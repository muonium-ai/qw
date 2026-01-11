#!/bin/bash
#
# QW Editor CLI Export Test Script
# Tests PDF and PNG export for all sample files and records timing data
#
# Usage: ./test_exports.sh [--pdf-only | --png-only]
#

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SAMPLES_DIR="${SCRIPT_DIR}/samples"
readonly OUTPUT_BASE="${SCRIPT_DIR}/output"
readonly QW_CLI="/usr/local/bin/qw"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Timing data
declare -a TIMING_DATA=()
TOTAL_START_TIME=0
TOTAL_END_TIME=0

# Options
RUN_PDF=true
RUN_PNG=true
THEMES=("dark" "light")

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Get current timestamp in milliseconds
get_timestamp_ms() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: use gdate if available, otherwise perl
        if command -v gdate &> /dev/null; then
            gdate +%s%3N
        else
            perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'
        fi
    else
        date +%s%3N
    fi
}

# Calculate duration in human-readable format
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

# Get file size in human-readable format
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            stat -f%z "$file" | awk '{ 
                if ($1 >= 1048576) printf "%.2f MB", $1/1048576
                else if ($1 >= 1024) printf "%.2f KB", $1/1024
                else printf "%d B", $1
            }'
        else
            stat --printf="%s" "$file" | awk '{ 
                if ($1 >= 1048576) printf "%.2f MB", $1/1048576
                else if ($1 >= 1024) printf "%.2f KB", $1/1024
                else printf "%d B", $1
            }'
        fi
    else
        echo "N/A"
    fi
}

# Count lines in a file
count_lines() {
    local file="$1"
    wc -l < "$file" | tr -d ' '
}

#------------------------------------------------------------------------------
# Pre-flight Checks
#------------------------------------------------------------------------------

check_requirements() {
    log_header "Pre-flight Checks"
    
    # Check for QW CLI
    if [[ ! -x "$QW_CLI" ]]; then
        log_error "QW CLI not found at $QW_CLI"
        log_info "Please install the CLI with: qw --install-cli"
        exit 1
    fi
    log_success "QW CLI found: $QW_CLI"
    
    # Get QW version
    local version
    version=$("$QW_CLI" --version 2>/dev/null || echo "unknown")
    log_info "QW CLI version: $version"
    
    # Check for samples directory
    if [[ ! -d "$SAMPLES_DIR" ]]; then
        log_error "Samples directory not found: $SAMPLES_DIR"
        exit 1
    fi
    log_success "Samples directory found: $SAMPLES_DIR"
    
    # Count sample files
    local sample_count
    sample_count=$(find "$SAMPLES_DIR" -type f -name "sample.*" | wc -l | tr -d ' ')
    log_info "Found $sample_count sample files"
    
    # List sample files
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

export_to_pdf() {
    local input_file="$1"
    local output_file="$2"
    local theme="$3"
    
    local start_time
    start_time=$(get_timestamp_ms)
    
    local result=0
    "$QW_CLI" --pdf --theme "$theme" "$input_file" -o "$output_file" 2>/dev/null || result=$?
    
    local end_time
    end_time=$(get_timestamp_ms)
    local duration=$((end_time - start_time))
    
    if [[ $result -eq 0 ]] && [[ -f "$output_file" ]]; then
        local size
        size=$(get_file_size "$output_file")
        TIMING_DATA+=("pdf,$theme,$(basename "$input_file"),$duration,$size,success")
        return 0
    else
        TIMING_DATA+=("pdf,$theme,$(basename "$input_file"),$duration,0,failed")
        return 1
    fi
}

export_to_png() {
    local input_file="$1"
    local output_file="$2"
    local theme="$3"
    
    local start_time
    start_time=$(get_timestamp_ms)
    
    local result=0
    "$QW_CLI" --png --theme "$theme" "$input_file" -o "$output_file" 2>/dev/null || result=$?
    
    local end_time
    end_time=$(get_timestamp_ms)
    local duration=$((end_time - start_time))
    
    if [[ $result -eq 0 ]] && [[ -f "$output_file" ]]; then
        local size
        size=$(get_file_size "$output_file")
        TIMING_DATA+=("png,$theme,$(basename "$input_file"),$duration,$size,success")
        return 0
    else
        TIMING_DATA+=("png,$theme,$(basename "$input_file"),$duration,0,failed")
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main Export Logic
#------------------------------------------------------------------------------

run_exports() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local output_dir="${OUTPUT_BASE}/${timestamp}"
    
    log_header "Running Export Tests"
    log_info "Output directory: $output_dir"
    
    # Create output directory
    mkdir -p "$output_dir"
    mkdir -p "$output_dir/pdf"
    mkdir -p "$output_dir/png"
    
    TOTAL_START_TIME=$(get_timestamp_ms)
    
    local success_count=0
    local failure_count=0
    
    # Process each sample file
    for sample_file in "$SAMPLES_DIR"/sample.*; do
        if [[ ! -f "$sample_file" ]]; then
            continue
        fi
        
        local filename
        filename=$(basename "$sample_file")
        local basename="${filename%.*}"
        local extension="${filename##*.}"
        
        echo ""
        log_info "Processing: $filename"
        
        for theme in "${THEMES[@]}"; do
            # PDF Export
            if [[ "$RUN_PDF" == "true" ]]; then
                local pdf_output="$output_dir/pdf/${basename}_${theme}.pdf"
                printf "    PDF (%-12s): " "$theme"
                
                if export_to_pdf "$sample_file" "$pdf_output" "$theme"; then
                    local size
                    size=$(get_file_size "$pdf_output")
                    echo -e "${GREEN}✓${NC} $size"
                    ((success_count++))
                else
                    echo -e "${RED}✗${NC} Failed"
                    ((failure_count++))
                fi
            fi
            
            # PNG Export
            if [[ "$RUN_PNG" == "true" ]]; then
                local png_output="$output_dir/png/${basename}_${theme}.png"
                printf "    PNG (%-12s): " "$theme"
                
                if export_to_png "$sample_file" "$png_output" "$theme"; then
                    local size
                    size=$(get_file_size "$png_output")
                    echo -e "${GREEN}✓${NC} $size"
                    ((success_count++))
                else
                    echo -e "${RED}✗${NC} Failed"
                    ((failure_count++))
                fi
            fi
        done
    done
    
    TOTAL_END_TIME=$(get_timestamp_ms)
    local total_duration=$((TOTAL_END_TIME - TOTAL_START_TIME))
    
    # Generate timing report
    generate_timing_report "$output_dir" "$timestamp" "$total_duration" "$success_count" "$failure_count"
    
    # Summary
    log_header "Export Summary"
    log_info "Total exports: $((success_count + failure_count))"
    log_success "Successful: $success_count"
    if [[ $failure_count -gt 0 ]]; then
        log_error "Failed: $failure_count"
    fi
    log_info "Total time: $(format_duration $total_duration)"
    log_info "Output: $output_dir"
    log_info "Timing report: $output_dir/timing_report.txt"
    echo ""
}

#------------------------------------------------------------------------------
# Timing Report Generation
#------------------------------------------------------------------------------

generate_timing_report() {
    local output_dir="$1"
    local timestamp="$2"
    local total_duration="$3"
    local success_count="$4"
    local failure_count="$5"
    
    local report_file="$output_dir/timing_report.txt"
    local csv_file="$output_dir/timing_data.csv"
    
    # Generate text report
    {
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║                    QW EDITOR EXPORT TIMING REPORT                      ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Test Run ID: $timestamp"
        echo ""
        echo "────────────────────────────────────────────────────────────────────────"
        echo "                           SYSTEM INFORMATION"
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
        echo "Hostname:      $(hostname)"
        echo "OS:            $(uname -s) $(uname -r)"
        echo "Architecture:  $(uname -m)"
        echo "QW CLI:        $("$QW_CLI" --version 2>/dev/null || echo 'unknown')"
        echo ""
        echo "────────────────────────────────────────────────────────────────────────"
        echo "                              SUMMARY"
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
        printf "Total Exports:     %d\n" "$((success_count + failure_count))"
        printf "Successful:        %d\n" "$success_count"
        printf "Failed:            %d\n" "$failure_count"
        printf "Success Rate:      %.1f%%\n" "$(echo "scale=1; $success_count * 100 / ($success_count + $failure_count)" | bc)"
        printf "Total Duration:    %s (%d ms)\n" "$(format_duration $total_duration)" "$total_duration"
        echo ""
        echo "────────────────────────────────────────────────────────────────────────"
        echo "                          DETAILED TIMING"
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
        printf "%-8s %-14s %-18s %10s %12s %8s\n" "Format" "Theme" "File" "Time (ms)" "Size" "Status"
        printf "%-8s %-14s %-18s %10s %12s %8s\n" "------" "-----" "----" "---------" "----" "------"
        
        for entry in "${TIMING_DATA[@]}"; do
            IFS=',' read -r format theme file duration size status <<< "$entry"
            printf "%-8s %-14s %-18s %10s %12s %8s\n" "$format" "$theme" "$file" "$duration" "$size" "$status"
        done
        
        echo ""
        echo "────────────────────────────────────────────────────────────────────────"
        echo "                          TIMING BY FORMAT"
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
        
        # Calculate averages by format
        local pdf_total=0 pdf_count=0
        local png_total=0 png_count=0
        
        for entry in "${TIMING_DATA[@]}"; do
            IFS=',' read -r format theme file duration size status <<< "$entry"
            if [[ "$status" == "success" ]]; then
                if [[ "$format" == "pdf" ]]; then
                    pdf_total=$((pdf_total + duration))
                    ((pdf_count++))
                elif [[ "$format" == "png" ]]; then
                    png_total=$((png_total + duration))
                    ((png_count++))
                fi
            fi
        done
        
        if [[ $pdf_count -gt 0 ]]; then
            local pdf_avg=$((pdf_total / pdf_count))
            printf "PDF Average:   %d ms (from %d exports)\n" "$pdf_avg" "$pdf_count"
        fi
        
        if [[ $png_count -gt 0 ]]; then
            local png_avg=$((png_total / png_count))
            printf "PNG Average:   %d ms (from %d exports)\n" "$png_avg" "$png_count"
        fi
        
        echo ""
        echo "────────────────────────────────────────────────────────────────────────"
        echo "                          TIMING BY THEME"
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
        
        # Calculate averages by theme
        for theme in "${THEMES[@]}"; do
            local theme_total=0 theme_count=0
            for entry in "${TIMING_DATA[@]}"; do
                IFS=',' read -r format t file duration size status <<< "$entry"
                if [[ "$t" == "$theme" ]] && [[ "$status" == "success" ]]; then
                    theme_total=$((theme_total + duration))
                    ((theme_count++))
                fi
            done
            if [[ $theme_count -gt 0 ]]; then
                local theme_avg=$((theme_total / theme_count))
                printf "%-12s Average:   %d ms (from %d exports)\n" "$theme" "$theme_avg" "$theme_count"
            fi
        done
        
        echo ""
        echo "────────────────────────────────────────────────────────────────────────"
        echo "                         SAMPLE FILE DETAILS"
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
        printf "%-18s %8s %12s\n" "File" "Lines" "Size"
        printf "%-18s %8s %12s\n" "----" "-----" "----"
        
        for sample_file in "$SAMPLES_DIR"/sample.*; do
            if [[ -f "$sample_file" ]]; then
                local filename
                filename=$(basename "$sample_file")
                local lines
                lines=$(count_lines "$sample_file")
                local size
                size=$(get_file_size "$sample_file")
                printf "%-18s %8s %12s\n" "$filename" "$lines" "$size"
            fi
        done
        
        echo ""
        echo "════════════════════════════════════════════════════════════════════════"
        echo "                            END OF REPORT"
        echo "════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "This report can be used for:"
        echo "  • Performance benchmarking across versions"
        echo "  • Identifying slow exports by file type"
        echo "  • Comparing theme rendering performance"
        echo "  • Tracking regression in export functionality"
        echo ""
        echo "For CSV data suitable for analysis: $csv_file"
        echo ""
        
    } > "$report_file"
    
    # Generate CSV for programmatic analysis
    {
        echo "timestamp,format,theme,file,duration_ms,size,status"
        for entry in "${TIMING_DATA[@]}"; do
            echo "$timestamp,$entry"
        done
    } > "$csv_file"
    
    log_info "Timing report saved to: $report_file"
    log_info "CSV data saved to: $csv_file"
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pdf-only)
                RUN_PDF=true
                RUN_PNG=false
                shift
                ;;
            --png-only)
                RUN_PDF=false
                RUN_PNG=true
                shift
                ;;
            --help|-h)
                echo "QW Editor CLI Export Test Script"
                echo ""
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --pdf-only    Only run PDF exports"
                echo "  --png-only    Only run PNG exports"
                echo "  --help, -h    Show this help message"
                echo ""
                echo "This script tests the QW Editor CLI export functionality"
                echo "on all sample files and records timing data for benchmarking."
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    parse_args "$@"
    
    log_header "QW Editor CLI Export Test"
    log_info "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    
    check_requirements
    run_exports
    
    log_info "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Run main function
main "$@"
