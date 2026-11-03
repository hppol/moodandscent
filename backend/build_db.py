"""
향수 데이터베이스(perfumes.json) 생성 스크립트

사용법:
    python build_db.py                         # data/fra_perfumes.csv → perfumes.json (1000개)
    python build_db.py --limit 1500

데이터 출처: Fragrantica.com 기반 공개 데이터셋 (Kaggle "Fragrantica.com Fragrance Dataset"의 fra_perfumes.csv)
- brands.py에 등록된 브랜드만 사용합니다.
- 리뷰 수가 MIN_RATING_COUNT 이상인, 실제로 널리 알려진 향수만 사용합니다.
- 노트는 데이터셋의 설명 문장("Top notes are ...; middle notes are ...")에서 그대로 추출합니다.
"""
import argparse
import ast
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from brands import BRAND_TIERS, DISPLAY_NAMES, normalize_brand

MIN_RATING_COUNT = 50  # 리뷰가 너무 적은 향수는 제외
MIN_PER_BRAND = 6      # 니치 브랜드도 빠지지 않도록 브랜드별 최소 확보 개수
MAX_PER_BRAND = 20     # 한 브랜드가 DB를 독점하지 않도록 브랜드당 최대 개수
ACCORDS_KEPT = 5       # 가장 강한 어코드 5개만 사용

PYRAMID_RE = re.compile(r"Top notes? (?:is|are) (.*?); middle notes? (?:is|are) (.*?); base notes? (?:is|are) (.*?)\.(?:\s|$)")
FLAT_NOTES_RE = re.compile(r"(?:^|\.)\s*Notes? (?:is|are) (.*?)\.(?:\s|$)")
YEAR_RE = re.compile(r"was launched in (\d{4})")


def split_notes(text: str) -> list[str]:
    parts = re.split(r",\s*|\s+and\s+", text)
    return [p.strip().lower() for p in parts if p.strip()]


def to_int(value: str) -> int:
    try:
        return int(str(value).replace(",", "").strip() or 0)
    except ValueError:
        return 0


def parse_name_brand(row: dict) -> tuple[str, str]:
    """Name 컬럼('Santal 33 Le Labofor women and men')과 설명 문장('Santal 33byLe Labois a ...')을
    대조해 악센트/아포스트로피가 살아 있는 정식 표기를 복원합니다. 실패하면 URL 슬러그를 사용합니다."""
    gender, desc = row["Gender"], row["Description"]
    base = row["Name"][: -len(gender)] if gender and row["Name"].endswith(gender) else row["Name"]
    for i, ch in enumerate(base):
        if ch == " ":
            name, brand = base[:i], base[i + 1:]
            if desc.startswith(f"{name}by{brand}is"):
                return name.strip(), brand.strip()

    slug_name = re.sub(r"-\d+\.html$", "", row["url"].rstrip("/").split("/")[-1])
    return slug_name.replace("-", " "), ""


def parse_row(row: dict):
    url_parts = row["url"].split("/")
    if len(url_parts) < 6:
        return None
    brand_slug = url_parts[4]
    key = normalize_brand(brand_slug)
    tier = BRAND_TIERS.get(key)
    if not tier:
        return None

    rating_count = to_int(row["Rating Count"])
    if rating_count < MIN_RATING_COUNT:
        return None

    try:
        accords = [a.strip().lower() for a in ast.literal_eval(row["Main Accords"])][:ACCORDS_KEPT]
    except (ValueError, SyntaxError):
        accords = []
    if len(accords) < 3:
        return None

    desc = row["Description"]
    top = middle = base = notes = []
    if m := PYRAMID_RE.search(desc):
        top, middle, base = (split_notes(g) for g in m.groups())
    elif m := FLAT_NOTES_RE.search(desc):
        notes = split_notes(m.group(1))

    name, brand = parse_name_brand(row)
    year = YEAR_RE.search(desc)
    try:
        rating = float(row["Rating Value"])
    except ValueError:
        rating = None

    return {
        "id": re.sub(r"[^a-z0-9]+", "_", re.sub(r"\.html$", "", "_".join(url_parts[4:6])).lower()).strip("_"),
        "brand": brand or DISPLAY_NAMES[key],
        "brand_key": key,
        "name": name,
        "tier": tier,
        "gender": row["Gender"].replace("for ", "").strip() or "women and men",
        "year": int(year.group(1)) if year else None,
        "rating": rating,
        "rating_count": rating_count,
        "top": top,
        "middle": middle,
        "base": base,
        "notes": notes,  # 탑/미들/베이스 구분 없이 공개된 노트
        "accords": accords,
        "source_url": row["url"],
    }


def select(perfumes: list[dict], limit: int, affordable_ratio: float) -> list[dict]:
    """1단계: 브랜드마다 인기 상위 MIN_PER_BRAND개 확보 → 2단계: 남은 자리를 리뷰 수 순으로 채움"""
    quota = {"affordable": int(limit * affordable_ratio)}
    quota["luxury"] = limit - quota["affordable"]

    by_brand = defaultdict(list)
    for p in sorted(perfumes, key=lambda p: p["rating_count"], reverse=True):
        by_brand[p["brand_key"]].append(p)

    chosen, per_brand, per_tier = {}, Counter(), Counter()

    def take(p):
        if p["id"] in chosen or per_brand[p["brand_key"]] >= MAX_PER_BRAND or per_tier[p["tier"]] >= quota[p["tier"]]:
            return
        chosen[p["id"]] = p
        per_brand[p["brand_key"]] += 1
        per_tier[p["tier"]] += 1

    for items in by_brand.values():
        for p in items[:MIN_PER_BRAND]:
            take(p)
    for p in sorted(perfumes, key=lambda p: p["rating_count"], reverse=True):
        take(p)
    return sorted(chosen.values(), key=lambda p: p["rating_count"], reverse=True)


def main():
    sys.stdout.reconfigure(encoding="utf-8")  # Windows 콘솔(cp949)에서 이모지 출력 오류 방지
    here = Path(__file__).parent
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", nargs="?", default=str(here / "data" / "fra_perfumes.csv"))
    parser.add_argument("--limit", type=int, default=1000)
    parser.add_argument("--affordable-ratio", type=float, default=0.35)
    parser.add_argument("--out", default=str(here / "perfumes.json"))
    args = parser.parse_args()

    with open(args.csv_path, encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    parsed, seen = [], set()
    for row in rows:
        p = parse_row(row)
        if p and p["id"] not in seen:
            seen.add(p["id"])
            parsed.append(p)

    selected = select(parsed, args.limit, args.affordable_ratio)
    Path(args.out).write_text(json.dumps(selected, ensure_ascii=False, indent=1), encoding="utf-8")

    # 엑셀에서 바로 열어볼 수 있는 보기용 CSV (utf-8-sig: 엑셀 한글/악센트 깨짐 방지)
    view_path = Path(args.out).with_name("perfumes_view.csv")
    with open(view_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["등급", "브랜드", "향수명", "성별", "출시년도", "평점", "리뷰수", "주요 어코드", "탑", "미들", "베이스", "노트(구분없음)", "출처"])
        for p in selected:
            w.writerow([p["tier"], p["brand"], p["name"], p["gender"], p["year"] or "", p["rating"], p["rating_count"],
                        ", ".join(p["accords"]), ", ".join(p["top"]), ", ".join(p["middle"]), ", ".join(p["base"]),
                        ", ".join(p["notes"]), p["source_url"]])

    tiers = Counter(p["tier"] for p in selected)
    with_pyramid = sum(1 for p in selected if p["top"] or p["middle"] or p["base"])
    with_flat = sum(1 for p in selected if p["notes"])
    brands = Counter(DISPLAY_NAMES[p["brand_key"]] for p in selected)
    print(f"✅ {len(selected)}개 저장 → {args.out}")
    print(f"   luxury {tiers['luxury']} / affordable {tiers['affordable']}")
    print(f"   노트 피라미드 {with_pyramid}개, 단일 노트 목록 {with_flat}개, 어코드만 {len(selected) - with_pyramid - with_flat}개")
    print(f"   브랜드 {len(brands)}개:", ", ".join(f"{b} {n}" for b, n in brands.most_common()))
    missing = sorted(DISPLAY_NAMES[k] for k in BRAND_TIERS if DISPLAY_NAMES[k] not in brands)
    if missing:
        print(f"⚠️ 데이터셋에 없거나 조건(리뷰 {MIN_RATING_COUNT}개 이상)을 못 채운 브랜드:", ", ".join(missing))


if __name__ == "__main__":
    main()
