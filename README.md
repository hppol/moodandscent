# Mood & Scent

오늘의 착장(OOTD) 사진과 일정·기분을 입력하면, 향수 DB(1,000개)에서 어울리는 **니치 향수 1개와 비슷한 향 구조의 가성비 대안 1개**를 추천하는 앱입니다.

AI가 향수 정보를 지어내지 않도록, **향수 이름·노트·향 계열은 항상 DB 값**을 사용하고 AI는 해석·선택·문구 작성만 맡습니다.

## 주요 기능

- **OOTD 추천**: 착장 사진 + 글 → 니치 픽 / 가성비 대안, 노트 피라미드, AI 무드보드 이미지
- **사진 없이 빠른 추천**: 전체 DB 또는 "내 향수(위시리스트·좋아요·착용 기록)" 안에서 추천
- **진열장 / 착용 캘린더**: 받은 추천 전부를 보관하고, 그중 실제로 뿌린 향수를 날짜별로 기록
- **향수 검색 · 상세 화면**: 노트, 비슷한 향수(유사도 계산), 나와의 기록, Fragrantica 링크
- **👍/👎 피드백**: 다음 추천에 반영 (👎한 향수는 후보에서 제외)
- **취향 리포트 · AI 검증 로그**: 향 계열 통계, AI가 받은 후보와 실제 선택 기록

## 추천이 만들어지는 과정

```
사진 ─ BLIP(착장 설명) ─┐
글 + 날씨 ──────────────┼─▶ ① AI: 원하는 향 특징 해석 (DB에 있는 단어만 허용)
                        │   ② 코드: DB 1,000개 점수 계산 → 후보 25개
                        │   ③ AI: 후보 중 id로 선택 (후보 밖이면 재요청 → 1순위로 대체)
                        │   ④ 코드: 노트·어코드 유사도로 가성비 대안 선택
                        │   ⑤ AI: DB 노트만 근거로 감성 문구 작성
                        └─▶ SD-Turbo: 무드보드 이미지 생성
```

## 기술 스택

| 영역 | 사용 기술 |
|---|---|
| 앱 | Flutter (웹 · Android · Windows) |
| 서버 | Python FastAPI (`backend/`) |
| AI | BLIP(사진 인식), Groq API(gpt-oss-20b / 120b), Stable Diffusion Turbo(이미지) |
| DB | 향수 DB: `backend/perfumes.json` · 사용자 기록: Firebase Firestore |

## 실행 방법

### 1. AI 서버 (`backend/`)

Python 3.12, NVIDIA GPU 권장 (없으면 CPU로 동작하지만 이미지 생성이 느림)

```bash
cd backend
python -m venv venv
venv\Scripts\activate            # macOS/Linux: source venv/bin/activate

# GPU용 PyTorch 먼저 설치 (GPU가 없으면 생략)
pip install torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cu130
pip install -r requirements.txt

copy .env.example .env           # 그리고 .env에 키 입력
python main.py                   # http://127.0.0.1:8000
```

처음 실행할 때 AI 모델(BLIP, SD-Turbo, 약 수 GB)을 자동으로 내려받아 시간이 걸립니다.

### 2. Firebase 연결

Firebase 연결 정보(`lib/firebase_options.dart` 등)는 저장소에 포함하지 않으므로 자신의 Firebase 프로젝트로 연결합니다.

1. [Firebase 콘솔](https://console.firebase.google.com)에서 프로젝트를 만들고 **Firestore Database** 생성
2. 프로젝트 폴더에서 연결 정보 생성
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure            # lib/firebase_options.dart 생성
   firebase deploy --only firestore:rules   # firestore.rules 적용
   ```
3. `backend/.env`의 `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`에 같은 프로젝트 값을 입력

### 3. 앱

```bash
flutter pub get
flutter run -d chrome            # 또는 -d edge, -d windows
```

휴대폰 실기기에서 테스트할 때는 `lib/config.dart`의 서버 주소를 PC의 IP로 바꿔주세요.

## 향수 DB 다시 만들기 (선택)

`backend/perfumes.json`이 이미 포함되어 있어 바로 실행됩니다. 개수를 바꾸거나 브랜드를 추가하려면:

1. Fragrantica 기반 공개 데이터셋(Kaggle "Fragrantica.com Fragrance Dataset"의 `fra_perfumes.csv`)을 받아 `backend/data/`에 넣기
2. `backend/brands.py`에서 브랜드 등급(니치/가성비) 수정
3. `python build_db.py --limit 1000` → `perfumes.json`, `perfumes_view.csv`(엑셀 보기용) 생성

## 데이터 출처

향수 이름·노트·향 계열·평점은 [Fragrantica](https://www.fragrantica.com) 기반 공개 데이터셋을 가공한 것이며, 비상업적 학습 목적으로 사용했습니다. 원본 데이터셋은 저장소에 포함하지 않습니다.
