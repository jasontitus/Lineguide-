# Kokoro-MLX TTS Server

Fast neural text-to-speech for LineGuide, powered by [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) running on Apple Silicon via MLX.

## Setup

```bash
# Requires Python 3.10+ and Apple Silicon Mac
pip install -r requirements.txt
python kokoro_server.py
```

The server starts on `http://localhost:8787`. The MLX model weights (~80 MB) are downloaded automatically on first launch.

## API

### `GET /health`
Returns server status.

### `GET /voices`
Lists available voice IDs.

### `POST /synthesize`
```json
{
  "text": "To be or not to be, that is the question.",
  "voice": "af_heart",
  "speed": 1.0
}
```
Returns `audio/wav` response.

## Voices

| Prefix | Category |
|--------|----------|
| `af_*` | American Female |
| `am_*` | American Male |
| `bf_*` | British Female |
| `bm_*` | British Male |

Default voice: `af_heart`

## Flutter Integration

The LineGuide app connects to this server automatically. Configure the URL in settings if running on a different host/port.
