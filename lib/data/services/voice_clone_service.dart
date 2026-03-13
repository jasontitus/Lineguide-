import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Voice profile for a cast member, storing reference audio and embeddings.
class VoiceProfile {
  final String characterName;
  final List<String> referenceAudioPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Estimated quality based on number/duration of reference clips.
  /// 0.0 = no data, 1.0 = excellent (60+ seconds of clean audio).
  double get quality {
    if (referenceAudioPaths.isEmpty) return 0.0;
    // Each clip assumed ~5-15s; 6+ clips = good quality
    return (referenceAudioPaths.length / 8.0).clamp(0.1, 1.0);
  }

  const VoiceProfile({
    required this.characterName,
    required this.referenceAudioPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  VoiceProfile copyWith({
    String? characterName,
    List<String>? referenceAudioPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VoiceProfile(
      characterName: characterName ?? this.characterName,
      referenceAudioPaths: referenceAudioPaths ?? this.referenceAudioPaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Status of a voice clone generation request.
enum VoiceCloneStatus {
  idle,
  extractingEmbedding, // analyzing reference audio
  generating, // synthesizing speech
  complete,
  error,
}

/// Service for voice cloning using F5-TTS (ONNX) or cloud fallback.
///
/// Architecture:
/// Phase 1 (MVP): Cloud-based — send reference audio + text to server,
///   receive synthesized audio back. Cache locally for offline playback.
/// Phase 2: On-device — download quantized F5-TTS ONNX model (~200MB),
///   run inference locally using onnxruntime_flutter.
///
/// The service manages:
/// - Voice profiles (reference audio per character)
/// - Generating speech for unrecorded lines
/// - Caching generated audio alongside real recordings
class VoiceCloneService {
  VoiceCloneService._();
  static final instance = VoiceCloneService._();

  VoiceCloneStatus _status = VoiceCloneStatus.idle;
  VoiceCloneStatus get status => _status;

  final Map<String, VoiceProfile> _profiles = {};

  /// Get voice profile for a character, or null if none exists.
  VoiceProfile? getProfile(String character) => _profiles[character];

  /// Get all voice profiles.
  Map<String, VoiceProfile> get profiles => Map.unmodifiable(_profiles);

  /// Build a voice profile from existing recordings.
  /// Call this after a cast member records several lines — their recordings
  /// become the reference audio for voice cloning.
  Future<VoiceProfile> buildProfileFromRecordings({
    required String character,
    required List<String> recordingPaths,
  }) async {
    // Filter to existing files
    final validPaths = <String>[];
    for (final path in recordingPaths) {
      if (await File(path).exists()) {
        validPaths.add(path);
      }
    }

    final now = DateTime.now();
    final profile = VoiceProfile(
      characterName: character,
      referenceAudioPaths: validPaths,
      createdAt: _profiles[character]?.createdAt ?? now,
      updatedAt: now,
    );

    _profiles[character] = profile;
    return profile;
  }

  /// Generate speech for a line using a character's voice profile.
  /// Returns the path to the generated audio file, or null if generation
  /// is not possible (no profile, service unavailable, etc.).
  ///
  /// The generated audio is cached locally so it only needs to be
  /// synthesized once per line.
  Future<String?> generateLine({
    required String productionId,
    required String character,
    required String lineId,
    required String text,
  }) async {
    final profile = _profiles[character];
    if (profile == null || profile.referenceAudioPaths.isEmpty) return null;

    // Check cache first
    final cachePath = await _cachePath(productionId, character, lineId);
    if (await File(cachePath).exists()) return cachePath;

    _status = VoiceCloneStatus.generating;

    try {
      // Phase 1: Cloud API call
      // In production, this would POST to a voice cloning API:
      //   POST /api/voice-clone/generate
      //   Body: { reference_audio: [base64...], text: "line text" }
      //   Response: audio/wav binary
      //
      // Phase 2: On-device ONNX inference
      //   Load F5-TTS ONNX model
      //   Extract speaker embedding from reference audio
      //   Run inference: (text, embedding) -> audio
      //
      // For now, return null to fall back to system TTS
      debugPrint(
        'VoiceClone: Would generate "$text" in ${character}\'s voice '
        '(${profile.referenceAudioPaths.length} reference clips, '
        'quality: ${(profile.quality * 100).toInt()}%)',
      );

      _status = VoiceCloneStatus.idle;
      return null; // Fall back to TTS until API is connected
    } catch (e) {
      _status = VoiceCloneStatus.error;
      debugPrint('VoiceClone error: $e');
      return null;
    }
  }

  /// Check if we can generate voice-cloned audio for a character.
  bool canClone(String character) {
    final profile = _profiles[character];
    return profile != null && profile.referenceAudioPaths.length >= 3;
  }

  /// Get the local cache path for a generated line.
  Future<String> _cachePath(
      String productionId, String character, String lineId) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(
        p.join(dir.path, 'voice_cache', productionId, character));
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return p.join(cacheDir.path, '$lineId.wav');
  }

  /// Clear cached generated audio for a production.
  Future<void> clearCache(String productionId) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'voice_cache', productionId));
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
  }
}
