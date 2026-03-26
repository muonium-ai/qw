//
//  VideoPlayerView.swift
//  qw
//
//  Native video player with playback controls: play/pause, seek, speed, volume.
//  Ticket: T-000051
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

#if os(macOS)

// MARK: - VideoPlayerView

/// A SwiftUI video player view with custom overlay controls.
struct VideoPlayerView: View {
    let fileURL: URL
    var onSwitchToHex: (() -> Void)?
    var onOpenExternal: (() -> Void)?

    @StateObject private var controller: VideoPlayerController

    init(fileURL: URL, onSwitchToHex: (() -> Void)? = nil, onOpenExternal: (() -> Void)? = nil) {
        self.fileURL = fileURL
        self.onSwitchToHex = onSwitchToHex
        self.onOpenExternal = onOpenExternal
        _controller = StateObject(wrappedValue: VideoPlayerController(url: fileURL))
    }

    var body: some View {
        ZStack {
            // Video layer
            if controller.hasError {
                videoErrorView
            } else {
                AVPlayerViewRepresentable(player: controller.player)
                    .accessibilityIdentifier("videoPlayerView")
            }

            // Controls overlay at bottom
            VStack {
                // Title bar at top
                videoTitleBar
                Spacer()
                if !controller.hasError {
                    controlsOverlay
                }
            }
        }
        .background(Color.black)
        .onDisappear {
            controller.pause()
        }
    }

    // MARK: - Title bar

    private var videoTitleBar: some View {
        HStack {
            Image(systemName: "film")
                .foregroundColor(.white)
            Text(fileURL.lastPathComponent)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Error view

    private var videoErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to play this video")
                .font(.headline)
                .foregroundColor(.white)
            Text(controller.errorMessage)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Text("The format may not be supported by the built-in player.")
                .font(.caption2)
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                Button("Open in Default App") {
                    if let action = onOpenExternal {
                        action()
                    } else {
                        NSWorkspace.shared.open(fileURL)
                    }
                }
                .buttonStyle(.borderedProminent)

                if let onSwitchToHex {
                    Button("View in Hex Mode") {
                        onSwitchToHex()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 6) {
            // Seek bar
            seekBar

            // Bottom row: play, time, spacer, speed, volume, mute
            HStack(spacing: 12) {
                playPauseButton
                timeLabel
                Spacer()
                speedMenu
                volumeControl
                muteButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Play/Pause

    private var playPauseButton: some View {
        Button(action: { controller.togglePlayPause() }) {
            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .help(controller.isPlaying ? "Pause" : "Play")
        .accessibilityIdentifier("videoPlayPauseButton")
    }

    // MARK: - Seek bar

    private var seekBar: some View {
        Slider(
            value: Binding(
                get: { controller.currentTime },
                set: { controller.seek(to: $0) }
            ),
            in: 0...max(controller.duration, 0.01)
        )
        .tint(.white)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("videoSeekBar")
    }

    // MARK: - Time label

    private var timeLabel: some View {
        Text("\(formatTime(controller.currentTime)) / \(formatTime(controller.duration))")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.white)
    }

    // MARK: - Speed menu

    private var speedMenu: some View {
        Menu {
            ForEach(VideoPlayerController.speedOptions, id: \.self) { speed in
                Button(action: { controller.setSpeed(speed) }) {
                    HStack {
                        Text(speedLabel(speed))
                        if abs(controller.playbackSpeed - speed) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(speedLabel(controller.playbackSpeed))
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.2))
                .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Playback speed")
        .accessibilityIdentifier("videoSpeedMenu")
    }

    // MARK: - Volume

    private var volumeControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundColor(.white)
            Slider(
                value: Binding(
                    get: { controller.volume },
                    set: { controller.setVolume($0) }
                ),
                in: 0...1
            )
            .frame(width: 80)
            .tint(.white)
        }
        .accessibilityIdentifier("videoVolumeControl")
    }

    private var muteButton: some View {
        Button(action: { controller.toggleMute() }) {
            Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundColor(controller.isMuted ? .red : .white)
        }
        .buttonStyle(.plain)
        .help(controller.isMuted ? "Unmute" : "Mute")
        .accessibilityIdentifier("videoMuteButton")
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == Float(Int(speed)) {
            return "\(Int(speed))x"
        }
        return String(format: "%.2gx", speed)
    }
}

// MARK: - AVPlayerViewRepresentable

/// Wraps `AVPlayerView` for use in SwiftUI.
private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none  // We provide our own controls
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - VideoPlayerController

/// Manages AVPlayer state for the video player view.
final class VideoPlayerController: ObservableObject {
    let player: AVPlayer

    static let speedOptions: [Float] = [1.0, 1.25, 1.5, 2.0, 4.0, 8.0]

    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var isMuted: Bool = false
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""

    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?

    private let fileURL: URL

    init(url: URL) {
        self.fileURL = url
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.player = AVPlayer()
            self.hasError = true
            self.errorMessage = "File not found: \(url.lastPathComponent)"
            FormatLogger.logOpenFailure(fileURL: url, formatName: nil, mode: "video", error: "File not found")
            return
        }

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: item)
        self.player.volume = 1.0

        setupObservers()
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        statusObservation?.invalidate()
        rateObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupObservers() {
        // Periodic time observer for seek bar updates
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                self.currentTime = seconds
            }
        }

        // Observe player item status
        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite {
                        self.duration = dur
                    }
                    FormatLogger.logOpenSuccess(fileURL: self.fileURL, formatName: nil, mode: "video")
                case .failed:
                    self.hasError = true
                    self.errorMessage = item.error?.localizedDescription ?? "Unknown playback error"
                    FormatLogger.logOpenFailure(fileURL: self.fileURL, formatName: nil, mode: "video", error: self.errorMessage)
                default:
                    break
                }
            }
        }

        // Observe rate for play/pause state
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.rate > 0
            }
        }

        // Observe end of playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.player.seek(to: .zero)
        }
    }

    // MARK: - Controls

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        player.rate = playbackSpeed
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player.volume = vol
        if vol > 0 && isMuted {
            isMuted = false
            player.isMuted = false
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }
}

#endif
