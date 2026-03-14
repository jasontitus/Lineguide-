import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// TTS engine type used for fallback speech synthesis.
enum TtsEngine {
  /// Kokoro MLX neural TTS via local server (default, higher quality).
  kokoroMlx,

  /// System TTS (last resort if Kokoro server unreachable).
  system,
}

/// Text-to-speech service.
///
/// Priority chain for playing other characters' lines:
///   1. Real recording by primary actor
///   2. Real recording by understudy (if fallback enabled)
///   3. Voice-cloned audio (if voice cloning enabled)
///   4. Kokoro MLX TTS (default fallback)
///   5. System TTS (last resort — only if Kokoro server unreachable)
class TtsService {
  TtsService._();
  static final instance = TtsService._();

  final FlutterTts _systemTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _initialized = false;
  TtsEngine _activeEngine = TtsEngine.kokoroMlx;

  // Map character names to Kokoro voice IDs for variety
  final Map<String, String> _characterVoices = {};

  // System TTS voices (fallback)
  final Map<String, Map<String, String>> _characterSystemVoices = {};
  List<dynamic> _availableSystemVoices = [];

  // Kokoro MLX server configuration
  String _kokoroBaseUrl = 'http://localhost:8787';
  bool _kokoroAvailable = false;

  // Audio cache directory
  String? _cacheDir;

  // Completion callback
  Function? _completionHandler;

  TtsEngine get activeEngine => _activeEngine;
  bool get isKokoroAvailable => _kokoroAvailable;

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

  /// Set the Kokoro MLX server URL.
  void setKokoroUrl(String url) {
    _kokoroBaseUrl = url;
    _kokoroAvailable = false; // Re-check on next speak
  }

  Future<void> init() async {
    if (_initialized) return;

    // Set up audio cache directory
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = p.join(appDir.path, 'tts_cache');
    await Directory(_cacheDir!).create(recursive: true);

    // Check if Kokoro MLX server is reachable
    _kokoroAvailable = await _checkKokoroServer();
    if (_kokoroAvailable) {
      _activeEngine = TtsEngine.kokoroMlx;
      debugPrint('TTS: Using Kokoro MLX server at $_kokoroBaseUrl');
    } else {
      _activeEngine = TtsEngine.system;
      debugPrint('TTS: Kokoro MLX server not reachable, using system TTS');
    }

    // Initialize system TTS as fallback
    await _systemTts.setLanguage('en-US');
    await _systemTts.setSpeechRate(0.5);
    await _systemTts.setVolume(1.0);
    await _systemTts.setPitch(1.0);

    _availableSystemVoices = await _systemTts.getVoices as List<dynamic>;

    // Listen for audio player completion
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _completionHandler?.call();
      }
    });

    _initialized = true;
  }

  /// Check if the Kokoro MLX server is healthy.
  Future<bool> _checkKokoroServer() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      try {
        final request =
            await client.getUrl(Uri.parse('$_kokoroBaseUrl/health'));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Assign a distinct Kokoro voice to a character for variety during rehearsal.
  void assignVoice(String character, int characterIndex) {
    // Assign a Kokoro voice
    final voiceIdx = characterIndex % kokoroVoices.length;
    _characterVoices[character] = kokoroVoices[voiceIdx];

    // Also assign a system TTS voice as fallback
    if (_availableSystemVoices.isNotEmpty) {
      final sysIdx = characterIndex % _availableSystemVoices.length;
      final voice = _availableSystemVoices[sysIdx];
      if (voice is Map) {
        _characterSystemVoices[character] = Map<String, String>.from(voice);
      }
    }
  }

  /// Speak text for a character using Kokoro MLX TTS.
  ///
  /// Falls back to system TTS only if the Kokoro server is unreachable.
  Future<void> speak(String text, {String? character}) async {
    if (!_initialized) await init();

    // Try Kokoro MLX first
    if (await _speakWithKokoroMlx(text, character: character)) return;

    // Kokoro not available — fall back to system TTS
    if (character != null &&
        _characterSystemVoices.containsKey(character)) {
      final voice = _characterSystemVoices[character]!;
      await _systemTts.setVoice(voice);
    }
    await _systemTts.speak(text);
  }

  /// Synthesize and play audio using the Kokoro MLX server.
  /// Returns true if successful.
  Future<bool> _speakWithKokoroMlx(String text,
      {String? character}) async {
    // Re-check server availability if it was previously unavailable
    if (!_kokoroAvailable) {
      _kokoroAvailable = await _checkKokoroServer();
      if (!_kokoroAvailable) return false;
    }

    final voice = (character != null && _characterVoices.containsKey(character))
        ? _characterVoices[character]!
        : 'af_heart';

    // Check cache first
    final cacheKey =
        '${text.hashCode}_${voice}_${_currentSpeed.toStringAsFixed(1)}';
    final cacheFile = File(p.join(_cacheDir!, '$cacheKey.wav'));

    if (cacheFile.existsSync()) {
      try {
        await _audioPlayer.setFilePath(cacheFile.path);
        await _audioPlayer.play();
        return true;
      } catch (_) {
        // Cache file corrupt, re-synthesize
        await cacheFile.delete();
      }
    }

    // Call Kokoro MLX server
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      try {
        final request =
            await client.postUrl(Uri.parse('$_kokoroBaseUrl/synthesize'));
        request.headers.contentType = ContentType.json;
        request.write(
          '{"text": ${_jsonEscape(text)}, "voice": "$voice", "speed": $_currentSpeed}',
        );
        final response = await request.close();

        if (response.statusCode != 200) {
          debugPrint('Kokoro MLX: server returned ${response.statusCode}');
          _kokoroAvailable = false;
          return false;
        }

        // Write audio to cache file
        final sink = cacheFile.openWrite();
        await response.pipe(sink);
        await sink.close();

        // Play the audio
        await _audioPlayer.setFilePath(cacheFile.path);
        await _audioPlayer.play();

        _activeEngine = TtsEngine.kokoroMlx;
        return true;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Kokoro MLX: synthesis failed: $e');
      _kokoroAvailable = false;
      return false;
    }
  }

  double _currentSpeed = 1.0;

  /// Stop current speech.
  Future<void> stop() async {
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
    _systemTts.setCompletionHandler(() => handler());
  }

  /// Clear the TTS audio cache.
  Future<void> clearCache() async {
    if (_cacheDir == null) return;
    final dir = Directory(_cacheDir!);
    if (dir.existsSync()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.wav')) {
          await entity.delete();
        }
      }
    }
    debugPrint('TTS: Cache cleared');
  }

  /// JSON-escape a string value (including surrounding quotes).
  static String _jsonEscape(String s) {
    return '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';
  }
}
