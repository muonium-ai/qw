//
//  WasmExecutionView.swift
//  qw
//
//  Bridges ExecutableRunnerView with WasmRunner for WebAssembly execution.
//  Ticket: T-000056
//

import SwiftUI

#if os(macOS)

/// A view that checks for WASM runtime availability and presents
/// either an ExecutableRunnerView (if a runtime is installed) or
/// an error message with install hints.
struct WasmExecutionView: View {
    let fileURL: URL
    let rawData: Data
    var onSwitchToHex: (() -> Void)?

    var body: some View {
        let availability = WasmRunner.isAvailable()
        let formatName = MagicBytes.detect(from: rawData)?.name ?? "WebAssembly Binary"

        if availability.available {
            ExecutableRunnerView(
                fileURL: fileURL,
                formatName: formatName,
                sandboxSummary: WasmRunner.sandboxSummary(),
                onSwitchToHex: onSwitchToHex,
                onExecute: { executor in
                    await WasmRunner.run(
                        fileURL: fileURL,
                        config: .wasmDefault,
                        executor: executor
                    )
                }
            )
        } else {
            runtimeNotFoundView(installHint: availability.installHint)
        }
    }

    @ViewBuilder
    private func runtimeNotFoundView(installHint: String?) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("WebAssembly Runtime Not Found")
                .font(.title2)
                .fontWeight(.semibold)

            Text("A WebAssembly runtime (wasmtime or wasmer) is required to run .wasm files.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if let hint = installHint {
                GroupBox {
                    Text(hint)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 400)
            }

            HStack(spacing: 12) {
                if let onSwitchToHex {
                    Button("View as Hex") {
                        onSwitchToHex()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#endif
