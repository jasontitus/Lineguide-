"""Kokoro-MLX TTS server for LineGuide.

Serves high-quality neural TTS via a lightweight HTTP API.
Runs on Apple Silicon using MLX for fast inference.

Usage:
    pip install -r requirements.txt
    python kokoro_server.py [--host 0.0.0.0] [--port 8787]
"""

import argparse
import io
import time
from contextlib import asynccontextmanager
from pathlib import Path

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Kokoro-MLX model (lazy-loaded at startup)
# ---------------------------------------------------------------------------

_pipeline = None

# Available Kokoro voices — short IDs mapped to full voice names.
# See https://huggingface.co/hexgrad/Kokoro-82M for the full voice list.
VOICES = {
    # American Female
    "af_heart": "af_heart",
    "af_alloy": "af_alloy",
    "af_aoede": "af_aoede",
    "af_bella": "af_bella",
    "af_jessica": "af_jessica",
    "af_kore": "af_kore",
    "af_nicole": "af_nicole",
    "af_nova": "af_nova",
    "af_river": "af_river",
    "af_sarah": "af_sarah",
    "af_sky": "af_sky",
    # American Male
    "am_adam": "am_adam",
    "am_echo": "am_echo",
    "am_eric": "am_eric",
    "am_fenrir": "am_fenrir",
    "am_liam": "am_liam",
    "am_michael": "am_michael",
    "am_onyx": "am_onyx",
    "am_puck": "am_puck",
    # British Female
    "bf_alice": "bf_alice",
    "bf_emma": "bf_emma",
    "bf_isabella": "bf_isabella",
    "bf_lily": "bf_lily",
    # British Male
    "bm_daniel": "bm_daniel",
    "bm_fable": "bm_fable",
    "bm_george": "bm_george",
    "bm_lewis": "bm_lewis",
}

DEFAULT_VOICE = "af_heart"


def _load_pipeline():
    """Load the Kokoro-MLX pipeline (downloads weights on first run)."""
    global _pipeline
    from kokoro import KPipeline

    _pipeline = KPipeline(lang_code="a")  # 'a' = American English
    return _pipeline


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model on startup."""
    print("Loading Kokoro-MLX model …")
    t0 = time.time()
    _load_pipeline()
    print(f"Kokoro-MLX ready in {time.time() - t0:.1f}s")
    yield


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="LineGuide Kokoro-MLX TTS",
    version="1.0.0",
    lifespan=lifespan,
)


class SynthesizeRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000)
    voice: str = Field(default=DEFAULT_VOICE)
    speed: float = Field(default=1.0, ge=0.5, le=2.0)


@app.get("/health")
async def health():
    return {"status": "ok", "model": "kokoro-mlx", "voices": len(VOICES)}


@app.get("/voices")
async def list_voices():
    return {"voices": list(VOICES.keys()), "default": DEFAULT_VOICE}


@app.post("/synthesize")
async def synthesize(req: SynthesizeRequest):
    if _pipeline is None:
        raise HTTPException(503, "Model not loaded")

    voice = req.voice if req.voice in VOICES else DEFAULT_VOICE

    t0 = time.time()

    # Kokoro pipeline returns generator of (graphemes, phonemes, audio) tuples.
    # Concatenate all audio segments for the full utterance.
    segments = []
    for _gs, _ps, audio in _pipeline(req.text, voice=voice, speed=req.speed):
        segments.append(audio)

    if not segments:
        raise HTTPException(422, "No audio generated for input text")

    # Concatenate and encode as WAV
    full_audio = np.concatenate(segments) if len(segments) > 1 else segments[0]

    buf = io.BytesIO()
    sf.write(buf, full_audio, 24000, format="WAV")
    wav_bytes = buf.getvalue()

    elapsed = time.time() - t0
    duration = len(full_audio) / 24000
    print(
        f"Synthesized {len(req.text)} chars → {duration:.1f}s audio "
        f"in {elapsed:.2f}s (RTF={elapsed/duration:.2f}x) voice={voice}"
    )

    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={
            "X-Audio-Duration": f"{duration:.3f}",
            "X-Inference-Time": f"{elapsed:.3f}",
        },
    )


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    parser = argparse.ArgumentParser(description="Kokoro-MLX TTS server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()

    uvicorn.run(app, host=args.host, port=args.port)
