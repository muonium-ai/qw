use wasm_bindgen::prelude::*;
use serde::Serialize;

// ---------------------------------------------------------------------------
// File type detection
// ---------------------------------------------------------------------------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileTypeMatch {
    name: String,
    description: String,
    match_offset: usize,
    match_length: usize,
}

/// Detect the file type from its raw bytes by checking magic-number signatures.
/// Returns a JSON string with match info, or `"{}"` if the type is unknown.
#[wasm_bindgen]
pub fn detect_file_type(data: &[u8]) -> String {
    if let Some(ft) = detect_file_type_inner(data) {
        serde_json::to_string(&ft).unwrap_or_else(|_| "{}".into())
    } else {
        "{}".into()
    }
}

fn starts_with(data: &[u8], offset: usize, needle: &[u8]) -> bool {
    if data.len() < offset + needle.len() {
        return false;
    }
    &data[offset..offset + needle.len()] == needle
}

fn detect_file_type_inner(data: &[u8]) -> Option<FileTypeMatch> {
    if data.is_empty() {
        return None;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if starts_with(data, 0, &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return Some(FileTypeMatch {
            name: "PNG Image".into(),
            description: "Portable Network Graphics image".into(),
            match_offset: 0,
            match_length: 8,
        });
    }

    // JPEG: FF D8 FF
    if starts_with(data, 0, &[0xFF, 0xD8, 0xFF]) {
        return Some(FileTypeMatch {
            name: "JPEG Image".into(),
            description: "JPEG image".into(),
            match_offset: 0,
            match_length: 3,
        });
    }

    // GIF: GIF87a or GIF89a
    if starts_with(data, 0, b"GIF87a") || starts_with(data, 0, b"GIF89a") {
        return Some(FileTypeMatch {
            name: "GIF Image".into(),
            description: "Graphics Interchange Format image".into(),
            match_offset: 0,
            match_length: 6,
        });
    }

    // PDF: %PDF
    if starts_with(data, 0, b"%PDF") {
        return Some(FileTypeMatch {
            name: "PDF Document".into(),
            description: "Portable Document Format".into(),
            match_offset: 0,
            match_length: 4,
        });
    }

    // ZIP: PK\x03\x04
    if starts_with(data, 0, &[0x50, 0x4B, 0x03, 0x04]) {
        return Some(FileTypeMatch {
            name: "ZIP Archive".into(),
            description: "ZIP compressed archive".into(),
            match_offset: 0,
            match_length: 4,
        });
    }

    // ELF: \x7FELF
    if starts_with(data, 0, &[0x7F, 0x45, 0x4C, 0x46]) {
        return Some(FileTypeMatch {
            name: "ELF Binary".into(),
            description: "Executable and Linkable Format binary".into(),
            match_offset: 0,
            match_length: 4,
        });
    }

    // Mach-O: four magic variants
    // MH_MAGIC (32-bit): FE ED FA CE
    if starts_with(data, 0, &[0xFE, 0xED, 0xFA, 0xCE]) {
        return Some(FileTypeMatch {
            name: "Mach-O Binary".into(),
            description: "Mach-O 32-bit big-endian executable".into(),
            match_offset: 0,
            match_length: 4,
        });
    }
    // MH_CIGAM (32-bit reversed): CE FA ED FE
    if starts_with(data, 0, &[0xCE, 0xFA, 0xED, 0xFE]) {
        return Some(FileTypeMatch {
            name: "Mach-O Binary".into(),
            description: "Mach-O 32-bit little-endian executable".into(),
            match_offset: 0,
            match_length: 4,
        });
    }
    // MH_MAGIC_64 (64-bit): FE ED FA CF
    if starts_with(data, 0, &[0xFE, 0xED, 0xFA, 0xCF]) {
        return Some(FileTypeMatch {
            name: "Mach-O Binary".into(),
            description: "Mach-O 64-bit big-endian executable".into(),
            match_offset: 0,
            match_length: 4,
        });
    }
    // MH_CIGAM_64 (64-bit reversed): CF FA ED FE
    if starts_with(data, 0, &[0xCF, 0xFA, 0xED, 0xFE]) {
        return Some(FileTypeMatch {
            name: "Mach-O Binary".into(),
            description: "Mach-O 64-bit little-endian executable".into(),
            match_offset: 0,
            match_length: 4,
        });
    }

    // MP4 (ftyp box): bytes 4..8 == "ftyp"
    if data.len() >= 8 && &data[4..8] == b"ftyp" {
        return Some(FileTypeMatch {
            name: "MP4 Video".into(),
            description: "MPEG-4 Part 14 media container".into(),
            match_offset: 4,
            match_length: 4,
        });
    }

    // RIFF/WAV: RIFF....WAVE
    if data.len() >= 12 && starts_with(data, 0, b"RIFF") && &data[8..12] == b"WAVE" {
        return Some(FileTypeMatch {
            name: "WAV Audio".into(),
            description: "Waveform Audio File Format".into(),
            match_offset: 0,
            match_length: 4,
        });
    }

    // Gzip: 1F 8B
    if starts_with(data, 0, &[0x1F, 0x8B]) {
        return Some(FileTypeMatch {
            name: "Gzip Archive".into(),
            description: "GNU zip compressed data".into(),
            match_offset: 0,
            match_length: 2,
        });
    }

    // Bzip2: BZ
    if starts_with(data, 0, b"BZ") && data.len() >= 3 && (data[2] == b'h' || data[2] == b'0') {
        return Some(FileTypeMatch {
            name: "Bzip2 Archive".into(),
            description: "Bzip2 compressed data".into(),
            match_offset: 0,
            match_length: 2,
        });
    }

    // XZ: FD 37 7A 58 5A 00
    if starts_with(data, 0, &[0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
        return Some(FileTypeMatch {
            name: "XZ Archive".into(),
            description: "XZ compressed data".into(),
            match_offset: 0,
            match_length: 6,
        });
    }

    // WASM: \0asm
    if starts_with(data, 0, &[0x00, 0x61, 0x73, 0x6D]) {
        return Some(FileTypeMatch {
            name: "WebAssembly".into(),
            description: "WebAssembly binary module".into(),
            match_offset: 0,
            match_length: 4,
        });
    }

    // PE/EXE: MZ
    if starts_with(data, 0, b"MZ") {
        return Some(FileTypeMatch {
            name: "PE Executable".into(),
            description: "Windows Portable Executable".into(),
            match_offset: 0,
            match_length: 2,
        });
    }

    // SQLite: "SQLite format 3\0"
    if starts_with(data, 0, b"SQLite format 3\x00") {
        return Some(FileTypeMatch {
            name: "SQLite Database".into(),
            description: "SQLite 3 database file".into(),
            match_offset: 0,
            match_length: 16,
        });
    }

    // XML: <?xml or BOM + <?xml
    if starts_with(data, 0, b"<?xml")
        || starts_with(data, 0, &[0xEF, 0xBB, 0xBF, 0x3C, 0x3F]) // UTF-8 BOM + <?
    {
        return Some(FileTypeMatch {
            name: "XML Document".into(),
            description: "Extensible Markup Language document".into(),
            match_offset: 0,
            match_length: 5,
        });
    }

    // JSON: heuristic — starts with { or [
    if !data.is_empty() {
        let first = skip_whitespace_and_bom(data);
        if first == Some(b'{') || first == Some(b'[') {
            return Some(FileTypeMatch {
                name: "JSON Document".into(),
                description: "JavaScript Object Notation data".into(),
                match_offset: 0,
                match_length: 1,
            });
        }
    }

    None
}

fn skip_whitespace_and_bom(data: &[u8]) -> Option<u8> {
    let mut i = 0;
    // Skip UTF-8 BOM
    if data.len() >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
        i = 3;
    }
    while i < data.len() {
        match data[i] {
            b' ' | b'\t' | b'\n' | b'\r' => i += 1,
            other => return Some(other),
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Hex formatting
// ---------------------------------------------------------------------------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HexRow {
    offset: String,
    hex: Vec<String>,
    ascii: String,
    byte_types: Vec<u8>,
}

/// Format a single hex-viewer row (16 bytes) starting at `offset`.
/// Returns a JSON string.
#[wasm_bindgen]
pub fn format_hex_row(offset: usize, data: &[u8]) -> String {
    let mut hex: Vec<String> = Vec::with_capacity(16);
    let mut ascii = String::with_capacity(16);
    let mut byte_types: Vec<u8> = Vec::with_capacity(16);

    for i in 0..16 {
        if i < data.len() {
            let b = data[i];
            hex.push(format!("{:02X}", b));
            ascii.push(to_ascii_char(b));
            byte_types.push(classify_byte(b));
        }
    }

    let row = HexRow {
        offset: format!("{:08X}", offset),
        hex,
        ascii,
        byte_types,
    };

    serde_json::to_string(&row).unwrap_or_else(|_| "{}".into())
}

fn to_ascii_char(b: u8) -> char {
    if b >= 0x20 && b <= 0x7E {
        b as char
    } else {
        '.'
    }
}

fn classify_byte(b: u8) -> u8 {
    match b {
        0x00 => 0,                      // null
        0x20..=0x7E => 1,               // printable ASCII
        0x80..=0xFF => 2,               // high byte (>127)
        _ => 3,                         // other non-printable
    }
}

// ---------------------------------------------------------------------------
// Byte decoding (data inspector)
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct SignedUnsigned<S: Serialize, U: Serialize> {
    signed: S,
    unsigned: U,
}

#[derive(Serialize)]
struct DecodedBytes {
    offset: String,
    hex: String,
    int8: SignedUnsigned<i8, u8>,
    int16: SignedUnsigned<i16, u16>,
    int32: SignedUnsigned<i32, u32>,
    int64: SignedUnsigned<String, String>,
    float32: String,
    float64: String,
    ascii: String,
    binary: String,
}

/// Decode bytes at `offset` in multiple numeric representations.
/// Returns a JSON string. i64/u64 are returned as strings to avoid JS precision loss.
#[wasm_bindgen]
pub fn decode_bytes(data: &[u8], offset: usize, little_endian: bool) -> String {
    if offset >= data.len() {
        return "{}".into();
    }

    let remaining = &data[offset..];

    // Gather up to 8 bytes for display
    let display_len = remaining.len().min(8);
    let hex_str: String = remaining[..display_len]
        .iter()
        .map(|b| format!("{:02X}", b))
        .collect::<Vec<_>>()
        .join(" ");

    let first_byte = remaining[0];

    // int8
    let int8 = SignedUnsigned {
        signed: first_byte as i8,
        unsigned: first_byte,
    };

    // int16
    let int16 = if remaining.len() >= 2 {
        let bytes: [u8; 2] = [remaining[0], remaining[1]];
        if little_endian {
            SignedUnsigned {
                signed: i16::from_le_bytes(bytes),
                unsigned: u16::from_le_bytes(bytes),
            }
        } else {
            SignedUnsigned {
                signed: i16::from_be_bytes(bytes),
                unsigned: u16::from_be_bytes(bytes),
            }
        }
    } else {
        SignedUnsigned { signed: first_byte as i8 as i16, unsigned: first_byte as u16 }
    };

    // int32
    let int32 = if remaining.len() >= 4 {
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&remaining[..4]);
        if little_endian {
            SignedUnsigned {
                signed: i32::from_le_bytes(bytes),
                unsigned: u32::from_le_bytes(bytes),
            }
        } else {
            SignedUnsigned {
                signed: i32::from_be_bytes(bytes),
                unsigned: u32::from_be_bytes(bytes),
            }
        }
    } else {
        SignedUnsigned { signed: 0, unsigned: 0 }
    };

    // int64 (as strings)
    let int64 = if remaining.len() >= 8 {
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&remaining[..8]);
        if little_endian {
            SignedUnsigned {
                signed: i64::from_le_bytes(bytes).to_string(),
                unsigned: u64::from_le_bytes(bytes).to_string(),
            }
        } else {
            SignedUnsigned {
                signed: i64::from_be_bytes(bytes).to_string(),
                unsigned: u64::from_be_bytes(bytes).to_string(),
            }
        }
    } else {
        SignedUnsigned { signed: "0".into(), unsigned: "0".into() }
    };

    // float32
    let float32 = if remaining.len() >= 4 {
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&remaining[..4]);
        let val = if little_endian {
            f32::from_le_bytes(bytes)
        } else {
            f32::from_be_bytes(bytes)
        };
        format_float(val as f64)
    } else {
        "N/A".into()
    };

    // float64
    let float64 = if remaining.len() >= 8 {
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&remaining[..8]);
        let val = if little_endian {
            f64::from_le_bytes(bytes)
        } else {
            f64::from_be_bytes(bytes)
        };
        format_float(val)
    } else {
        "N/A".into()
    };

    // ASCII character
    let ascii = if first_byte >= 0x20 && first_byte <= 0x7E {
        String::from(first_byte as char)
    } else {
        ".".into()
    };

    // Binary representation of first byte
    let binary = format!("{:08b}", first_byte);

    let decoded = DecodedBytes {
        offset: format!("0x{:08X}", offset),
        hex: hex_str,
        int8,
        int16,
        int32,
        int64,
        float32,
        float64,
        ascii,
        binary,
    };

    serde_json::to_string(&decoded).unwrap_or_else(|_| "{}".into())
}

fn format_float(val: f64) -> String {
    if val.is_nan() {
        "NaN".into()
    } else if val.is_infinite() {
        if val.is_sign_positive() { "Infinity".into() } else { "-Infinity".into() }
    } else {
        format!("{}", val)
    }
}

// ---------------------------------------------------------------------------
// File info
// ---------------------------------------------------------------------------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileInfo {
    file_size: usize,
    row_count: usize,
    detected_type: serde_json::Value,
}

/// Return high-level info about the loaded file (size, row count, detected type).
/// Returns a JSON string.
#[wasm_bindgen]
pub fn get_file_info(data: &[u8]) -> String {
    let file_size = data.len();
    let row_count = (file_size + 15) / 16; // ceil(file_size / 16)

    let detected_type = if let Some(ft) = detect_file_type_inner(data) {
        serde_json::to_value(&ft).unwrap_or(serde_json::Value::Object(serde_json::Map::new()))
    } else {
        serde_json::Value::Object(serde_json::Map::new())
    };

    let info = FileInfo {
        file_size,
        row_count,
        detected_type,
    };

    serde_json::to_string(&info).unwrap_or_else(|_| "{}".into())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_png() {
        let data = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00];
        let result = detect_file_type(&data);
        assert!(result.contains("PNG Image"));
    }

    #[test]
    fn test_detect_jpeg() {
        let data = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
        let result = detect_file_type(&data);
        assert!(result.contains("JPEG Image"));
    }

    #[test]
    fn test_detect_unknown() {
        let data = [0x01, 0x02, 0x03];
        let result = detect_file_type(&data);
        assert_eq!(result, "{}");
    }

    #[test]
    fn test_detect_macho_64_le() {
        let data = [0xCF, 0xFA, 0xED, 0xFE, 0x00];
        let result = detect_file_type(&data);
        assert!(result.contains("Mach-O Binary"));
    }

    #[test]
    fn test_detect_mp4() {
        let data = [0x00, 0x00, 0x00, 0x20, b'f', b't', b'y', b'p', b'i', b's', b'o', b'm'];
        let result = detect_file_type(&data);
        assert!(result.contains("MP4 Video"));
    }

    #[test]
    fn test_detect_sqlite() {
        let mut data = b"SQLite format 3\x00".to_vec();
        data.extend_from_slice(&[0x00; 16]);
        let result = detect_file_type(&data);
        assert!(result.contains("SQLite Database"));
    }

    #[test]
    fn test_format_hex_row() {
        let data = b"Hello, World!!!!";
        let result = format_hex_row(0, data);
        assert!(result.contains("48")); // 'H'
        assert!(result.contains("Hello, World!!!!"));
    }

    #[test]
    fn test_format_hex_row_short() {
        let data = b"Hi";
        let result = format_hex_row(0, data);
        let row: serde_json::Value = serde_json::from_str(&result).unwrap();
        assert_eq!(row["hex"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_byte_types() {
        // null, printable, high byte, non-printable
        let data = [0x00, 0x41, 0x80, 0x01];
        let result = format_hex_row(0, &data);
        let row: serde_json::Value = serde_json::from_str(&result).unwrap();
        let types = row["byteTypes"].as_array().unwrap();
        assert_eq!(types[0], 0); // null
        assert_eq!(types[1], 1); // printable
        assert_eq!(types[2], 2); // high byte
        assert_eq!(types[3], 3); // non-printable
    }

    #[test]
    fn test_decode_bytes_le() {
        let data: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
        let result = decode_bytes(&data, 0, true);
        let decoded: serde_json::Value = serde_json::from_str(&result).unwrap();
        assert_eq!(decoded["int8"]["signed"], -1);
        assert_eq!(decoded["int8"]["unsigned"], 255);
        assert_eq!(decoded["binary"], "11111111");
    }

    #[test]
    fn test_decode_bytes_offset_past_end() {
        let data = [0x01, 0x02];
        let result = decode_bytes(&data, 10, true);
        assert_eq!(result, "{}");
    }

    #[test]
    fn test_get_file_info() {
        let data = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00];
        let result = get_file_info(&data);
        let info: serde_json::Value = serde_json::from_str(&result).unwrap();
        assert_eq!(info["fileSize"], 10);
        assert_eq!(info["rowCount"], 1);
        assert!(info["detectedType"]["name"].as_str().unwrap().contains("PNG"));
    }
}
