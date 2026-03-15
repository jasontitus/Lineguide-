import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'debug_log_service.dart';
import 'model_manager.dart';

/// TTS engine type.
enum TtsEngine {
  /// Kokoro on-device neural TTS via MLX (default, higher quality).
  kokoroMlx,

  /// System TTS (last resort if Kokoro model not loaded).
  system,
}

/// Text-to-speech service using Kokoro via MLX.
///
/// Priority chain for playing other characters' lines:
///   1. Real recording by primary actor
///   2. Real recording by understudy (if fallback enabled)
///   3. Voice-cloned audio (if voice cloning enabled)
///   4. Kokoro MLX on-device TTS (default fallback)
///   5. System TTS (last resort — only if Kokoro unavailable)
class TtsService {
  TtsService._();
  static final instance = TtsService._();

  static const _channel = MethodChannel('com.lineguide/kokoro_mlx');

  final FlutterTts _systemTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _initialized = false;
  TtsEngine _activeEngine = TtsEngine.kokoroMlx;

  // Map character names to Kokoro voice IDs (set by voice config or fallback)
  final Map<String, String> _characterVoices = {};

  // Per-character speed overrides (from voice config)
  final Map<String, double> _characterSpeeds = {};

  // System TTS voices (fallback)
  final Map<String, Map<String, String>> _characterSystemVoices = {};
  List<dynamic> _availableSystemVoices = [];

  // Kokoro MLX state
  bool _kokoroLoaded = false;

  // Completion callback — guarded by generation counter to fire exactly once per speak()
  Function? _completionHandler;
  bool _isSpeaking = false;
  int _speakGen = 0; // incremented each speak(), prevents stale completions

  TtsEngine get activeEngine => _activeEngine;
  bool get isKokoroLoaded => _kokoroLoaded;
  bool get isInitialized => _initialized;

  /// Available Kokoro voices for character assignment.
  static const List<String> kokoroVoices = [
    'af_heart',
    'af_bella',
    'af_jessica',
    'af_nova',
    'af_sarah',
    'am_adam',
    'am_eric',
    'am_michael',
    'am_onyx',
    'bf_alice',
    'bf_emma',
    'bf_lily',
    'bm_daniel',
    'bm_george',
    'bm_lewis',
  ];

  Future<void> init() async {
    if (_initialized) return;

    // Try to load Kokoro MLX model on device
    _kokoroLoaded = await _initKokoroMlx();
    if (_kokoroLoaded) {
      _activeEngine = TtsEngine.kokoroMlx;
      debugPrint('TTS: Using Kokoro MLX on-device neural TTS');
    } else {
      _activeEngine = TtsEngine.system;
      debugPrint('TTS: Kokoro MLX not available, using system TTS');
    }

    // Initialize system TTS as fallback
    await _systemTts.setLanguage('en-US');
    await _systemTts.setSpeechRate(0.5);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.0);
    _availableSystemVoices = await _systemTts.getVoices as List<dynamic>;

    _systemTts.setCompletionHandler(() {
      _fireCompletion('systemTts');
    });

    // DO NOT use playerStateStream for completion detection — it re-emits stale
    // 'completed' events during the next line's Kokoro synthesis, causing lines
    // to be skipped. Instead, completion is fired from _speakWithKokoroMlx after
    // play() returns, guarded by a generation counter.
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        DebugLogService.instance.log(LogCategory.tts,
            'audioPlayer stream completed (gen=$_speakGen, speaking=$_isSpeaking) — ignored, using gen counter');
      }
    });

    _initialized = true;
  }

  /// Initialize on-device Kokoro MLX model.
  /// Returns true if the model is loaded and ready for inference.
  Future<bool> _initKokoroMlx() async {
    try {
      final result = await _channel.invokeMethod<bool>('loadModel');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Kokoro MLX: load failed: ${e.message}');
      return false;
    } on MissingPluginException {
      // Platform channel not registered (e.g. running on Android or web)
      debugPrint('Kokoro MLX: platform channel not available');
      return false;
    }
  }

  /// Check if the Kokoro MLX model is downloaded but not yet loaded.
  Future<bool> isModelDownloaded() async {
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('getModelStatus');
      return status?['downloaded'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Assign a specific Kokoro voice and speed to a character.
  ///
  /// Called by rehearsal screen after resolving voice config (preset + overrides).
  void assignVoice(String character, int characterIndex,
      {String? voiceId, double? speed}) {
    // Use provided voiceId or fall back to round-robin from kokoroVoices
    _characterVoices[character] =
        voiceId ?? kokoroVoices[characterIndex % kokoroVoices.length];

    if (speed != null) {
      _characterSpeeds[character] = speed;
    }

    // Also assign a system TTS voice as fallback
    if (_availableSystemVoices.isNotEmpty) {
      final sysIdx = characterIndex % _availableSystemVoices.length;
      final voice = _availableSystemVoices[sysIdx];
      if (voice is Map) {
        _characterSystemVoices[character] = Map<String, String>.from(voice);
      }
    }
  }

  /// Speak text for a character using Kokoro MLX on-device TTS.
  ///
  /// Falls back to system TTS only if Kokoro is not available on this device.
  Future<void> speak(String text, {String? character}) async {
    if (!_initialized) await init();
    final dlog = DebugLogService.instance;
    final preview = text.length > 40 ? '${text.substring(0, 37)}...' : text;

    // Increment generation — any stale completion from previous speak() is ignored
    _speakGen++;
    _isSpeaking = true;

    // Try Kokoro MLX first
    if (_kokoroLoaded) {
      dlog.log(LogCategory.tts, 'Kokoro speak: "$preview" (char=$character)');
      final spoke = await _speakWithKokoroMlx(text, character: character);
      if (spoke) return; // completion will fire from _audioPlayer stream
      dlog.log(LogCategory.tts, 'Kokoro failed, falling back to system TTS');
    }

    // Fall back to system TTS
    dlog.log(LogCategory.tts, 'System TTS: "$preview"');
    if (character != null &&
        _characterSystemVoices.containsKey(character)) {
      final voice = _characterSystemVoices[character]!;
      await _systemTts.setVoice(voice);
    }
    await _systemTts.speak(text);
  }

  /// Synthesize and play audio using on-device Kokoro MLX.
  /// Returns true if successful.
  Future<bool> _speakWithKokoroMlx(String text, {String? character}) async {
    final gen = _speakGen; // capture for stale-check after async gaps
    final voice = (character != null && _characterVoices.containsKey(character))
        ? _characterVoices[character]!
        : 'af_heart';

    // Use per-character speed if set, otherwise global speed
    final speed = (character != null && _characterSpeeds.containsKey(character))
        ? _characterSpeeds[character]!
        : _currentSpeed;

    try {
      final audioPath = await _channel.invokeMethod<String>('synthesize', {
        'text': text,
        'voice': voice,
        'speed': speed,
      });

      if (audioPath == null) {
        DebugLogService.instance.logError(LogCategory.tts, 'Kokoro returned null audio path');
        return false;
      }

      // Bail out if a newer speak() was called during synthesis
      if (gen != _speakGen) {
        DebugLogService.instance.log(LogCategory.tts,
            'Kokoro synthesis finished but gen stale ($gen != $_speakGen), discarding');
        return true; // return true to prevent system TTS fallback
      }

      // Stop any previous playback and reset player state before loading new audio.
      // This ensures the audio session is properly re-acquired after STT released it.
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(audioPath);
      DebugLogService.instance.log(LogCategory.tts, 'Kokoro playing audio');
      await _audioPlayer.play();

      // play() returned — audio finished (or was stopped).
      // Fire completion only if this is still the active speak() call.
      if (gen == _speakGen) {
        _fireCompletion('kokoroPlay');
      } else {
        DebugLogService.instance.log(LogCategory.tts,
            'Kokoro play done but gen stale ($gen != $_speakGen), completion skipped');
      }
      return true;
    } on PlatformException catch (e) {
      DebugLogService.instance.logError(LogCategory.tts, 'Kokoro synthesis failed', e);
      return false;
    } catch (e) {
      DebugLogService.instance.logError(LogCategory.tts, 'Kokoro playback failed', e);
      return false;
    }
  }

  double _currentSpeed = 1.0;

  /// Fire the completion handler exactly once per speak() call.
  /// Prevents stale/duplicate completion events from advancing the rehearsal.
  void _fireCompletion(String source) {
    if (_isSpeaking) {
      _isSpeaking = false;
      DebugLogService.instance.log(LogCategory.tts, 'Completion fired (source=$source)');
      _completionHandler?.call();
    } else {
      DebugLogService.instance.log(LogCategory.tts, 'Completion IGNORED (source=$source, not speaking)');
    }
  }

  /// Stop current speech. Does NOT fire the completion handler.
  Future<void> stop() async {
    _speakGen++; // Invalidate any in-flight speak() call
    _isSpeaking = false; // Prevent stop() from triggering completion
    await _audioPlayer.stop();
    await _systemTts.stop();
  }

  /// Set playback speed (0.0 to 1.0, where 0.5 is normal for system TTS).
  Future<void> setRate(double rate) async {
    // For Kokoro MLX, speed is 0.5–2.0 where 1.0 is normal.
    // The caller passes rate as system-TTS scale (0.0–1.0, 0.5 = normal).
    // Convert: system 0.5 → Kokoro 1.0
    _currentSpeed = (rate / 0.5).clamp(0.5, 2.0);
    await _systemTts.setSpeechRate(rate);
  }

  /// Listen for TTS completion events.
  void setCompletionHandler(Function handler) {
    _completionHandler = handler;
    // Don't override system TTS handler — init() already routes it through
    // _fireCompletion which provides the _isSpeaking guard.
  }

  /// Delete the on-device Kokoro model to free storage.
  Future<void> deleteModel() async {
    try {
      await _channel.invokeMethod('deleteModel');
      _kokoroLoaded = false;
      _activeEngine = TtsEngine.system;
    } catch (e) {
      debugPrint('Kokoro MLX: delete failed: $e');
    }
  }

  /// Debug info for diagnostics screen.
  Future<Map<String, String>> getDebugInfo() async {
    return {
      'initialized': _initialized.toString(),
      'activeEngine': _activeEngine.name,
      'kokoroLoaded': _kokoroLoaded.toString(),
    };
  }

  /// Clean up resources.
  void dispose() {
    _audioPlayer.dispose();
  }
}
