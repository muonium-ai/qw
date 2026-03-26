//
//  ImageViewerView.swift
//  qw
//
//  Native image viewer with zoom, pan, and image info controls.
//  Ticket: T-000050
//

import SwiftUI
import ImageIO

#if os(macOS)
import AppKit

/// A native image viewer with zoom, pan, and metadata display.
struct ImageViewerView: View {
    let data: Data
    var fileURL: URL?

    // MARK: - State

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var showInfo: Bool = false
    @State private var imageSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var fitScale: CGFloat = 1.0

    // MARK: - Derived

    private var nsImage: NSImage? {
        NSImage(data: data)
    }

    private var formatName: String {
        MagicBytes.detect(from: data)?.name ?? "Unknown"
    }

    private var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    private var imageProperties: ImageProperties {
        ImageProperties.extract(from: data)
    }

    private var exifMetadata: ExifMetadata {
        ExifParser.parse(data: data)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dark background
            Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
                .ignoresSafeArea()

            if let nsImage = nsImage {
                GeometryReader { geo in
                    let img = Image(nsImage: nsImage)

                    ZStack {
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomScale)
                            .offset(panOffset)
                            .gesture(panGesture)
                            .gesture(magnifyGesture)
                            .accessibilityIdentifier("imageContent")
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onAppear {
                        containerSize = geo.size
                        let rep = nsImage.representations.first
                        let w = CGFloat(rep?.pixelsWide ?? Int(nsImage.size.width))
                        let h = CGFloat(rep?.pixelsHigh ?? Int(nsImage.size.height))
                        imageSize = CGSize(width: w, height: h)
                        computeFitScale()
                    }
                    .onChange(of: geo.size) { _, newSize in
                        containerSize = newSize
                        computeFitScale()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Unable to load image")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            // Info panel overlay
            if showInfo {
                infoPanel
            }
        }
        .overlay(alignment: .bottom) {
            toolbarView
        }
        .onAppear {
            // Start at fit-to-window
            zoomScale = 1.0
            lastZoomScale = 1.0
        }
        .accessibilityIdentifier("imageViewer")
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 16) {
            // Zoom percentage
            Text("\(Int(zoomScale * 100))%")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 56, alignment: .center)

            Divider()
                .frame(height: 20)

            // Zoom out
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Zoom Out")

            // Zoom in
            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Zoom In")

            Divider()
                .frame(height: 20)

            // Fit to window
            Button(action: fitToWindow) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Fit to Window")

            // Actual size
            Button(action: actualSize) {
                Text("1:1")
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Actual Size (100%)")

            Divider()
                .frame(height: 20)

            // Info toggle
            Button(action: { showInfo.toggle() }) {
                Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Image Info")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .padding(.bottom, 16)
    }

    // MARK: - Info Panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Basic image info
                    infoPanelSection("Image") {
                        infoRow("Format", formatName)
                        infoRow("File Size", fileSizeString)
                        if imageSize.width > 0 && imageSize.height > 0 {
                            infoRow("Dimensions", "\(Int(imageSize.width)) x \(Int(imageSize.height)) px")
                        }
                        if let props = imageProperties.colorModel {
                            infoRow("Color Model", props)
                        }
                        if let depth = imageProperties.bitDepth {
                            infoRow("Bit Depth", "\(depth)")
                        }
                        if let dpi = imageProperties.dpi {
                            infoRow("DPI", "\(Int(dpi))")
                        }
                        if let profile = imageProperties.profileName {
                            infoRow("ICC Profile", profile)
                        }
                        if let url = fileURL {
                            infoRow("File Name", url.lastPathComponent)
                        }
                    }

                    // EXIF / TIFF / GPS / IPTC metadata
                    let metadata = exifMetadata
                    if !metadata.isEmpty {
                        let categories = orderedCategories(from: metadata.entries)
                        ForEach(categories, id: \.self) { category in
                            let categoryEntries = metadata.entries.filter { $0.category == category }
                            infoPanelSection(category) {
                                ForEach(Array(categoryEntries.enumerated()), id: \.offset) { _, entry in
                                    infoRow(entry.key, entry.value)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
    }

    private func infoPanelSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
            content()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption, design: .default))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .default))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
        }
    }

    /// Returns categories in a stable display order.
    private func orderedCategories(from entries: [ExifMetadata.Entry]) -> [String] {
        let order = ["Image", "TIFF", "EXIF", "GPS", "IPTC"]
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            // Skip "Image" since we show it in the basic section
            guard entry.category != "Image" else { continue }
            if !seen.contains(entry.category) {
                seen.insert(entry.category)
                result.append(entry.category)
            }
        }
        return result.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastZoomScale * value.magnification
                zoomScale = min(max(newScale, 0.1), 20.0)
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    // MARK: - Zoom Actions

    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = min(zoomScale * 1.25, 20.0)
            lastZoomScale = zoomScale
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = max(zoomScale / 1.25, 0.1)
            lastZoomScale = zoomScale
        }
    }

    private func fitToWindow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
    }

    private func actualSize() {
        guard imageSize.width > 0, containerSize.width > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            // Calculate the scale needed so the image displays at true pixel size.
            // SwiftUI's .fit already scales the image to fit the container;
            // we need to counteract that scaling to reach 1:1 pixels.
            let scaleX = containerSize.width / imageSize.width
            let scaleY = containerSize.height / imageSize.height
            let currentFit = min(scaleX, scaleY)
            if currentFit > 0 {
                zoomScale = 1.0 / currentFit
            } else {
                zoomScale = 1.0
            }
            lastZoomScale = zoomScale
            panOffset = .zero
            lastPanOffset = .zero
        }
    }

    private func computeFitScale() {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return }
        let scaleX = containerSize.width / imageSize.width
        let scaleY = containerSize.height / imageSize.height
        fitScale = min(scaleX, scaleY)
    }
}

// MARK: - ImageProperties

/// Extracts basic image properties using ImageIO (no NSImage needed).
private struct ImageProperties {
    var colorModel: String?
    var bitDepth: Int?
    var dpi: Double?
    var profileName: String?

    static func extract(from data: Data) -> ImageProperties {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImageProperties()
        }
        var result = ImageProperties()
        if let cm = props[kCGImagePropertyColorModel] as? String {
            result.colorModel = cm
        }
        if let d = props[kCGImagePropertyDepth] as? Int {
            result.bitDepth = d
        }
        if let dw = props[kCGImagePropertyDPIWidth] as? Double {
            result.dpi = dw
        }
        if let pn = props[kCGImagePropertyProfileName] as? String {
            result.profileName = pn
        }
        return result
    }
}

#else

/// Placeholder for non-macOS platforms.
struct ImageViewerView: View {
    let data: Data
    var fileURL: URL?

    var body: some View {
        Text("Image viewer is not available on this platform.")
            .foregroundStyle(.secondary)
    }
}

#endif
