import Foundation
import AVFoundation
import Kokoro

/// On-device Kokoro TTS service using MLX for Apple Silicon inference.
///
/// Downloads model weights from HuggingFace on first use (~86 MB),
/// then runs inference entirely on-device via the MLX framework.
class KokoroMLXService {

    // MARK: - Voice catalogue

    /// Available Kokoro voice IDs. Each maps to a pre-trained voice style.
    static let availableVoices: [String] = [
        // American Female
        "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica",
        "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
        // American Male
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam",
        "am_michael", "am_onyx", "am_puck",
        // British Female
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
        // British Male
        "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ]

    // MARK: - State

    private var pipeline: KPipeline?
    private let sampleRate: Int = 24_000
    private let modelRepo = "hexgrad/Kokoro-82M"

    var isModelLoaded: Bool { pipeline != nil }

    var isModelDownloaded: Bool {
        let dir = modelDirectory
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path)
    }

    // MARK: - Model lifecycle

    /// Load (and download if needed) the Kokoro MLX model.
    func loadModel() async throws {
        if pipeline != nil { return }

        // KPipeline from kokoro-swift handles downloading & caching from HuggingFace
        pipeline = try await KPipeline(langCode: "a") // "a" = American English
    }

    /// Delete downloaded model weights to free storage.
    func deleteModel() throws {
        pipeline = nil
        let dir = modelDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Synthesis

    /// Synthesize speech and return the path to a WAV file.
    func synthesize(text: String, voice: String, speed: Float) async throws -> String {
        guard let pipeline = pipeline else {
            throw KokoroError.modelNotLoaded
        }

        // Generate audio samples via Kokoro MLX inference
        var allSamples: [Float] = []
        for await result in pipeline.generate(text: text, voice: voice, speed: speed) {
            allSamples.append(contentsOf: result.audio)
        }

        guard !allSamples.isEmpty else {
            throw KokoroError.emptyAudio
        }

        // Write to a cached WAV file
        let outputPath = cacheURL(for: text, voice: voice, speed: speed)
        try writeWAV(samples: allSamples, sampleRate: sampleRate, to: outputPath)

        return outputPath.path
    }

    // MARK: - Audio encoding

    private func writeWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        // Create directory if needed
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Convert Float32 samples to Int16 PCM
        let pcmData = samples.withUnsafeBufferPointer { buffer -> Data in
            var data = Data()
            data.reserveCapacity(buffer.count * 2)
            for sample in buffer {
                let clamped = max(-1.0, min(1.0, sample))
                var int16 = Int16(clamped * Float(Int16.max))
                data.append(Data(bytes: &int16, count: 2))
            }
            return data
        }

        // Build WAV header + data
        var wav = Data()
        let dataSize = UInt32(pcmData.count)
        let fileSize = UInt32(36 + pcmData.count)

        wav.append("RIFF".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        wav.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM format
        wav.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // mono
        wav.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wav.append(withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) }) // byte rate
        wav.append(withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })  // block align
        wav.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample
        wav.append("data".data(using: .ascii)!)
        wav.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wav.append(pcmData)

        try wav.write(to: url)
    }

    // MARK: - Caching

    private func cacheURL(for text: String, voice: String, speed: Float) -> URL {
        let hash = "\(text.hashValue)_\(voice)_\(String(format: "%.1f", speed))"
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kokoro_tts", isDirectory: true)
        return cacheDir.appendingPathComponent("\(hash).wav")
    }

    private var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kokoro_mlx", isDirectory: true)
    }
}

// MARK: - Errors

enum KokoroError: LocalizedError {
    case modelNotLoaded
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Kokoro model not loaded. Call loadModel() first."
        case .emptyAudio: return "No audio generated for the given text."
        }
    }
}
