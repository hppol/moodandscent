from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import torch
from PIL import Image
import io
import os
import base64
import json
import urllib.request
from dotenv import load_dotenv
from transformers import BlipProcessor, BlipForConditionalGeneration
from groq import Groq
from diffusers import AutoPipelineForText2Image
from pathlib import Path
from recommender import load_db, build_vocab, recommend, search_perfumes, similar_perfumes, MyPoolTooSmall
import firebase_store
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

# .env 파일 로드
load_dotenv()

app = FastAPI(title="Mood & Scent API")

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

device = "cuda" if torch.cuda.is_available() else "cpu"
dtype = torch.float16 if device == "cuda" else torch.float32

# ==========================================
# [Step 2] 로컬 비전 AI (BLIP) 세팅
# ==========================================
print("1/3. 로컬 비전 AI(BLIP)를 불러오는 중...")
processor = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base")
vision_model = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-base").to(device)
print("✅ BLIP 모델 로드 완료!")

# ==========================================
# [Step 3] 외부 AI (Groq API) 세팅
# ==========================================
print("2/3. Groq API 연동 중...")
groq_api_key = os.getenv("GROQ_API_KEY")
client = Groq(api_key=groq_api_key)
print("✅ Groq API 키 로드 완료!")

# ==========================================
# 향수 DB 로드 (build_db.py로 생성한 perfumes.json)
# ==========================================
DB_PATH = Path(__file__).with_name("perfumes.json")
if not DB_PATH.exists():
    raise SystemExit("❌ perfumes.json이 없습니다. 먼저 `python build_db.py <데이터셋.csv>`를 실행하세요.")
perfume_db = load_db(DB_PATH)
perfume_vocab = build_vocab(perfume_db)
print(f"✅ 향수 DB 로드 완료! ({len(perfume_db)}개)")

# ==========================================
# [Step 4] 로컬 이미지 생성 AI (Stable Diffusion Turbo) 세팅
# ==========================================
print("3/3. 로컬 이미지 생성 AI(SD-Turbo)를 불러오는 중... (최초 실행 시 용량이 커서 오래 걸립니다!)")
sd_pipe = AutoPipelineForText2Image.from_pretrained(
    "stabilityai/sd-turbo", 
    torch_dtype=dtype, 
    variant="fp16" if device == "cuda" else None
).to(device)
print("✅ Stable Diffusion 로드 완료! 서버 준비 끝!")


@app.get("/")
def read_root():
    return {"message": "Welcome to Mood & Scent API. Backend is fully running!"}

@app.get("/perfumes/search")
def search(q: str = "", limit: int = 30):
    """향수 DB 검색 (앱의 향수 검색 화면). 사실 정보만 반환하고 AI는 사용하지 않음"""
    return {"results": search_perfumes(perfume_db, q, min(limit, 50))}

@app.get("/perfumes/similar")
def similar(id: str, limit: int = 5):
    """향수 상세 화면의 '비슷한 향수' (노트·어코드 유사도 계산, AI 없음)"""
    return {"results": similar_perfumes(perfume_db, id, min(limit, 10))}


_executor = ThreadPoolExecutor(max_workers=4)
_weather_cache = {"at": 0.0, "value": None}


def get_weather() -> tuple[str, str]:
    """목포 실시간 날씨 (Open-Meteo, 10분간 재사용). 실패하면 기본 문구"""
    if _weather_cache["value"] and time.time() - _weather_cache["at"] < 600:
        return _weather_cache["value"]
    lat, lon = 34.8118, 126.3922
    weather_text, weather_badge = "선선한 가을 날씨", "MOKPO 24°C · 구름 조금"
    try:
        weather_url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
        req = urllib.request.Request(weather_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3) as resp:
            w_data = json.loads(resp.read().decode('utf-8'))
            temp = w_data.get("current_weather", {}).get("temperature", 24)
            code = w_data.get("current_weather", {}).get("weathercode", 0)
            temp_int = round(temp)
            cond = "맑음" if code == 0 else "구름 조금" if code in [1, 2, 3] else "비/흐림"
            weather_text = f"현재 목포 기온 {temp_int}℃, 날씨 {cond}"
            weather_badge = f"MOKPO {temp_int}°C · {cond}"
            _weather_cache.update(at=time.time(), value=(weather_text, weather_badge))
    except Exception as e:
        print(f"Weather API note: {e}")
    return weather_text, weather_badge


def curate(image_bytes: bytes | None, mood_text: str, scope: str = "all") -> dict:
    """추천 전체 과정. image_bytes가 없으면 빠른 추천(사진 인식 생략),
    scope='mine'이면 내 향수(위시리스트·좋아요·착용 기록) 안에서만 추천"""
    started = time.perf_counter()
    # 날씨·피드백·내 향수 목록은 사진 인식/AI 해석과 동시에 가져옴
    weather_future = _executor.submit(get_weather)
    feedback_future = _executor.submit(firebase_store.fetch_feedback)  # 앱에서 남긴 👍/👎 반영
    pool_future = _executor.submit(firebase_store.fetch_my_perfume_ids) if scope == "mine" else None

    # 1. BLIP: 사진에서 착장 설명 추출 (빠른 추천이면 생략)
    t = time.perf_counter()
    if image_bytes:
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        inputs = processor(pil_image, return_tensors="pt").to(device)
        out = vision_model.generate(**inputs, max_new_tokens=50)
        image_caption = processor.decode(out[0], skip_special_tokens=True)
    else:
        image_caption = "(no outfit photo provided)"
    blip_seconds = time.perf_counter() - t
    weather_text, weather_badge = weather_future.result()

    # 2. DB 기반 추천: AI는 해석/선택/문구만, 향수 정보는 perfumes.json에서
    result = recommend(client, perfume_db, perfume_vocab, image_caption, mood_text, weather_text,
                       feedback_future, pool_ids=pool_future)
    copy = result["copy"]
    raw_sd_prompt = copy.get("sd_prompt_en", "aesthetic luxury perfume moodboard, minimalist, soft light")
    # SD-Turbo 이미지 퀄리티를 극대화하는 키워드 보강
    enhanced_sd_prompt = f"{raw_sd_prompt}, award-winning editorial still life photography, cinematic warm lighting, sharp focus, 8k uhd, aesthetic minimalism, high resolution"

    # 3. Stable Diffusion: 무드보드 이미지 생성 (GPU에서 1초 미만)
    t = time.perf_counter()
    sd_image = sd_pipe(prompt=enhanced_sd_prompt, num_inference_steps=4, guidance_scale=0.0).images[0]
    buffered = io.BytesIO()
    sd_image.save(buffered, format="JPEG", quality=95)
    img_base64 = base64.b64encode(buffered.getvalue()).decode("utf-8")
    sd_seconds = time.perf_counter() - t

    # 4. AI 검증 로그를 Firestore에 기록 (백그라운드, 응답 속도 영향 없음)
    trace = result["trace"]
    trace["timings"].update(blip=round(blip_seconds, 2), image=round(sd_seconds, 2),
                            total=round(time.perf_counter() - started, 2))
    trace["mode"] = ("photo" if image_bytes else "quick") + ("_mine" if scope == "mine" else "")
    log_id = uuid.uuid4().hex[:12]
    firebase_store.save_log_async(log_id, {
        "moodText": mood_text,
        "imageCaption": image_caption,
        "weather": weather_text,
        "luxury": f'{result["luxury"]["brand"]} - {result["luxury"]["name"]}',
        "affordable": f'{result["affordable"]["brand"]} - {result["affordable"]["name"]}',
        **trace,
    })

    return {
        "status": "success",
        "log_id": log_id,
        "mode": trace["mode"],
        "weather_badge": weather_badge,
        "killing_quote": copy.get("killing_quote_kr", "오늘의 시그니처 향기"),
        "luxury_perfume": result["luxury"],
        "affordable_perfume": result["affordable"],
        "taste_summary": result["profile"].get("summary_kr", ""),
        "visualized_ingredients": copy.get("visualized_ingredients_kr", "향 노트 오브제"),
        "tpo_analysis": copy.get("tpo_analysis_kr", ""),
        "sd_prompt": raw_sd_prompt,
        "generated_image_base64": img_base64
    }


@app.post("/analyze")
async def analyze_mood(
    image: UploadFile = File(...),
    mood_text: str = Form(...)
):
    try:
        return curate(await image.read(), mood_text)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"status": "error", "message": str(e)}


@app.post("/quick")
async def quick_recommend(
    mood_text: str = Form(...),
    scope: str = Form("all")  # all: 전체 DB / mine: 내 향수(위시·좋아요·착용) 안에서
):
    """⚡ 빠른 추천: 사진 없이 글 + 날씨만으로 추천"""
    try:
        return curate(None, mood_text, "mine" if scope == "mine" else "all")
    except MyPoolTooSmall as e:
        return {"status": "error", "message": str(e)}
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"status": "error", "message": str(e)}


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
