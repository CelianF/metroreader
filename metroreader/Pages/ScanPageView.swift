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
    /// Une fois par lancement de l'app, pas par apparition de la page : sur le
    /// Duo plié couché, la page se recrée quand la carte s'affiche, et un état
    /// de la vue oubliait le premier scan — il en relançait un, qui vidait la
    /// carte, et ainsi de suite.
    private static var hasAutoLaunched = false
    #endif
    @State private var isImporting = false
    /// Sur le Duo déplié, la fiche se partage : ses validations passent dans
    /// l'autre panneau.
    @Environment(\.ecranDeplie) private var deplie
    #if os(iOS)
    /// La barre du Duo demande l'import d'ici, où vit le sélecteur de fichier.
    @ObservedObject private var actionsDuDuo = ActionsDuDuo.shared
    #endif

    // Tant qu'aucune carte n'est lue en entier, on n'affiche que l'état vide :
    // les boutons de scan, de menu et de partage restent masqués. C'est la
    // lecture achevée qui compte, pas l'en-tête reçu : la cible tient l'écran
    // jusqu'au bout plutôt que de céder la place à un passe encore à moitié vide.
    private var hasCard: Bool { nfcReader.isReadComplete }

    var body: some View {
        Group {
            if hasCard {
                ScanView(cardID: nfcReader.cardID, tagIcc: nfcReader.tagIcc, tagEnvHolder: nfcReader.tagEnvHolder, tagContracts: nfcReader.tagContracts, tagEvents: nfcReader.tagEvents, tagSpecialEvents: nfcReader.tagSpecialEvents, export: nfcReader.export,
                         partie: deplie ? .carte : .tout, historyManager: historyManager)
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
            // Sur le Duo, ces boutons vivent dans sa barre, sous la caméra.
            if !Duo.estUnDuo {
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
                nfcReader.importFile(at: url, historyManager: historyManager)
            case .failure(let error):
                print("Error picking file: \(error.localizedDescription)")
            }
        }
        #if os(iOS)
        .onChange(of: actionsDuDuo.importer) { _, demande in
            guard demande else { return }
            actionsDuDuo.importer = false
            isImporting = true
        }
        .onAppear {
            if autoLaunchScan && !Self.hasAutoLaunched {
                nfcReader.beginScanning(historyManager: historyManager)
                Self.hasAutoLaunched = true
            }
        }
        #endif
    }
}

#Preview {
    ScanPageView(nfcReader: NFCReader(), historyManager: HistoryManager())
}
