#!/bin/bash
#
# QW Editor Native Export Test Script
# Uses the native qw-export tool for true screenshot-like exports
#
# Usage: ./test_native_exports.sh [--pdf-only | --png-only]
#

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SAMPLES_DIR="${SCRIPT_DIR}/samples"
readonly OUTPUT_BASE="${SCRIPT_DIR}/output"
readonly QW_EXPORT="/usr/local/bin/qw-export"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Timing data
declare -a TIMING_DATA=()

# Themes available in qw-export
THEMES=("dark" "light" "monokai" "dracula" "solarized-dark" "solarized-light")

# Options
RUN_PDF=true
RUN_PNG=true

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

log_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

get_timestamp_ms() {
    if command -v gdate &> /dev/null; then
        gdate +%s%3N
    else
        perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'
    fi
}

format_duration() {
    local ms=$1
    local seconds=$((ms / 1000))
    local milliseconds=$((ms % 1000))
    
    if [[ $seconds -ge 60 ]]; then
        local minutes=$((seconds / 60))
        seconds=$((seconds % 60))
        printf "%dm %d.%03ds" "$minutes" "$seconds" "$milliseconds"
    else
        printf "%d.%03ds" "$seconds" "$milliseconds"
    fi
}

get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f%z "$file" | awk '{ 
            if ($1 >= 1048576) printf "%.2f MB", $1/1048576
            else if ($1 >= 1024) printf "%.2f KB", $1/1024
            else printf "%d B", $1
        }'
    else
        echo "N/A"
    fi
}

count_lines() {
    local file="$1"
    wc -l < "$file" | tr -d ' '
}

#------------------------------------------------------------------------------
# Pre-flight Checks
#------------------------------------------------------------------------------

check_requirements() {
    log_header "Pre-flight Checks"
    
    if [[ ! -x "$QW_EXPORT" ]]; then
        log_error "qw-export not found at $QW_EXPORT"
        log_info "Build it with: cd qw-export && swiftc -O -o qw-export Sources/qw-export.swift -framework AppKit"
        exit 1
    fi
    log_success "qw-export found: $QW_EXPORT"
    
    if [[ ! -d "$SAMPLES_DIR" ]]; then
        log_error "Samples directory not found: $SAMPLES_DIR"
        exit 1
    fi
    log_success "Samples directory found: $SAMPLES_DIR"
    
    local sample_count
    sample_count=$(find "$SAMPLES_DIR" -type f -name "sample.*" | wc -l | tr -d ' ')
    log_info "Found $sample_count sample files"
    log_info "Available themes: ${THEMES[*]}"
    
    echo ""
    log_info "Sample files:"
    for file in "$SAMPLES_DIR"/sample.*; do
        if [[ -f "$file" ]]; then
            local basename
            basename=$(basename "$file")
            local lines
            lines=$(count_lines "$file")
            local size
            size=$(get_file_size "$file")
            printf "    %-20s %6s lines  %10s\n" "$basename" "$lines" "$size"
        fi
    done
    echo ""
}

#------------------------------------------------------------------------------
# Export Functions
#------------------------------------------------------------------------------

export_to_format() {
    local input_file="$1"
    local output_file="$2"
    local theme="$3"
    local format="$4"
    
    local start_time
    start_time=$(get_timestamp_ms)
    
    local result=0
    "$QW_EXPORT" -f "$format" -t "$theme" "$input_file" -o "$output_file" 2>/dev/null || result=$?
    
    local end_time
    end_time=$(get_timestamp_ms)
    local duration=$((end_time - start_time))
    
    if [[ $result -eq 0 ]] && [[ -f "$output_file" ]]; then
        local size
        size=$(get_file_size "$output_file")
        TIMING_DATA+=("$format,$theme,$(basename "$input_file"),$duration,$size,success")
        return 0
    else
        TIMING_DATA+=("$format,$theme,$(basename "$input_file"),$duration,0,failed")
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main Testing
#------------------------------------------------------------------------------

run_tests() {
    log_header "Running Native Export Tests"
    
    mkdir -p "$OUTPUT_BASE"
    
    local total_exports=0
    local successful_exports=0
    local failed_exports=0
    
    local total_start
    total_start=$(get_timestamp_ms)
    
    # Test all themes with all sample files
    for theme in "${THEMES[@]}"; do
        local theme_dir="${OUTPUT_BASE}/${theme}"
        mkdir -p "$theme_dir"
        
        log_info "Testing theme: ${CYAN}$theme${NC}"
        
        for sample in "$SAMPLES_DIR"/sample.*; do
            if [[ ! -f "$sample" ]]; then
                continue
            fi
            
            local filename
            filename=$(basename "$sample")
            local ext="${filename##*.}"
            
            # PNG export
            if $RUN_PNG; then
                local png_output="${theme_dir}/${filename}.png"
                ((total_exports++))
                
                if export_to_format "$sample" "$png_output" "$theme" "png"; then
                    ((successful_exports++))
                    printf "    ${GREEN}✓${NC} PNG %-12s -> %s\n" "$ext" "$(get_file_size "$png_output")"
                else
                    ((failed_exports++))
                    printf "    ${RED}✗${NC} PNG %-12s FAILED\n" "$ext"
                fi
            fi
            
            # PDF export
            if $RUN_PDF; then
                local pdf_output="${theme_dir}/${filename}.pdf"
                ((total_exports++))
                
                if export_to_format "$sample" "$pdf_output" "$theme" "pdf"; then
                    ((successful_exports++))
                    printf "    ${GREEN}✓${NC} PDF %-12s -> %s\n" "$ext" "$(get_file_size "$pdf_output")"
                else
                    ((failed_exports++))
                    printf "    ${RED}✗${NC} PDF %-12s FAILED\n" "$ext"
                fi
            fi
        done
        echo ""
    done
    
    local total_end
    total_end=$(get_timestamp_ms)
    local total_duration=$((total_end - total_start))
    
    # Summary
    log_header "Test Results Summary"
    
    echo -e "Total exports:      ${CYAN}$total_exports${NC}"
    echo -e "Successful:         ${GREEN}$successful_exports${NC}"
    echo -e "Failed:             ${RED}$failed_exports${NC}"
    echo -e "Total time:         ${YELLOW}$(format_duration $total_duration)${NC}"
    
    if [[ $total_exports -gt 0 ]]; then
        local avg=$((total_duration / total_exports))
        echo -e "Average per export: ${YELLOW}$(format_duration $avg)${NC}"
    fi
    echo ""
    
    # Output directory size
    local output_size
    output_size=$(du -sh "$OUTPUT_BASE" 2>/dev/null | cut -f1)
    echo -e "Output directory:   ${CYAN}$output_size${NC} in $OUTPUT_BASE"
    echo ""
    
    # Show timing breakdown by format
    log_header "Timing Breakdown"
    
    echo "Format  Theme           File            Time        Size        Status"
    echo "------  --------------  --------------  ----------  ----------  ------"
    for data in "${TIMING_DATA[@]}"; do
        IFS=',' read -r fmt theme file duration size status <<< "$data"
        printf "%-6s  %-14s  %-14s  %10s  %10s  %s\n" \
            "$fmt" "$theme" "$file" "$(format_duration "$duration")" "$size" "$status"
    done
    echo ""
    
    if [[ $failed_exports -gt 0 ]]; then
        return 1
    fi
    return 0
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pdf-only)
                RUN_PNG=false
                shift
                ;;
            --png-only)
                RUN_PDF=false
                shift
                ;;
            --theme)
                shift
                THEMES=("$1")
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--pdf-only | --png-only] [--theme THEME]"
                echo ""
                echo "Options:"
                echo "  --pdf-only    Only run PDF exports"
                echo "  --png-only    Only run PNG exports"
                echo "  --theme NAME  Only test specific theme"
                echo ""
                echo "Available themes: dark, light, monokai, dracula, solarized-dark, solarized-light"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    log_header "QW Editor Native Export Test"
    echo -e "Using ${CYAN}qw-export${NC} for native screenshot-like rendering"
    echo -e "Features: Syntax highlighting, themed backgrounds, line numbers"
    echo ""
    
    check_requirements
    run_tests
}

main "$@"
