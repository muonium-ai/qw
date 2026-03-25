//
//  MediaMetadataPanel.swift
//  qw
//
//  Displays ffprobe-extracted media metadata in the hex view sidebar.
//  Ticket: T-000042
//

import SwiftUI

/// Sidebar panel that shows media metadata extracted by ffprobe.
struct MediaMetadataPanel: View {

    let result: FFprobeResult?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: SyntaxTheme {
        EditorSettingsManager.shared.syntaxTheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 300)
        .background(theme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "film")
                .foregroundStyle(.secondary)
            Text("Media Metadata")
                .font(.system(.headline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch result {
        case .none:
            loadingView
        case .notInstalled:
            notInstalledView
        case .error(let msg):
            errorView(msg)
        case .timeout:
            errorView("ffprobe timed out")
        case .success(let metadata):
            metadataView(metadata)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Probing media...")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption))
                Spacer()
            }
            Spacer()
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 8) {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("ffprobe not found")
                        .font(.system(.caption).bold())
                        .foregroundStyle(.primary)
                    Text("Install via: brew install ffmpeg")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            Spacer()
        }
        .padding(8)
    }

    private func errorView(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            Spacer()
        }
        .padding(8)
    }

    // MARK: - Metadata display

    private func metadataView(_ metadata: FFprobeMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Format section
                if metadata.formatName != nil || metadata.formatLongName != nil {
                    sectionHeader("Container")
                    if let name = metadata.formatLongName ?? metadata.formatName {
                        metadataRow(label: "Format", value: name)
                    }
                    if let dur = metadata.formattedDuration {
                        metadataRow(label: "Duration", value: dur)
                    }
                    if let br = metadata.formattedBitrate {
                        metadataRow(label: "Bitrate", value: br)
                    }
                }

                // Streams
                for (index, stream) in metadata.streams.enumerated() {
                    let title: String
                    switch stream.codecType {
                    case "video": title = "Video Stream \(index)"
                    case "audio": title = "Audio Stream \(index)"
                    default: title = "\(stream.codecType.capitalized) Stream \(index)"
                    }

                    sectionHeader(title)

                    if let codec = stream.codecLongName ?? stream.codecName {
                        metadataRow(label: "Codec", value: codec)
                    }

                    if stream.codecType == "video" {
                        if let w = stream.width, let h = stream.height {
                            metadataRow(label: "Resolution", value: "\(w) x \(h)")
                        }
                        if let fps = FFprobeMetadata.formatFrameRate(stream.frameRate) {
                            metadataRow(label: "Frame Rate", value: fps)
                        }
                    }

                    if stream.codecType == "audio" {
                        if let sr = stream.sampleRate {
                            let srKHz = (Double(sr) ?? 0) / 1000.0
                            if srKHz > 0 {
                                metadataRow(label: "Sample Rate", value: String(format: "%.1f kHz", srKHz))
                            } else {
                                metadataRow(label: "Sample Rate", value: "\(sr) Hz")
                            }
                        }
                        if let ch = stream.channels {
                            let layout = stream.channelLayout ?? (ch == 1 ? "mono" : ch == 2 ? "stereo" : "\(ch)ch")
                            metadataRow(label: "Channels", value: "\(ch) (\(layout))")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Row helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .default).bold())
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.caption2))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("Media Metadata — Loading") {
    MediaMetadataPanel(result: nil)
}

#Preview("Media Metadata — Not Installed") {
    MediaMetadataPanel(result: .notInstalled)
}

#Preview("Media Metadata — Success") {
    let metadata = FFprobeMetadata(
        formatName: "mov,mp4,m4a,3gp,3g2,mj2",
        formatLongName: "QuickTime / MOV",
        duration: 125.5,
        bitrate: 1_500_000,
        streams: [
            FFprobeMetadata.StreamInfo(
                codecType: "video",
                codecName: "h264",
                codecLongName: "H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10",
                width: 1920,
                height: 1080,
                frameRate: "30/1",
                sampleRate: nil,
                channels: nil,
                channelLayout: nil
            ),
            FFprobeMetadata.StreamInfo(
                codecType: "audio",
                codecName: "aac",
                codecLongName: "AAC (Advanced Audio Coding)",
                width: nil,
                height: nil,
                frameRate: nil,
                sampleRate: "44100",
                channels: 2,
                channelLayout: "stereo"
            ),
        ]
    )
    MediaMetadataPanel(result: .success(metadata))
}
