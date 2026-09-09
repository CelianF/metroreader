//
//  ScanPageView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//


import SwiftUI

struct ScanPageView: View {
    @ObservedObject var nfcReader: NFCReader
    @ObservedObject var historyManager: HistoryManager
    #if os(iOS)
    @AppStorage("autoLaunchScan") private var autoLaunchScan = false
    @State private var hasAutoLaunched = false
    #endif
    @State private var isImporting = false

    // Tant qu'aucune carte n'est lue en entier, on n'affiche que l'état vide :
    // les boutons de scan, de menu et de partage restent masqués. C'est la
    // lecture achevée qui compte, pas l'en-tête reçu : la cible tient l'écran
    // jusqu'au bout plutôt que de céder la place à un passe encore à moitié vide.
    private var hasCard: Bool { nfcReader.isReadComplete }

    var body: some View {
        Group {
            if hasCard {
                ScanView(cardID: nfcReader.cardID, tagIcc: nfcReader.tagIcc, tagEnvHolder: nfcReader.tagEnvHolder, tagContracts: nfcReader.tagContracts, tagEvents: nfcReader.tagEvents, tagSpecialEvents: nfcReader.tagSpecialEvents, exportDataAsJSON: nfcReader.exportDataAsJSON, historyManager: historyManager)
            } else {
                EmptyScanView(
                    isScanning: nfcReader.isScanning,
                    isTagDetected: nfcReader.isTagDetected,
                    onScan: { nfcReader.beginScanning(historyManager: historyManager) },
                    onImport: { isImporting = true }
                )
            }
        }
        .navigationTitle("")
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarLeading) {
                // Sans carte, l'écran vide porte déjà son propre bouton d'import
                if hasCard {
                    Button(action: { isImporting = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }

                    Button(action: {
                        nfcReader.beginScanning(historyManager: historyManager)
                    }) {
                        Image(systemName: "wave.3.forward")
                    }
                }
            }
            #else
            ToolbarItemGroup {
                Button(action: { isImporting = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            #endif
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.metropass],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                
                // Security: Gain access to the file
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        nfcReader.importJSON(from: data, historyManager: historyManager)
                    }
                }
            case .failure(let error):
                print("Error picking file: \(error.localizedDescription)")
            }
        }
        #if os(iOS)
        .onAppear {
            if autoLaunchScan && !hasAutoLaunched {
                nfcReader.beginScanning(historyManager: historyManager)
                hasAutoLaunched = true
            }
        }
        #endif
    }
}

#Preview {
    ScanPageView(nfcReader: NFCReader(), historyManager: HistoryManager())
}
