//
//  AudioPlayerView.swift
//  qw
//
//  Audio playback view with play/pause, seek, speed, and volume controls.
//  Ticket: T-000052
//

import SwiftUI
import AVFoundation
import Combine

/// A minimal audio player view for binary audio files.
struct AudioPlayerView: View {
    let fileURL: URL

    @StateObject private var controller = AudioPlayerController()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Large icon
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)

                // Filename
                Text(fileURL.lastPathComponent)
                    .font(.title2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Error message
                if let error = controller.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Seek bar with time labels
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { controller.currentTime },
                            set: { controller.seek(to: $0) }
                        ),
                        in: 0...max(controller.duration, 0.01)
                    )
                    .disabled(controller.duration == 0)

                    HStack {
                        Text(formatTime(controller.currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(controller.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                // Play/Pause button
                Button(action: { controller.togglePlayPause() }) {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(controller.errorMessage != nil)
                .keyboardShortcut(.space, modifiers: [])

                // Speed control
                HStack(spacing: 12) {
                    Text("Speed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Speed", selection: $controller.playbackSpeed) {
                        Text("1\u{00D7}").tag(Float(1.0))
                        Text("1.25\u{00D7}").tag(Float(1.25))
                        Text("1.5\u{00D7}").tag(Float(1.5))
                        Text("2\u{00D7}").tag(Float(2.0))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                // Volume control
                HStack(spacing: 8) {
                    Button(action: { controller.toggleMute() }) {
                        Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(.plain)
                    .help(controller.isMuted ? "Unmute" : "Mute")

                    Slider(value: $controller.volume, in: 0...1)
                        .frame(maxWidth: 200)
                }
            }
            .frame(maxWidth: 400)
            .padding(32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            controller.load(url: fileURL)
        }
        .onDisappear {
            controller.cleanup()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Audio Player Controller

/// Observable controller that wraps AVPlayer for audio playback.
final class AudioPlayerController: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var errorMessage: String?

    @Published var volume: Float = 1.0 {
        didSet {
            if !isMuted {
                player?.volume = volume
            }
        }
    }

    @Published var isMuted: Bool = false {
        didSet {
            player?.volume = isMuted ? 0 : volume
        }
    }

    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            if isPlaying {
                player?.rate = playbackSpeed
            }
        }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "File not found."
            return
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.volume = isMuted ? 0 : volume
        self.player = avPlayer

        // Observe duration once ready
        Task { @MainActor in
            do {
                let dur = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(dur)
                if seconds.isFinite && seconds > 0 {
                    self.duration = seconds
                }
            } catch {
                self.errorMessage = "Unable to load audio: \(error.localizedDescription)"
            }
        }

        // Periodic time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite {
                self.currentTime = secs
            }
        }

        // End-of-playback observer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.player?.seek(to: .zero)
            self?.currentTime = 0
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = playbackSpeed
            isPlaying = true
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }

    deinit {
        cleanup()
    }
}
