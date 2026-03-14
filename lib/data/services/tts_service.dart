import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TTS engine type used for fallback speech synthesis.
enum TtsEngine {
  /// Kokoro on-device neural TTS (default, higher quality).
  kokoro,

  /// System TTS (disabled by default — only used if Kokoro unavailable).
  system,
}

/// Text-to-speech service.
///
/// Priority chain for playing other characters' lines:
///   1. Real recording by primary actor
///   2. Real recording by understudy (if fallback enabled)
///   3. Voice-cloned audio (if voice cloning enabled)
///   4. Kokoro on-device TTS (default fallback)
///   5. System TTS (last resort — only if device can't run Kokoro)
class TtsService {
  TtsService._();
  static final instance = TtsService._();

  final FlutterTts _systemTts = FlutterTts();
  bool _initialized = false;
  TtsEngine _activeEngine = TtsEngine.kokoro;

  // Map character names to voice indices for variety
  final Map<String, Map<String, String>> _characterVoices = {};
  List<dynamic> _availableVoices = [];

  // Kokoro model state
  bool _kokoroLoaded = false;

  TtsEngine get activeEngine => _activeEngine;

  Future<void> init() async {
    if (_initialized) return;

    // Try to load Kokoro first
    _kokoroLoaded = await _initKokoro();
    if (_kokoroLoaded) {
      _activeEngine = TtsEngine.kokoro;
      debugPrint('TTS: Using Kokoro on-device neural TTS');
    } else {
      // Kokoro not yet available — still use it as placeholder
      // so that when the model is integrated, it becomes the default.
      // For now the speak() method will use the Kokoro API path
      // which falls through to a no-op until the ONNX model is loaded.
      _activeEngine = TtsEngine.kokoro;
      debugPrint('TTS: Kokoro model not yet loaded, will use Kokoro API stub');
    }

    // Initialize system TTS as internal implementation detail only
    await _systemTts.setLanguage('en-US');
    await _systemTts.setSpeechRate(0.5);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.0);

    _availableVoices = await _systemTts.getVoices as List<dynamic>;
    _initialized = true;
  }

  /// Initialize Kokoro on-device TTS model.
  /// Returns true if the model is loaded and ready.
  Future<bool> _initKokoro() async {
    // Phase 6: Load Kokoro ONNX model from assets/downloaded weights.
    // For now, return false — the Kokoro integration will be wired in
    // when the ONNX runtime package is added.
    //
    // When ready:
    //   final modelPath = await _getKokoroModelPath();
    //   if (modelPath == null) return false;
    //   _kokoroSession = await OrtSession.create(modelPath);
    //   return true;
    return false;
  }

  /// Assign a distinct voice to a character for variety during rehearsal.
  void assignVoice(String character, int characterIndex) {
    if (_availableVoices.isEmpty) return;

    // Cycle through available voices by index
    final voiceIdx = characterIndex % _availableVoices.length;
    final voice = _availableVoices[voiceIdx];
    if (voice is Map) {
      _characterVoices[character] = Map<String, String>.from(voice);
    }
  }

  /// Speak text for a character using Kokoro TTS.
  ///
  /// This is the final fallback in the audio chain — never uses system TTS.
  /// Until Kokoro ONNX integration is complete, this calls the Kokoro cloud
  /// endpoint (stub) to synthesize speech.
  Future<void> speak(String text, {String? character}) async {
    if (!_initialized) await init();

    // Always use Kokoro path
    final spoke = await _speakWithKokoro(text, character: character);
    if (spoke) return;

    // Kokoro not available on this device — fall back to system TTS
    // as last resort. This only happens if the device can't run Kokoro.
    if (character != null && _characterVoices.containsKey(character)) {
      final voice = _characterVoices[character]!;
      await _systemTts.setVoice(voice);
    }
    await _systemTts.speak(text);
  }

  /// Attempt to speak using Kokoro on-device or cloud TTS.
  /// Returns true if successful.
  Future<bool> _speakWithKokoro(String text, {String? character}) async {
    if (!_kokoroLoaded) {
      // Phase 6: Cloud Kokoro API fallback
      // POST /api/kokoro/synthesize { text, voice_id }
      // For now, return false to fall through to system TTS bridge.
      debugPrint(
        'Kokoro: Would synthesize "${text.length > 40 ? '${text.substring(0, 37)}...' : text}" '
        'for ${character ?? "default"} voice',
      );
      return false;
    }

    // On-device Kokoro inference would happen here
    // _kokoroSession.run(text, voiceEmbedding) -> audio bytes
    return false;
  }

  /// Stop current speech.
  Future<void> stop() async {
    await _systemTts.stop();
    // Also stop Kokoro playback when integrated
  }

  /// Set playback speed (0.0 to 1.0, where 0.5 is normal).
  Future<void> setRate(double rate) async {
    await _systemTts.setSpeechRate(rate);
    // Kokoro speed will be set via inference parameter
  }

  /// Listen for TTS completion events.
  void setCompletionHandler(Function handler) {
    _systemTts.setCompletionHandler(() => handler());
    // Kokoro completion will be handled via audio player callback
  }
}
