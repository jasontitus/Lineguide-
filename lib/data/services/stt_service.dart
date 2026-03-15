import 'dart:async';

import 'package:flutter/foundation.dart';

import 'apple_stt_channel.dart';
import 'debug_log_service.dart';
import 'mlx_stt_channel.dart';

/// STT engine type.
enum SttEngine {
  /// Apple SFSpeechRecognizer with contextualStrings (primary — real-time).
  apple,

  /// MLX Parakeet batch transcription (for file transcription).
  mlx,
}

/// Speech-to-text service.
///
/// Primary engine: Apple SFSpeechRecognizer via custom platform channel
/// with contextualStrings for vocabulary hinting. Provides real-time
/// streaming results — words appear as you speak.
///
/// MLX Parakeet is available for batch file transcription but not used
/// for live mic input (it's a batch model, not streaming).
class SttService {
  SttService._();
  static final instance = SttService._();

  final AppleSttChannel _appleChannel = AppleSttChannel.instance;
  final MlxSttChannel _mlxChannel = MlxSttChannel.instance;

  bool _isListening = false;
  SttEngine _activeEngine = SttEngine.apple;

  String _locale = 'en-US';

  SttEngine get activeEngine => _activeEngine;
  bool get isListening => _isListening;
  bool get isMlxReady => _mlxChannel.isInitialized;
  bool get isAvailable => _appleChannel.isInitialized;
  String get locale => _locale;

  /// Initialize the STT engine.
  ///
  /// [locale] — BCP-47 locale (e.g. "en-US", "en-GB"). Use "en-GB" for
  /// British/classical/Shakespearean scripts to improve recognition of
  /// British vocabulary and speech patterns.
  Future<bool> init({String locale = 'en-US'}) async {
    _locale = locale;

    // Dispose any previously loaded MLX model to free memory —
    // we use Apple STT now, Parakeet is only for batch file transcription
    _mlxChannel.dispose();

    // Apple SFSpeechRecognizer — real-time streaming with vocabulary hints
    final appleOk = await _appleChannel.initialize(locale: locale);
    if (appleOk) {
      _activeEngine = SttEngine.apple;
      DebugLogService.instance.log(LogCategory.stt,
          'Apple STT ready (locale=$locale, contextualStrings)');
      return true;
    }

    DebugLogService.instance.logError(LogCategory.stt, 'No STT engine available');
    return false;
  }

  /// Re-attempt MLX init (for batch file transcription).
  Future<bool> reloadMlx() async {
    try {
      final ok = await _mlxChannel.initialize('builtin');
      return ok;
    } catch (e) {
      debugPrint('STT: MLX init failed: $e');
      return false;
    }
  }

  // Stored callbacks for continuous mode restarts
  void Function(String)? _onResult;
  void Function()? _onDone;
  bool _continuous = false;
  List<String>? _vocabHints;

  /// Start listening for speech. Calls [onResult] with recognized words
  /// in real-time as they are spoken.
  ///
  /// [vocabularyHints] — words/phrases to boost in recognition. Pass
  /// character names, script-specific terms, or the expected line's words
  /// to improve accuracy.
  ///
  /// When [continuous] is true, listening automatically restarts after
  /// each recognition session until [stop] is called.
  Future<void> listen({
    required void Function(String recognizedWords) onResult,
    void Function()? onDone,
    bool continuous = false,
    Duration listenFor = const Duration(seconds: 30),
    List<String>? vocabularyHints,
  }) async {
    // Auto-init if needed
    if (!_appleChannel.isInitialized) {
      final ok = await init();
      if (!ok) {
        onDone?.call();
        return;
      }
    }

    _isListening = true;
    _continuous = continuous;
    _onResult = onResult;
    _onDone = onDone;
    _vocabHints = vocabularyHints;

    await _startAppleSession();
  }

  Future<void> _startAppleSession() async {
    if (!_isListening) return;

    final ok = await _appleChannel.listen(
      contextualStrings: _vocabHints,
      onResult: (text, isFinal) {
        _onResult?.call(text);
      },
      onDone: () {
        if (_continuous && _isListening) {
          // Auto-restart after brief pause
          Future.delayed(const Duration(milliseconds: 200), () {
            if (_isListening) {
              _startAppleSession();
            }
          });
        } else {
          _isListening = false;
          _onDone?.call();
          _onResult = null;
          _onDone = null;
        }
      },
    );

    if (!ok) {
      _isListening = false;
      _onDone?.call();
      _onResult = null;
      _onDone = null;
    }
  }

  /// Stop listening.
  ///
  /// [discard] parameter kept for API compatibility but not needed
  /// for Apple engine (no pending transcription to discard).
  Future<void> stop({bool discard = false}) async {
    _isListening = false;
    _continuous = false;
    _onResult = null;
    _onDone = null;
    _vocabHints = null;
    await _appleChannel.stop();
  }

  /// Transcribe a pre-recorded audio file (MLX Parakeet only).
  Future<String?> transcribeFile(String audioPath,
      {List<String>? vocabularyHints}) async {
    if (_mlxChannel.isInitialized) {
      return _mlxChannel.transcribe(audioPath,
          vocabularyHints: vocabularyHints);
    }
    return null;
  }

  // ── Match Score ───────────────────────────────────────

  /// Simple fuzzy match: what percentage of expected words were spoken.
  static double matchScore(String expected, String spoken) {
    final normalizedExpected = _normalize(expected);
    if (normalizedExpected.isEmpty) return 1.0;

    final expectedWords = normalizedExpected.split(RegExp(r'\s+'));
    final spokenWords = _normalize(spoken).split(RegExp(r'\s+'));

    int matched = 0;
    for (final word in expectedWords) {
      if (spokenWords.contains(word)) matched++;
    }

    return matched / expectedWords.length;
  }

  static String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  // ── Helpers ───────────────────────────────────────────

  void dispose() {
    _appleChannel.dispose();
    _mlxChannel.dispose();
  }
}
