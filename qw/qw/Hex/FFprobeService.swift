//
//  FFprobeService.swift
//  qw
//
//  Extracts media metadata from video and audio files using ffprobe.
//  Runs asynchronously with timeout and graceful degradation when ffprobe
//  is not installed.
//  Ticket: T-000042
//

import Foundation

// MARK: - FFprobe metadata result

/// Structured metadata extracted from ffprobe output.
struct FFprobeMetadata {
    /// Format/container name (e.g. "mov,mp4,m4a,3gp,3g2,mj2").
    let formatName: String?
    /// Format long name (e.g. "QuickTime / MOV").
    let formatLongName: String?
    /// Duration in seconds.
    let duration: Double?
    /// Overall bitrate in bits/s.
    let bitrate: Int?

    /// Per-stream information.
    let streams: [StreamInfo]

    struct StreamInfo {
        let codecType: String       // "video" or "audio"
        let codecName: String?      // e.g. "h264", "aac"
        let codecLongName: String?
        // Video
        let width: Int?
        let height: Int?
        let frameRate: String?      // e.g. "30/1" or "24000/1001"
        // Audio
        let sampleRate: String?     // e.g. "44100"
        let channels: Int?
        let channelLayout: String?  // e.g. "stereo"
    }
}

// MARK: - FFprobe result

/// The result of an ffprobe invocation.
enum FFprobeResult {
    case success(FFprobeMetadata)
    case notInstalled
    case error(String)
    case timeout
}

// MARK: - FFprobeService

/// Asynchronously invokes `ffprobe` on a file path and parses the JSON output.
enum FFprobeService {

    /// Default timeout in seconds.
    private static let timeoutSeconds: TimeInterval = 5

    /// Check whether a file signature name looks like an audio or video format.
    static func isAudioVideoFormat(signatureName: String) -> Bool {
        let name = signatureName.lowercased()
        let keywords = ["mp4", "video", "audio", "wav", "avi", "riff", "mov",
                        "flac", "ogg", "mkv", "webm", "mp3", "aac", "m4a",
                        "mpeg", "matroska", "opus"]
        return keywords.contains(where: { name.contains($0) })
    }

    /// Check whether a database category indicates audio or video.
    static func isAudioVideoCategory(_ category: String) -> Bool {
        let cat = category.lowercased()
        return cat == "audio" || cat == "video" || cat == "multimedia"
    }

    /// Run ffprobe asynchronously on the given file URL.
    /// Returns the result on the calling async context (not the main thread).
    static func probe(fileURL: URL) async -> FFprobeResult {
        let path = fileURL.path

        // Locate ffprobe on PATH
        guard let ffprobePath = findFFprobe() else {
            return .notInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            path
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Run with timeout
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: .error("Failed to launch ffprobe: \(error.localizedDescription)"))
                        return
                    }

                    // Timeout via DispatchWorkItem
                    let timeoutItem = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + timeoutSeconds,
                        execute: timeoutItem
                    )

                    process.waitUntilExit()
                    timeoutItem.cancel()

                    if process.terminationStatus != 0 && !process.isRunning {
                        // Check if it was terminated by timeout
                        if process.terminationReason == .uncaughtSignal {
                            continuation.resume(returning: .timeout)
                            return
                        }
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(returning: .error("ffprobe exited with status \(process.terminationStatus): \(errMsg)"))
                        return
                    }

                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    guard !data.isEmpty else {
                        continuation.resume(returning: .error("ffprobe returned no output"))
                        return
                    }

                    let result = parseJSON(data)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    // MARK: - Private helpers

    /// Find ffprobe on the system PATH, checking common locations.
    private static func findFFprobe() -> String? {
        // Check common paths first for speed
        let commonPaths = [
            "/usr/local/bin/ffprobe",
            "/opt/homebrew/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which`
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["ffprobe"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            if which.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = result, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Ignore
        }
        return nil
    }

    /// Parse ffprobe JSON output into structured metadata.
    private static func parseJSON(_ data: Data) -> FFprobeResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .error("Failed to parse ffprobe JSON output")
        }

        // Parse format section
        let formatDict = json["format"] as? [String: Any]
        let formatName = formatDict?["format_name"] as? String
        let formatLongName = formatDict?["format_long_name"] as? String
        let durationStr = formatDict?["duration"] as? String
        let duration = durationStr.flatMap { Double($0) }
        let bitrateStr = formatDict?["bit_rate"] as? String
        let bitrate = bitrateStr.flatMap { Int($0) }

        // Parse streams
        var streams: [FFprobeMetadata.StreamInfo] = []
        if let streamArray = json["streams"] as? [[String: Any]] {
            for s in streamArray {
                let codecType = s["codec_type"] as? String ?? "unknown"
                let codecName = s["codec_name"] as? String
                let codecLongName = s["codec_long_name"] as? String
                let width = s["width"] as? Int
                let height = s["height"] as? Int

                // Frame rate: prefer r_frame_rate, then avg_frame_rate
                let frameRate = (s["r_frame_rate"] as? String) ?? (s["avg_frame_rate"] as? String)

                let sampleRate = s["sample_rate"] as? String
                let channels = s["channels"] as? Int
                let channelLayout = s["channel_layout"] as? String

                streams.append(FFprobeMetadata.StreamInfo(
                    codecType: codecType,
                    codecName: codecName,
                    codecLongName: codecLongName,
                    width: width,
                    height: height,
                    frameRate: frameRate,
                    sampleRate: sampleRate,
                    channels: channels,
                    channelLayout: channelLayout
                ))
            }
        }

        let metadata = FFprobeMetadata(
            formatName: formatName,
            formatLongName: formatLongName,
            duration: duration,
            bitrate: bitrate,
            streams: streams
        )
        return .success(metadata)
    }
}

// MARK: - Display formatting

extension FFprobeMetadata {

    /// Format duration as "HH:MM:SS.ms" or "MM:SS.ms".
    var formattedDuration: String? {
        guard let d = duration else { return nil }
        let hours = Int(d) / 3600
        let minutes = (Int(d) % 3600) / 60
        let seconds = Int(d) % 60
        let ms = Int((d.truncatingRemainder(dividingBy: 1)) * 100)
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, ms)
        }
        return String(format: "%d:%02d.%02d", minutes, seconds, ms)
    }

    /// Format bitrate as human-readable string (e.g. "1.5 Mbps").
    var formattedBitrate: String? {
        guard let b = bitrate else { return nil }
        if b >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(b) / 1_000_000)
        } else if b >= 1_000 {
            return String(format: "%d kbps", b / 1_000)
        }
        return "\(b) bps"
    }

    /// Format frame rate fraction as decimal (e.g. "30/1" -> "30.00 fps").
    static func formatFrameRate(_ fr: String?) -> String? {
        guard let fr = fr else { return nil }
        let parts = fr.split(separator: "/")
        if parts.count == 2,
           let num = Double(parts[0]),
           let den = Double(parts[1]),
           den > 0 {
            let fps = num / den
            if fps > 0 && fps < 1000 {
                return String(format: "%.2f fps", fps)
            }
        }
        return nil
    }
}
