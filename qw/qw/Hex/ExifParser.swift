//
//  ExifParser.swift
//  qw
//
//  Extracts EXIF, TIFF, GPS, and IPTC metadata from image data (JPEG, PNG)
//  using Apple's ImageIO framework (CGImageSource).
//  Ticket: T-000041
//

import Foundation
import ImageIO

// MARK: - ExifMetadata

/// Structured result holding extracted image metadata fields as key-value pairs.
struct ExifMetadata {
    /// Ordered list of metadata entries for display.
    let entries: [Entry]

    struct Entry {
        let category: String   // e.g. "EXIF", "TIFF", "GPS", "IPTC", "Image"
        let key: String        // human-readable field name
        let value: String      // formatted value
    }

    /// Whether any metadata was found.
    var isEmpty: Bool { entries.isEmpty }
}

// MARK: - ExifParser

/// Parses EXIF and related metadata from image data using Apple's ImageIO framework.
enum ExifParser {

    /// Extract metadata from raw image data (JPEG or PNG).
    /// Returns an `ExifMetadata` with all discovered fields, or an empty result
    /// if the data is not a supported image or contains no metadata.
    static func parse(data: Data) -> ExifMetadata {
        guard !data.isEmpty else { return ExifMetadata(entries: []) }

        // Create an image source from the data
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ExifMetadata(entries: [])
        }

        // Get properties for the first image in the source
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ExifMetadata(entries: [])
        }

        var entries: [ExifMetadata.Entry] = []

        // Top-level image properties
        extractTopLevelProperties(from: properties, into: &entries)

        // TIFF dictionary
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            extractTIFFProperties(from: tiff, into: &entries)
        }

        // EXIF dictionary
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            extractEXIFProperties(from: exif, into: &entries)
        }

        // GPS dictionary
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            extractGPSProperties(from: gps, into: &entries)
        }

        // IPTC dictionary
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            extractIPTCProperties(from: iptc, into: &entries)
        }

        return ExifMetadata(entries: entries)
    }

    // MARK: - Top-level properties

    private static func extractTopLevelProperties(from props: [CFString: Any], into entries: inout [ExifMetadata.Entry]) {
        if let width = props[kCGImagePropertyPixelWidth] {
            entries.append(.init(category: "Image", key: "Pixel Width", value: "\(width)"))
        }
        if let height = props[kCGImagePropertyPixelHeight] {
            entries.append(.init(category: "Image", key: "Pixel Height", value: "\(height)"))
        }
        if let dpiWidth = props[kCGImagePropertyDPIWidth] {
            entries.append(.init(category: "Image", key: "DPI Width", value: "\(dpiWidth)"))
        }
        if let dpiHeight = props[kCGImagePropertyDPIHeight] {
            entries.append(.init(category: "Image", key: "DPI Height", value: "\(dpiHeight)"))
        }
        if let depth = props[kCGImagePropertyDepth] {
            entries.append(.init(category: "Image", key: "Bit Depth", value: "\(depth)"))
        }
        if let colorModel = props[kCGImagePropertyColorModel] {
            entries.append(.init(category: "Image", key: "Color Model", value: "\(colorModel)"))
        }
        if let profileName = props[kCGImagePropertyProfileName] {
            entries.append(.init(category: "Image", key: "ICC Profile", value: "\(profileName)"))
        }
        if let orientation = props[kCGImagePropertyOrientation] as? Int {
            entries.append(.init(category: "Image", key: "Orientation", value: orientationName(orientation)))
        }
    }

    // MARK: - TIFF properties

    private static func extractTIFFProperties(from tiff: [CFString: Any], into entries: inout [ExifMetadata.Entry]) {
        if let make = tiff[kCGImagePropertyTIFFMake] as? String {
            entries.append(.init(category: "TIFF", key: "Camera Make", value: make))
        }
        if let model = tiff[kCGImagePropertyTIFFModel] as? String {
            entries.append(.init(category: "TIFF", key: "Camera Model", value: model))
        }
        if let software = tiff[kCGImagePropertyTIFFSoftware] as? String {
            entries.append(.init(category: "TIFF", key: "Software", value: software))
        }
        if let dateTime = tiff[kCGImagePropertyTIFFDateTime] as? String {
            entries.append(.init(category: "TIFF", key: "Date/Time", value: dateTime))
        }
        if let artist = tiff[kCGImagePropertyTIFFArtist] as? String {
            entries.append(.init(category: "TIFF", key: "Artist", value: artist))
        }
        if let copyright = tiff[kCGImagePropertyTIFFCopyright] as? String {
            entries.append(.init(category: "TIFF", key: "Copyright", value: copyright))
        }
        if let desc = tiff[kCGImagePropertyTIFFImageDescription] as? String {
            entries.append(.init(category: "TIFF", key: "Description", value: desc))
        }
        if let xRes = tiff[kCGImagePropertyTIFFXResolution] {
            entries.append(.init(category: "TIFF", key: "X Resolution", value: "\(xRes)"))
        }
        if let yRes = tiff[kCGImagePropertyTIFFYResolution] {
            entries.append(.init(category: "TIFF", key: "Y Resolution", value: "\(yRes)"))
        }
        if let resUnit = tiff[kCGImagePropertyTIFFResolutionUnit] as? Int {
            let unitName: String
            switch resUnit {
            case 2: unitName = "inches"
            case 3: unitName = "centimeters"
            default: unitName = "\(resUnit)"
            }
            entries.append(.init(category: "TIFF", key: "Resolution Unit", value: unitName))
        }
    }

    // MARK: - EXIF properties

    private static func extractEXIFProperties(from exif: [CFString: Any], into entries: inout [ExifMetadata.Entry]) {
        if let dateOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            entries.append(.init(category: "EXIF", key: "Date Taken", value: dateOriginal))
        }
        if let dateDigitized = exif[kCGImagePropertyExifDateTimeDigitized] as? String {
            entries.append(.init(category: "EXIF", key: "Date Digitized", value: dateDigitized))
        }
        if let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double {
            let display: String
            if exposureTime >= 1.0 {
                display = String(format: "%.1f s", exposureTime)
            } else if exposureTime > 0 {
                let denom = Int(round(1.0 / exposureTime))
                display = "1/\(denom) s"
            } else {
                display = "\(exposureTime)"
            }
            entries.append(.init(category: "EXIF", key: "Exposure Time", value: display))
        }
        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
            entries.append(.init(category: "EXIF", key: "F-Number", value: String(format: "f/%.1f", fNumber)))
        }
        if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = iso.first {
            entries.append(.init(category: "EXIF", key: "ISO Speed", value: "ISO \(first)"))
        }
        if let focalLength = exif[kCGImagePropertyExifFocalLength] as? Double {
            entries.append(.init(category: "EXIF", key: "Focal Length", value: String(format: "%.1f mm", focalLength)))
        }
        if let focalLength35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
            entries.append(.init(category: "EXIF", key: "Focal Length (35mm)", value: "\(focalLength35) mm"))
        }
        if let aperture = exif[kCGImagePropertyExifApertureValue] as? Double {
            entries.append(.init(category: "EXIF", key: "Aperture Value", value: String(format: "%.2f", aperture)))
        }
        if let brightness = exif[kCGImagePropertyExifBrightnessValue] as? Double {
            entries.append(.init(category: "EXIF", key: "Brightness", value: String(format: "%.2f", brightness)))
        }
        if let exposureBias = exif[kCGImagePropertyExifExposureBiasValue] as? Double {
            entries.append(.init(category: "EXIF", key: "Exposure Bias", value: String(format: "%+.1f EV", exposureBias)))
        }
        if let meteringMode = exif[kCGImagePropertyExifMeteringMode] as? Int {
            entries.append(.init(category: "EXIF", key: "Metering Mode", value: meteringModeName(meteringMode)))
        }
        if let flash = exif[kCGImagePropertyExifFlash] as? Int {
            entries.append(.init(category: "EXIF", key: "Flash", value: flashDescription(flash)))
        }
        if let whiteBalance = exif[kCGImagePropertyExifWhiteBalance] as? Int {
            entries.append(.init(category: "EXIF", key: "White Balance", value: whiteBalance == 0 ? "Auto" : "Manual"))
        }
        if let exposureMode = exif[kCGImagePropertyExifExposureMode] as? Int {
            let name: String
            switch exposureMode {
            case 0: name = "Auto"
            case 1: name = "Manual"
            case 2: name = "Auto Bracket"
            default: name = "\(exposureMode)"
            }
            entries.append(.init(category: "EXIF", key: "Exposure Mode", value: name))
        }
        if let exposureProgram = exif[kCGImagePropertyExifExposureProgram] as? Int {
            entries.append(.init(category: "EXIF", key: "Exposure Program", value: exposureProgramName(exposureProgram)))
        }
        if let lensModel = exif[kCGImagePropertyExifLensModel] as? String {
            entries.append(.init(category: "EXIF", key: "Lens Model", value: lensModel))
        }
        if let lensMake = exif[kCGImagePropertyExifLensMake] as? String {
            entries.append(.init(category: "EXIF", key: "Lens Make", value: lensMake))
        }
        if let colorSpace = exif[kCGImagePropertyExifColorSpace] as? Int {
            let name: String
            switch colorSpace {
            case 1: name = "sRGB"
            case 0xFFFF: name = "Uncalibrated"
            default: name = "\(colorSpace)"
            }
            entries.append(.init(category: "EXIF", key: "Color Space", value: name))
        }
        if let widthPx = exif[kCGImagePropertyExifPixelXDimension] {
            entries.append(.init(category: "EXIF", key: "Image Width", value: "\(widthPx)"))
        }
        if let heightPx = exif[kCGImagePropertyExifPixelYDimension] {
            entries.append(.init(category: "EXIF", key: "Image Height", value: "\(heightPx)"))
        }
        if let sceneCaptureType = exif[kCGImagePropertyExifSceneCaptureType] as? Int {
            let name: String
            switch sceneCaptureType {
            case 0: name = "Standard"
            case 1: name = "Landscape"
            case 2: name = "Portrait"
            case 3: name = "Night"
            default: name = "\(sceneCaptureType)"
            }
            entries.append(.init(category: "EXIF", key: "Scene Capture", value: name))
        }
        if let subjectDistance = exif[kCGImagePropertyExifSubjectDistance] as? Double {
            entries.append(.init(category: "EXIF", key: "Subject Distance", value: String(format: "%.2f m", subjectDistance)))
        }
        if let digitalZoom = exif[kCGImagePropertyExifDigitalZoomRatio] as? Double {
            entries.append(.init(category: "EXIF", key: "Digital Zoom", value: String(format: "%.1fx", digitalZoom)))
        }
    }

    // MARK: - GPS properties

    private static func extractGPSProperties(from gps: [CFString: Any], into entries: inout [ExifMetadata.Entry]) {
        // Latitude
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String {
            let sign = latRef == "S" ? -1.0 : 1.0
            entries.append(.init(category: "GPS", key: "Latitude", value: formatCoordinate(lat * sign, isLatitude: true)))
        }

        // Longitude
        if let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
           let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
            let sign = lonRef == "W" ? -1.0 : 1.0
            entries.append(.init(category: "GPS", key: "Longitude", value: formatCoordinate(lon * sign, isLatitude: false)))
        }

        // Altitude
        if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
            let altRef = gps[kCGImagePropertyGPSAltitudeRef] as? Int ?? 0
            let signedAlt = altRef == 1 ? -alt : alt
            entries.append(.init(category: "GPS", key: "Altitude", value: String(format: "%.1f m", signedAlt)))
        }

        // Speed
        if let speed = gps[kCGImagePropertyGPSSpeed] as? Double,
           let speedRef = gps[kCGImagePropertyGPSSpeedRef] as? String {
            let unit: String
            switch speedRef {
            case "K": unit = "km/h"
            case "M": unit = "mph"
            case "N": unit = "knots"
            default: unit = speedRef
            }
            entries.append(.init(category: "GPS", key: "Speed", value: String(format: "%.1f %@", speed, unit)))
        }

        // Direction
        if let direction = gps[kCGImagePropertyGPSImgDirection] as? Double {
            entries.append(.init(category: "GPS", key: "Image Direction", value: String(format: "%.1f\u{00B0}", direction)))
        }

        // Timestamp
        if let timestamp = gps[kCGImagePropertyGPSTimeStamp] as? String {
            entries.append(.init(category: "GPS", key: "GPS Timestamp", value: timestamp))
        }
        if let dateStamp = gps[kCGImagePropertyGPSDateStamp] as? String {
            entries.append(.init(category: "GPS", key: "GPS Date", value: dateStamp))
        }
    }

    // MARK: - IPTC properties

    private static func extractIPTCProperties(from iptc: [CFString: Any], into entries: inout [ExifMetadata.Entry]) {
        if let caption = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String {
            entries.append(.init(category: "IPTC", key: "Caption", value: caption))
        }
        if let headline = iptc[kCGImagePropertyIPTCHeadline] as? String {
            entries.append(.init(category: "IPTC", key: "Headline", value: headline))
        }
        if let keywords = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
            entries.append(.init(category: "IPTC", key: "Keywords", value: keywords.joined(separator: ", ")))
        }
        if let creator = iptc[kCGImagePropertyIPTCCreatorContactInfo] as? String {
            entries.append(.init(category: "IPTC", key: "Creator", value: creator))
        }
        if let copyright = iptc[kCGImagePropertyIPTCCopyrightNotice] as? String {
            entries.append(.init(category: "IPTC", key: "Copyright", value: copyright))
        }
        if let city = iptc[kCGImagePropertyIPTCCity] as? String {
            entries.append(.init(category: "IPTC", key: "City", value: city))
        }
        if let country = iptc[kCGImagePropertyIPTCCountryPrimaryLocationName] as? String {
            entries.append(.init(category: "IPTC", key: "Country", value: country))
        }
    }

    // MARK: - Formatting helpers

    private static func orientationName(_ value: Int) -> String {
        switch value {
        case 1: return "Normal (1)"
        case 2: return "Flipped Horizontal (2)"
        case 3: return "Rotated 180\u{00B0} (3)"
        case 4: return "Flipped Vertical (4)"
        case 5: return "Transposed (5)"
        case 6: return "Rotated 90\u{00B0} CW (6)"
        case 7: return "Transversed (7)"
        case 8: return "Rotated 90\u{00B0} CCW (8)"
        default: return "\(value)"
        }
    }

    private static func meteringModeName(_ value: Int) -> String {
        switch value {
        case 0: return "Unknown"
        case 1: return "Average"
        case 2: return "Center-Weighted"
        case 3: return "Spot"
        case 4: return "Multi-Spot"
        case 5: return "Pattern"
        case 6: return "Partial"
        default: return "\(value)"
        }
    }

    private static func flashDescription(_ value: Int) -> String {
        let fired = (value & 0x01) != 0
        return fired ? "Fired" : "Did not fire"
    }

    private static func exposureProgramName(_ value: Int) -> String {
        switch value {
        case 0: return "Not Defined"
        case 1: return "Manual"
        case 2: return "Normal Program"
        case 3: return "Aperture Priority"
        case 4: return "Shutter Priority"
        case 5: return "Creative"
        case 6: return "Action"
        case 7: return "Portrait"
        case 8: return "Landscape"
        default: return "\(value)"
        }
    }

    /// Format a GPS coordinate as degrees, minutes, seconds.
    private static func formatCoordinate(_ decimal: Double, isLatitude: Bool) -> String {
        let abs = Swift.abs(decimal)
        let degrees = Int(abs)
        let minutesFull = (abs - Double(degrees)) * 60.0
        let minutes = Int(minutesFull)
        let seconds = (minutesFull - Double(minutes)) * 60.0
        let direction: String
        if isLatitude {
            direction = decimal >= 0 ? "N" : "S"
        } else {
            direction = decimal >= 0 ? "E" : "W"
        }
        return String(format: "%d\u{00B0} %d' %.1f\" %@", degrees, minutes, seconds, direction)
    }
}
