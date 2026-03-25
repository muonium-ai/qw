# QW Hex Viewer — Web UI

Browser-based hex viewer powered by WebAssembly.

## Prerequisites

- Rust toolchain with `wasm-pack` installed
- Python 3 (for local dev server) or any static HTTP server

## Build the WASM module

```bash
cd qw-wasm
wasm-pack build --target web
```

This produces the `pkg/` directory with `qw_wasm.js` and `qw_wasm_bg.wasm`.

## Serve locally

```bash
cd qw-wasm/www
python3 -m http.server 8080
```

Then open http://localhost:8080 in your browser.

## Usage

1. **Open a file**: Drag and drop any file onto the viewer, or click the "Browse" button.
2. **Navigate**: Click any byte in the hex grid to select it. Use arrow keys to move the cursor. Page Up/Down to jump by 20 rows.
3. **Inspect data**: The right panel shows decoded values (integers, floats, ASCII, binary) at the selected offset. Toggle between Little Endian and Big Endian with the LE/BE buttons.
4. **AI Explain**: Click "Explain with AI" in the toolbar to send the file header to Claude for structural analysis. You will be prompted for an Anthropic API key on first use (stored in localStorage).

## Notes

- The app works without the WASM module by falling back to JavaScript implementations of the core functions. Build the WASM module for better performance on large files.
- Virtual scrolling is used so files of any size can be viewed without lag.
- The app runs entirely client-side; files are never uploaded to a server.
