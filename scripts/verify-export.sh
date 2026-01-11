#!/bin/bash
#
# verify-export.sh - Verify exported PDF and PNG files from QW Editor
#
# Usage:
#   ./verify-export.sh <file>           # Verify a single file
#   ./verify-export.sh <file1> <file2>  # Verify multiple files
#   ./verify-export.sh *.pdf *.png      # Verify all PDFs and PNGs in current dir
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  QW Editor Export File Verifier${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}  $1${NC}"
}

verify_pdf() {
    local file="$1"
    echo -e "\n${BLUE}Verifying PDF: ${NC}$file"
    echo "----------------------------------------"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        print_error "File does not exist"
        ((FAILED++))
        return 1
    fi
    
    # Check file size
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [[ "$size" -eq 0 ]]; then
        print_error "File is empty (0 bytes)"
        ((FAILED++))
        return 1
    fi
    print_success "File size: $size bytes"
    
    # Use 'file' command to check file type
    local file_type=$(file -b "$file")
    echo -e "  File type: $file_type"
    
    if [[ "$file_type" == *"PDF"* ]]; then
        print_success "File is a valid PDF"
    else
        print_error "File is NOT a PDF"
        ((FAILED++))
        return 1
    fi
    
    # Check PDF magic bytes
    local magic=$(head -c 4 "$file")
    if [[ "$magic" == "%PDF" ]]; then
        print_success "PDF magic bytes verified (%PDF)"
    else
        print_error "Invalid PDF magic bytes"
        ((FAILED++))
        return 1
    fi
    
    # Use pdfinfo if available
    if command -v pdfinfo &> /dev/null; then
        echo -e "\n  ${YELLOW}PDF Info:${NC}"
        pdfinfo "$file" 2>/dev/null | while read line; do
            echo "    $line"
        done
        
        # Check page count
        local pages=$(pdfinfo "$file" 2>/dev/null | grep "Pages:" | awk '{print $2}')
        if [[ -n "$pages" && "$pages" -gt 0 ]]; then
            print_success "PDF has $pages page(s)"
        else
            print_error "Could not determine page count"
        fi
    else
        print_info "pdfinfo not installed (install with: brew install poppler)"
    fi
    
    ((PASSED++))
    return 0
}

verify_png() {
    local file="$1"
    echo -e "\n${BLUE}Verifying PNG: ${NC}$file"
    echo "----------------------------------------"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        print_error "File does not exist"
        ((FAILED++))
        return 1
    fi
    
    # Check file size
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [[ "$size" -eq 0 ]]; then
        print_error "File is empty (0 bytes)"
        ((FAILED++))
        return 1
    fi
    print_success "File size: $size bytes"
    
    # Use 'file' command to check file type
    local file_type=$(file -b "$file")
    echo -e "  File type: $file_type"
    
    if [[ "$file_type" == *"PNG"* ]]; then
        print_success "File is a valid PNG"
    else
        print_error "File is NOT a PNG"
        ((FAILED++))
        return 1
    fi
    
    # Check PNG magic bytes (89 50 4E 47 = .PNG)
    local magic=$(xxd -p -l 4 "$file")
    if [[ "$magic" == "89504e47" ]]; then
        print_success "PNG magic bytes verified (89 50 4E 47)"
    else
        print_error "Invalid PNG magic bytes: $magic"
        ((FAILED++))
        return 1
    fi
    
    # Use sips to get image info (built into macOS)
    if command -v sips &> /dev/null; then
        echo -e "\n  ${YELLOW}Image Info:${NC}"
        local width=$(sips -g pixelWidth "$file" 2>/dev/null | tail -1 | awk '{print $2}')
        local height=$(sips -g pixelHeight "$file" 2>/dev/null | tail -1 | awk '{print $2}')
        local format=$(sips -g format "$file" 2>/dev/null | tail -1 | awk '{print $2}')
        
        echo "    Width: ${width}px"
        echo "    Height: ${height}px"
        echo "    Format: $format"
        
        if [[ -n "$width" && "$width" -gt 0 && -n "$height" && "$height" -gt 0 ]]; then
            print_success "Image dimensions: ${width}x${height}"
        else
            print_error "Could not determine image dimensions"
        fi
    fi
    
    ((PASSED++))
    return 0
}

verify_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    case "$ext" in
        pdf)
            verify_pdf "$file"
            ;;
        png)
            verify_png "$file"
            ;;
        *)
            echo -e "\n${YELLOW}Skipping: ${NC}$file (unknown extension: .$ext)"
            echo "  Supported formats: .pdf, .png"
            ;;
    esac
}

print_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "  ${GREEN}Passed: $PASSED${NC}"
    echo -e "  ${RED}Failed: $FAILED${NC}"
    echo ""
    
    if [[ "$FAILED" -eq 0 ]]; then
        echo -e "${GREEN}All files verified successfully!${NC}"
        return 0
    else
        echo -e "${RED}Some files failed verification.${NC}"
        return 1
    fi
}

# Main
print_header

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <file> [file2] [file3] ..."
    echo ""
    echo "Examples:"
    echo "  $0 document.pdf"
    echo "  $0 *.pdf *.png"
    echo "  $0 ~/Documents/export.pdf ~/Documents/export.png"
    echo ""
    echo "Supported formats: PDF, PNG"
    exit 1
fi

for file in "$@"; do
    verify_file "$file"
done

print_summary
