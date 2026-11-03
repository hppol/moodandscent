"""
DB 기반 향수 추천 엔진

AI는 향수 정보를 '생성'하지 않고, 아래 역할만 맡습니다.
  1) interpret_request : 사용자의 착장/상황/날씨를 '원하는 향의 특징(어코드, 노트)'으로 해석
  2) choose_luxury     : 코드가 DB에서 추린 후보 중에서 하나를 id로 선택 (DB에 없는 id면 거절)
  3) write_copy        : DB에 있는 노트만 근거로 감성 문구 작성

향수 이름, 브랜드, 노트, 어코드는 항상 DB 값을 그대로 사용합니다.
가성비 대안은 AI가 아니라 코드가 노트/어코드 유사도를 계산해서 고릅니다.
"""
import json
import math
import time
from collections import Counter
from pathlib import Path

# 단순한 작업(취향 해석, 후보 중 선택)은 빠른 모델, 감성 문구는 품질 좋은 모델.
# Groq 응답이 가끔 10~30초씩 지연되므로, 시간 안에 답이 없으면 끊고 빠른 모델로 다시 요청합니다.
FAST_MODEL = "openai/gpt-oss-20b"
WRITER_MODEL = "openai/gpt-oss-120b"
BACKUP_MODEL = "qwen/qwen3.8-27b"
FAST_TIMEOUT = 6.0     # 초
WRITER_TIMEOUT = 7.0   # 초
# Groq 무료 요금제는 모델마다 분당 토큰 한도가 따로 있으므로, 한도·지연 시 다른 모델로 넘김
LUXURY_CANDIDATES = 25
ACCORD_WEIGHTS = [1.0, 0.9, 0.8, 0.7, 0.6]  # mainaccord1이 가장 지배적인 향


# ==========================================
# DB 로드
# ==========================================
def load_db(path: Path) -> list[dict]:
    db = json.loads(path.read_text(encoding="utf-8"))
    for p in db:
        p["all_notes"] = set(p["top"] + p["middle"] + p["base"] + p.get("notes", []))
    return db


def build_vocab(db: list[dict]) -> dict:
    """AI가 해석 결과를 DB에 실제로 존재하는 단어로만 말하도록 어휘 목록을 만듭니다."""
    accords = Counter(a for p in db for a in p["accords"])
    notes = Counter(n for p in db for n in p["all_notes"])
    return {
        "accords": [a for a, _ in accords.most_common()],
        "notes": [n for n, _ in notes.most_common(150)],
    }


# ==========================================
# 점수 계산 (순수 코드, AI 없음)
# ==========================================
def _gender_tag(gender: str) -> str:
    """데이터셋 표기('women', 'men', 'for women and men', 'unisex' 등)를 3가지로 통일"""
    has_women = "women" in gender
    has_men = "men" in gender.replace("women", "")
    if has_women and not has_men:
        return "feminine"
    if has_men and not has_women:
        return "masculine"
    return "unisex"


def _gender_ok(perfume: dict, wanted: str) -> bool:
    return wanted == "any" or _gender_tag(perfume.get("gender", "unisex")) in (wanted, "unisex")


def profile_score(perfume: dict, profile: dict) -> float:
    wanted_accords = set(profile.get("accords", []))
    wanted_notes = set(profile.get("notes", []))
    avoid = set(profile.get("avoid", []))

    score = sum(w for a, w in zip(perfume["accords"], ACCORD_WEIGHTS) if a in wanted_accords) * 2
    score += len(perfume["all_notes"] & wanted_notes) * 1.0
    score -= sum(w for a, w in zip(perfume["accords"], ACCORD_WEIGHTS) if a in avoid) * 3
    score -= len(perfume["all_notes"] & avoid) * 1.5
    score += math.log10(perfume.get("rating_count", 0) + 1) * 0.3  # 검증된 대중성 소폭 가산
    # 사용자 피드백(👍한 향수들의 어코드) 반영
    liked = profile.get("liked_accords", {})
    score += sum(w * liked.get(a, 0) for a, w in zip(perfume["accords"], ACCORD_WEIGHTS)) * 0.5
    return score


def similarity(a: dict, b: dict) -> tuple[float, list[str], list[str]]:
    """두 향수의 유사도(0~1)와 공통 노트, 공통 어코드"""
    acc_a, acc_b = set(a["accords"]), set(b["accords"])
    shared_accords = [x for x in a["accords"] if x in acc_b]
    shared_notes = sorted(a["all_notes"] & b["all_notes"])
    jac_acc = len(acc_a & acc_b) / max(len(acc_a | acc_b), 1)
    jac_notes = len(a["all_notes"] & b["all_notes"]) / max(len(a["all_notes"] | b["all_notes"]), 1)
    return 0.6 * jac_acc + 0.4 * jac_notes, shared_notes, shared_accords


def _usable(p: dict, profile: dict, tier: str) -> bool:
    return (p["tier"] == tier and p["id"] not in profile.get("disliked_ids", set())
            and _gender_ok(p, profile.get("gender", "any")))


def top_candidates(db: list[dict], profile: dict, tier: str, k: int) -> list[dict]:
    pool = [p for p in db if _usable(p, profile, tier)]
    return sorted(pool, key=lambda p: profile_score(p, profile), reverse=True)[:k]


def pick_dupe(db: list[dict], luxury: dict, profile: dict) -> tuple[dict, float, list[str], list[str]]:
    """럭셔리 픽과 향 구조가 가장 비슷한 가성비 향수 (유사도 70% + 사용자 취향 30%)"""
    pool = [p for p in db if _usable(p, profile, "affordable")]
    pool = pool or [p for p in db if p["tier"] == "affordable"]
    max_pref = max((profile_score(p, profile) for p in pool), default=1) or 1

    best = max(pool, key=lambda p: 0.7 * similarity(luxury, p)[0] + 0.3 * profile_score(p, profile) / max_pref)
    sim, shared_notes, shared_accords = similarity(luxury, best)
    return best, sim, shared_notes, shared_accords


# ==========================================
# AI 호출
# ==========================================
def _ask_json(client, system: str, user: str, temperature: float = 0.4,
              model: str = FAST_MODEL, timeout: float = FAST_TIMEOUT, used: list | None = None) -> dict:
    """JSON 응답 요청. 제한 시간 초과·사용량 한도·오류 시 다른 모델로 다시 요청 (used에 실제 사용 모델 기록)"""
    other = WRITER_MODEL if model == FAST_MODEL else FAST_MODEL
    attempts = [(model, timeout), (other, 15.0), (BACKUP_MODEL, 20.0)]
    for i, (m, t) in enumerate(attempts):
        try:
            kwargs = dict(
                messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
                model=m,
                response_format={"type": "json_object"},
                temperature=temperature,
            )
            if m.startswith("openai/gpt-oss"):
                kwargs["reasoning_effort"] = "low" if m == FAST_MODEL else "medium"
            res = client.with_options(timeout=t, max_retries=0).chat.completions.create(**kwargs)
            if used is not None:
                used.append(m if i == 0 else f"{m} (재요청)")
            return json.loads(res.choices[0].message.content)
        except Exception as e:
            if i == len(attempts) - 1:
                raise
            print(f"LLM note: {m} {type(e).__name__} → {attempts[i + 1][0]}로 재요청")


def interpret_request(client, vocab: dict, caption: str, mood_text: str, weather_text: str,
                      used: list | None = None) -> dict:
    system = f"""
    You are a fragrance consultant. Translate the user's outfit, situation and the weather
    into the scent profile they would want. Do NOT name any perfume.
    Use ONLY words from these vocabularies (exact lowercase spelling):
    ACCORDS: {", ".join(vocab["accords"])}
    NOTES: {", ".join(vocab["notes"])}

    Return JSON:
    {{
      "accords": [3-6 accords that fit],
      "notes": [3-8 notes that fit],
      "avoid": [accords or notes to avoid, e.g. heavy ones for a small classroom; may be empty],
      "gender": "any" | "feminine" | "masculine"   (use "any" unless the user explicitly asks),
      "summary_kr": "해석한 취향을 한 문장으로 요약"
    }}
    """
    user = f"Current weather: {weather_text}\nOutfit from photo: {caption}\nUser message: {mood_text}"
    profile = _ask_json(client, system, user, used=used)

    # AI가 어휘 밖의 단어를 써도 DB와 매칭되는 단어만 남김
    accord_set, note_set = set(vocab["accords"]), set(vocab["notes"])
    profile["accords"] = [a for a in profile.get("accords", []) if a in accord_set]
    profile["notes"] = [n for n in profile.get("notes", []) if n in note_set]
    profile["avoid"] = [x for x in profile.get("avoid", []) if x in accord_set or x in note_set]
    if profile.get("gender") not in ("any", "feminine", "masculine"):
        profile["gender"] = "any"
    return profile


def _candidate_line(p: dict) -> str:
    return (f'{p["id"]} | {p["brand"]} - {p["name"]} | accords: {", ".join(p["accords"])} | '
            f'notes: {", ".join(sorted(p["all_notes"])[:8])}')


def choose_luxury(client, candidates: list[dict], caption: str, mood_text: str, weather_text: str,
                  attempts: list[str], used: list | None = None) -> tuple[dict, bool]:
    """AI가 후보 목록 안에서만 고르게 하고, 목록 밖 id면 재시도 후 1순위 후보로 대체.
    attempts에는 AI가 실제로 답한 id가 순서대로 기록되고, 대체 여부를 함께 반환합니다."""
    by_id = {p["id"]: p for p in candidates}
    system = f"""
    You are a master perfumer. Choose the ONE perfume from the CANDIDATES list that best fits
    the user's outfit, situation and weather. You MUST answer with an id copied exactly from the list.
    CANDIDATES (id | name | accords | notes):
    {chr(10).join(_candidate_line(p) for p in candidates)}

    Return JSON: {{"id": "<candidate id>"}}
    """
    user = f"Current weather: {weather_text}\nOutfit from photo: {caption}\nUser message: {mood_text}"

    for _ in range(2):
        chosen = str(_ask_json(client, system, user, temperature=0.5, used=used).get("id", ""))
        attempts.append(chosen)
        if chosen in by_id:
            return by_id[chosen], False
        user += f'\n(Your previous answer "{chosen}" is not in the list. Pick an id from the list.)'
    return candidates[0], True


def write_copy(client, luxury: dict, dupe: dict, shared_notes: list[str],
               caption: str, mood_text: str, weather_text: str, mine: bool = False,
               used: list | None = None) -> dict:
    def facts(p):
        lines = [f'{p["brand"]} - {p["name"]}', f'  Main accords (strongest first): {", ".join(p["accords"])}']
        if p["top"] or p["middle"] or p["base"]:
            lines += [f'  Top: {", ".join(p["top"])}', f'  Heart: {", ".join(p["middle"])}',
                      f'  Base: {", ".join(p["base"])}']
        elif p.get("notes"):
            lines.append(f'  Notes: {", ".join(p["notes"])}')
        else:
            lines.append("  Notes: not published -> describe the smell using the main accords only")
        return "\n".join(lines)

    system = f"""
    You are a witty high-fashion magazine editor and perfumer writing in Korean.
    The perfumes are already chosen. Here are their VERIFIED facts from the database:

    [{"TODAY'S PICK (from the user's own collection)" if mine else "LUXURY PICK"}]
    {facts(luxury)}

    [{"ANOTHER OPTION (also from the user's own collection)" if mine else "AFFORDABLE ALTERNATIVE"}]
    {facts(dupe)}
    Shared notes: {", ".join(shared_notes) or "none"}

    🚨 GROUNDING RULES:
    - When describing smell, mention ONLY ingredients/accords listed for that perfume above.
    - NEVER state price, launch year, perfumer, concentration, longevity numbers or any fact not given above.
    - {"Both perfumes are ones the user already likes/owns/wants; do not call either a dupe or budget option."
       if mine else "Do not claim the alternative is an official dupe; say it shares a similar scent structure."}

    Return JSON:
    {{
      "luxury_description_kr": "누구나 상상할 수 있는 생생한 냄새 묘사 1~2문장 (위 노트 기반)",
      "luxury_reason_kr": "착장/상황과 이 향의 케미를 위트 있는 패션 에디터 말투로 2문장",
      "affordable_description_kr": "냄새 묘사 1~2문장 (위 노트 기반)",
      "affordable_reason_kr": "{"오늘 상황에서 또 다른 선택지로서의 매력 2문장" if mine else "가성비 데일리 대안으로서의 매력 2문장"}",
      "killing_quote_kr": "잡지 커버용 감성 한 줄 카피",
      "tpo_analysis_kr": "유저 상황 맞춤 위트 있는 에티켓 팁 2문장",
      "visualized_ingredients_kr": "이미지에 등장시킬 럭셔리 픽 노트 재료 3~4개 (한국어, 쉼표 구분)",
      "sd_prompt_en": "high-end luxury perfume still life photography, elegant glass bottle, [3-5 tangible ingredients from the LUXURY notes], warm golden hour light, minimalist marble and linen, 35mm film, Kinfolk style, no humans, no text"
    }}
    """
    user = f"Current weather: {weather_text}\nOutfit from photo: {caption}\nUser message: {mood_text}"
    return _ask_json(client, system, user, temperature=0.7, model=WRITER_MODEL, timeout=WRITER_TIMEOUT, used=used)


# ==========================================
# 앱으로 보낼 카드 데이터 (사실 정보는 전부 DB 값)
# ==========================================
def _notes_text(p: dict) -> str:
    def fmt(notes):
        return ", ".join(n.title() for n in notes)

    if p["top"] or p["middle"] or p["base"]:
        return " | ".join(f"{label}: {fmt(n)}" for label, n in
                          (("Top", p["top"]), ("Heart", p["middle"]), ("Base", p["base"])) if n)
    if p.get("notes"):
        return f"Notes: {fmt(p['notes'])}"
    return f"Main Accords: {fmt(p['accords'])}"


def to_card(p: dict, description: str, reason: str, match_reason: str) -> dict:
    return {
        "id": p["id"],
        "brand": p["brand"],
        "name": p["name"],
        "tier": p["tier"],
        "price_range": "",  # 데이터셋에 가격이 없어 표시하지 않음 (추측 금지)
        "scent_notes": _notes_text(p),
        # 앱에서 탑/미들/베이스를 층별로 보여주기 위한 원본 목록
        "top_notes": p["top"],
        "middle_notes": p["middle"],
        "base_notes": p["base"],
        "notes": p.get("notes", []),
        "accords": p["accords"],
        "rating": p.get("rating"),
        "rating_count": p.get("rating_count"),
        "gender": p.get("gender", ""),
        "year": p.get("year"),
        "source_url": p.get("source_url", ""),
        "match_reason": match_reason,
        "scent_description_kr": description,
        "reason_kr": reason,
    }


def feedback_to_profile(feedback: list[dict], db_by_id: dict) -> dict:
    """Firestore의 👍/👎 피드백을 추천 점수에 쓸 형태로 변환"""
    disliked = {f["perfumeId"] for f in feedback if f.get("vote") == -1}
    liked_accords = Counter()
    for f in feedback:
        p = db_by_id.get(f.get("perfumeId"))
        if f.get("vote") == 1 and p:
            liked_accords.update(p["accords"][:3])
    total = sum(liked_accords.values()) or 1
    return {"disliked_ids": disliked, "liked_accords": {a: n / total * 3 for a, n in liked_accords.items()}}


class MyPoolTooSmall(Exception):
    pass


def recommend(client, db: list[dict], vocab: dict, caption: str, mood_text: str, weather_text: str,
              feedback: list[dict] | None = None, pool_ids: set[str] | None = None) -> dict:
    """pool_ids가 주어지면 '내 향수(위시·좋아요·착용)' 안에서만 추천하고,
    두 번째 카드는 가성비 대안 대신 '내 향수 중 다음으로 잘 맞는 향수'가 됩니다."""
    timings, attempts, models_used = {}, [], {}

    t = time.perf_counter()
    models_used["interpret"] = []
    profile = interpret_request(client, vocab, caption, mood_text, weather_text, models_used["interpret"])
    timings["interpret"] = time.perf_counter() - t
    # feedback / pool_ids는 서버가 AI 해석과 동시에 Firestore에서 읽어 오도록 Future로 넘길 수 있음
    if hasattr(feedback, "result"):
        feedback = feedback.result()
    if hasattr(pool_ids, "result"):
        pool_ids = pool_ids.result()
    profile.update(feedback_to_profile(feedback or [], {p["id"]: p for p in db}))

    mine = pool_ids is not None
    if mine:
        pool = [p for p in db if p["id"] in pool_ids and p["id"] not in profile["disliked_ids"]]
        if len(pool) < 2:
            raise MyPoolTooSmall("내 향수가 2개 이상 필요해요. 위시리스트·좋아요·착용 기록에 향수를 더 담아주세요.")
        candidates = sorted(pool, key=lambda p: profile_score(p, profile), reverse=True)[:LUXURY_CANDIDATES]
    else:
        candidates = top_candidates(db, profile, "luxury", LUXURY_CANDIDATES)

    t = time.perf_counter()
    models_used["choose"] = []
    luxury, fallback_used = choose_luxury(client, candidates, caption, mood_text, weather_text, attempts,
                                          models_used["choose"])
    timings["choose"] = time.perf_counter() - t

    if mine:
        dupe = next(p for p in candidates if p["id"] != luxury["id"])
        sim, shared_notes, shared_accords = similarity(luxury, dupe)
    else:
        dupe, sim, shared_notes, shared_accords = pick_dupe(db, luxury, profile)

    t = time.perf_counter()
    models_used["copy"] = []
    copy = write_copy(client, luxury, dupe, shared_notes, caption, mood_text, weather_text, mine, models_used["copy"])
    timings["copy"] = time.perf_counter() - t

    def matched_keywords(p):
        return [a for a in p["accords"] if a in profile["accords"]] + sorted(p["all_notes"] & set(profile["notes"]))

    matched = matched_keywords(luxury)
    luxury_reason = f"취향 키워드 일치: {', '.join(matched)}" if matched else "착장·상황 종합 판단"
    shared = ", ".join(n.title() for n in (shared_notes or shared_accords)[:5])
    if mine:
        dupe_matched = matched_keywords(dupe)
        dupe_reason = "내 향수 중 다음으로 잘 맞는 향" + (f" · 취향 키워드 일치: {', '.join(dupe_matched)}" if dupe_matched else "")
    else:
        dupe_reason = f"럭셔리 픽과 향 구조 유사도 {round(sim * 100)}%" + (f" · 공통: {shared}" if shared else "")

    # 추천 로그용 기록: AI가 실제로 무엇을 골랐고 검증을 통과했는지
    trace = {
        "profile": {k: profile.get(k) for k in ("accords", "notes", "avoid", "gender", "summary_kr")},
        "candidates": [f'{p["brand"]} - {p["name"]}' for p in candidates],
        "candidate_ids": [p["id"] for p in candidates],
        "ai_attempts": attempts,
        "first_try_valid": bool(attempts) and attempts[0] in {p["id"] for p in candidates},
        "fallback_used": fallback_used,
        "luxury_id": luxury["id"],
        "affordable_id": dupe["id"],
        "dupe_similarity": round(sim, 3),
        "feedback_used": {"disliked": len(profile["disliked_ids"]), "liked_accords": sorted(profile["liked_accords"])},
        "timings": {k: round(v, 2) for k, v in timings.items()},
        "models": {k: ", ".join(v) for k, v in models_used.items()},
    }

    return {
        "profile": profile,
        "luxury": to_card(luxury, copy.get("luxury_description_kr", ""), copy.get("luxury_reason_kr", ""), luxury_reason),
        "affordable": to_card(dupe, copy.get("affordable_description_kr", ""), copy.get("affordable_reason_kr", ""), dupe_reason),
        "copy": copy,
        "trace": trace,
    }


# ==========================================
# 향수 검색 (앱의 검색 화면용, AI 없음)
# ==========================================
def _normalize(text: str) -> str:
    import unicodedata
    s = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    return " ".join("".join(ch if ch.isalnum() else " " for ch in s).split())


def search_perfumes(db: list[dict], query: str, limit: int = 30) -> list[dict]:
    """브랜드·이름에 검색어의 모든 단어가 들어간 향수 (검색어가 비면 리뷰 많은 순)"""
    tokens = _normalize(query).split()
    if not tokens:
        hits = db
    else:
        hits = []
        for p in db:
            haystack = p.setdefault("_search_key", _normalize(f'{p["brand"]} {p["name"]}'))
            if all(t in haystack for t in tokens):
                hits.append(p)
        # 이름이 검색어로 시작하는 향수를 먼저
        hits.sort(key=lambda p: (not _normalize(p["name"]).startswith(tokens[0]), -p.get("rating_count", 0)))
    if not tokens:
        hits = sorted(hits, key=lambda p: -p.get("rating_count", 0))
    return [to_card(p, "", "", "") for p in hits[:limit]]


def similar_perfumes(db: list[dict], perfume_id: str, limit: int = 5) -> list[dict]:
    """노트·어코드 유사도가 높은 향수 (상세 화면의 '비슷한 향수'). AI 없음"""
    base = next((p for p in db if p["id"] == perfume_id), None)
    if base is None:
        return []
    scored = sorted(((similarity(base, p), p) for p in db if p["id"] != base["id"]),
                    key=lambda x: x[0][0], reverse=True)[:limit]
    cards = []
    for (sim, shared_notes, shared_accords), p in scored:
        shared = ", ".join(n.title() for n in (shared_notes or shared_accords)[:4])
        cards.append(to_card(p, "", "", f"유사도 {round(sim * 100)}%" + (f" · 공통: {shared}" if shared else "")))
    return cards
