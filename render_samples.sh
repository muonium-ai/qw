#!/bin/bash
#
# Render all sample files as PNG and PDF using qw-export
#
# Usage: ./render_samples.sh [--theme THEME] [--format FORMAT]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES_DIR="${SCRIPT_DIR}/samples"
OUTPUT_DIR="${SCRIPT_DIR}/output"
QW_EXPORT="/usr/local/bin/qw-export"

# Defaults
THEME="monokai"
FORMAT="both"  # png, pdf, or both

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--theme)
            THEME="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -t, --theme THEME    Theme: dark, light, monokai, dracula,"
            echo "                       solarized-dark, solarized-light (default: monokai)"
            echo "  -f, --format FORMAT  Format: png, pdf, or both (default: both)"
            echo "  -o, --output DIR     Output directory (default: ./output)"
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check qw-export exists
if [[ ! -x "$QW_EXPORT" ]]; then
    echo "Error: qw-export not found at $QW_EXPORT"
    echo "Build it with: cd qw-export && swiftc -O -o qw-export Sources/qw-export.swift -framework AppKit"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR/$THEME"

echo "Rendering samples with theme: $THEME"
echo "Output directory: $OUTPUT_DIR/$THEME"
echo ""

# Render each sample file
for sample in "$SAMPLES_DIR"/sample.*; do
    if [[ ! -f "$sample" ]]; then
        continue
    fi
    
    filename=$(basename "$sample")
    
    if [[ "$FORMAT" == "png" ]] || [[ "$FORMAT" == "both" ]]; then
        echo "  Exporting $filename -> PNG"
        "$QW_EXPORT" -t "$THEME" -f png "$sample" -o "$OUTPUT_DIR/$THEME/$filename.png"
    fi
    
    if [[ "$FORMAT" == "pdf" ]] || [[ "$FORMAT" == "both" ]]; then
        echo "  Exporting $filename -> PDF"
        "$QW_EXPORT" -t "$THEME" -f pdf "$sample" -o "$OUTPUT_DIR/$THEME/$filename.pdf"
    fi
done

echo ""
echo "Done! Files saved to: $OUTPUT_DIR/$THEME/"
ls -la "$OUTPUT_DIR/$THEME/"
