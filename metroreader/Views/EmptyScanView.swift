//
//  EmptyScanView.swift
//  metroreader
//

import SwiftUI

struct EmptyScanView: View {
    var isScanning: Bool = false
    let onScan: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Aucun Navigo scanné")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Liquid Glass à partir d'iOS 26, style plein en dessous
            Group {
                if #available(iOS 26.0, macOS 26.0, *) {
                    actionButton.buttonStyle(.glassProminent)
                } else {
                    actionButton.buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .tint(.blue)
            .disabled(isScanning)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionButton: some View {
        #if os(iOS)
        Button(action: onScan) {
            Text(isScanning ? "Scan en cours…" : "Scanner une carte")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        #else
        // Pas de NFC sur macOS : l'import reste la seule entrée
        Button(action: onImport) {
            Text("Importer un fichier")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        #endif
    }
}

#Preview {
    EmptyScanView(onScan: {}, onImport: {})
}

#Preview("Scan en cours") {
    EmptyScanView(isScanning: true, onScan: {}, onImport: {})
}
