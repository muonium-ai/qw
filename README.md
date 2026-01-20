# QW

QW is a lightweight, multi-tab native text editor (SwiftUI + AppKit/TextKit 2) with syntax highlighting and export (PDF/PNG) support.

This repo contains:
- The Xcode app project: `qw/qw.xcodeproj` (scheme: `qw`)
- A small shell CLI wrapper: `cli/qw` (installed as `/usr/local/bin/qw`)
- A native export tool: `qw-export/` (Swift package producing the `qw-export` executable)

## Requirements

- macOS
- Xcode (for `xcodebuild`)
- Swift toolchain (comes with Xcode)

Optional (nice-to-have):
- `xcbeautify` for prettier `xcodebuild` output
- Homebrew (to install optional tools)

## Quick start

Show available make targets:

```bash
make help
```

Build and run the macOS app:

```bash
make run
```

Run unit tests:

```bash
make test
```

Clean build artifacts:

```bash
make clean
```

## Build (Makefile)

The Makefile is the preferred workflow for local development.

- Build macOS (Release):

```bash
make build-mac
```

- Build all (macOS + iOS simulator):

```bash
make build-all
```

- Run the macOS app (alias for deploy-mac):

```bash
make run
```

- Deploy to iPad Simulator (alias: `deploy-ios`):

```bash
make deploy-ipad
```

You can also use the legacy alias:

```bash
make deploy-ios
```

Note: The app is currently configured as **iPad-only** (iPhone is ineligible by design).

## Build (xcodebuild directly)

List targets/schemes:

```bash
xcodebuild -list -project qw/qw.xcodeproj
```

Build macOS:

```bash
xcodebuild build -project qw/qw.xcodeproj -scheme qw -destination "platform=macOS" -configuration Release
```

Run tests:

```bash
xcodebuild test -project qw/qw.xcodeproj -scheme qw -destination "platform=macOS"
```

## Install / Uninstall

Install the app to `/Applications` and install the `qw` CLI to `/usr/local/bin/qw`:

```bash
make install
```

Install only the CLI:

```bash
make install-cli
```

Uninstall both:

```bash
make uninstall
```

## CLI usage (`qw`)

After `make install-cli` (or `make install`), you can:

- Open the app:

```bash
qw
```

- Open a file or folder:

```bash
qw file.txt
qw .
```

- Open a file in read-only mode:

```bash
qw -r file.txt
qw --readonly config.json
```

- Export a file (CLI fallback exporters):

```bash
qw --pdf path/to/file.py
qw --png path/to/file.js -o out.png
```

Notes:
- The CLI’s `--pdf/--png` implementation uses best-effort exporters (e.g. `enscript`/`ghostscript`/`pygmentize` when available, otherwise macOS `cupsfilter`/`sips`).
- For “exactly like the app” screenshot-style exports, use `qw-export` (next section).

## Native export tool (`qw-export`)

`qw-export` is a Swift command-line tool that renders syntax-highlighted output using AppKit.

Build it via SwiftPM:

```bash
cd qw-export
swift build -c release
```

The binary will be at:

```bash
./.build/release/qw-export
```

If you want the helper scripts to find it at `/usr/local/bin/qw-export`, copy it there:

```bash
sudo cp ./.build/release/qw-export /usr/local/bin/qw-export
sudo chmod +x /usr/local/bin/qw-export
```

Example usage:

```bash
qw-export -f png -t monokai samples/sample.swift -o /tmp/sample.swift.png
qw-export -f pdf -t dracula samples/sample.py -o /tmp/sample.py.pdf
```

## Export test scripts

There are two export test paths:

1) Test exports via the `qw` CLI wrapper:

```bash
./test_exports.sh
# or:
./test_exports.sh --pdf-only
./test_exports.sh --png-only
```

2) Test exports via the native `qw-export` tool:

```bash
./test_native_exports.sh
# or:
./test_native_exports.sh --pdf-only
./test_native_exports.sh --png-only
```

Render all samples with a chosen theme/format (native exporter):

```bash
./render_samples.sh --theme monokai --format both
./render_samples.sh --theme dracula --format png
```

Verify exported PDFs/PNGs:

```bash
./scripts/verify-export.sh output/**/*.pdf output/**/*.png
```

## Project notes

- Product/agent notes live in:
  - `requirements/QW_PRD.md`
  - `requirements/agents.md`

## Vendored dependency: `pygments-swift`

The syntax highlighting engine is developed in a separate repo and is included here as a **git submodule** at `vendor/pygments-swift`.

Clone this repo with submodules:

```bash
git clone --recurse-submodules git@github.com:muonium-ai/qw.git
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

Update the submodule to the latest upstream commit (then commit the pointer in this repo):

```bash
git submodule update --remote --merge vendor/pygments-swift
git add vendor/pygments-swift
git commit -m "Update pygments-swift submodule"
git push
```

---

If you want, I can also add a short “Contributing” section (coding style, where features live, and how exports/syntax highlighting are wired) after a quick pass over the Swift modules.