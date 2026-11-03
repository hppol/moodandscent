"""
서버에서 Firebase Firestore를 읽고 쓰는 도우미 (REST API 사용, 추가 패키지 없음)

- fetch_feedback(): 앱에서 남긴 👍/👎 피드백을 읽어 추천에 반영
- save_log_async(): 추천 1회마다 'AI 검증 로그'를 recommendation_logs 컬렉션에 기록 (응답 속도에 영향 없도록 백그라운드)
"""
import json
import os
import threading
import urllib.request
from datetime import datetime, timezone


def _config() -> tuple[str, str]:
    # .env는 main.py에서 load_dotenv()로 읽으므로, import 시점이 아니라 호출 시점에 확인
    return os.getenv("FIREBASE_PROJECT_ID", ""), os.getenv("FIREBASE_API_KEY", "")


def _request(method: str, path: str, body: dict | None = None) -> dict:
    project_id, api_key = _config()
    base_url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents"
    url = f"{base_url}/{path}{'&' if '?' in path else '?'}key={api_key}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read() or b"{}")


# ---------- Firestore 값 형식 <-> 파이썬 값 변환 ----------
def _encode(value):
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if value is None:
        return {"nullValue": None}
    if isinstance(value, datetime):
        return {"timestampValue": value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")}
    if isinstance(value, dict):
        return {"mapValue": {"fields": {k: _encode(v) for k, v in value.items()}}}
    if isinstance(value, (list, tuple, set)):
        return {"arrayValue": {"values": [_encode(v) for v in value]}}
    return {"stringValue": str(value)}


def _decode(value: dict):
    kind, raw = next(iter(value.items()))
    if kind == "integerValue":
        return int(raw)
    if kind == "mapValue":
        return {k: _decode(v) for k, v in raw.get("fields", {}).items()}
    if kind == "arrayValue":
        return [_decode(v) for v in raw.get("values", [])]
    return raw


def enabled() -> bool:
    return all(_config())


def fetch_feedback() -> list[dict]:
    """피드백 문서 목록 (실패하면 빈 목록 → 추천은 피드백 없이 정상 진행)"""
    if not enabled():
        return []
    try:
        return _list_docs("feedback")
    except Exception as e:
        print(f"Feedback fetch note: {e}")
        return []


def save_log_async(log_id: str, log: dict) -> None:
    if not enabled():
        return

    def _save():
        try:
            fields = {k: _encode(v) for k, v in {**log, "createdAt": datetime.now(timezone.utc)}.items()}
            _request("PATCH", f"recommendation_logs/{log_id}", {"fields": fields})
        except Exception as e:
            print(f"Log save note: {e}")

    threading.Thread(target=_save, daemon=True).start()


def _list_docs(collection: str) -> list[dict]:
    docs = _request("GET", f"{collection}?pageSize=300").get("documents", [])
    return [{k: _decode(v) for k, v in d.get("fields", {}).items()} for d in docs]


def fetch_my_perfume_ids() -> set[str]:
    """'내 향수' = 위시리스트 + 👍한 향수 + 착용 캘린더에 기록한 향수 (빠른 추천 '내 향수 안에서' 모드용)"""
    if not enabled():
        return set()
    ids = set()
    try:
        ids |= {d.get("perfumeId") for d in _list_docs("wishlist")}
        ids |= {d.get("perfumeId") for d in _list_docs("feedback") if d.get("vote") == 1}
        ids |= {(d.get("perfume") or {}).get("id") for d in _list_docs("wear_log")}
    except Exception as e:
        print(f"My perfumes fetch note: {e}")
    return {i for i in ids if i}
