//
//  qw-export-main.swift
//  qw-export
//
//  Main entry point for the qw-export command-line tool
//  This tool renders source code files as PNG/PDF with syntax highlighting
//  exactly as they appear in the QW Editor
//

import Foundation

#if os(macOS)
import AppKit

// Ensure we have a run loop for AppKit operations
let app = NSApplication.shared

// Process command line arguments
let exitCode = ExportCLI.main(arguments: CommandLine.arguments)
exit(exitCode)

#else
fputs("Error: qw-export is only available on macOS\n", stderr)
exit(1)
#endif
