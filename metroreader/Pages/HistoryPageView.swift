//
//  HistoryPageView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2026.
//  Edited by Célian Faucille on 10/01/2026

import SwiftUI


struct HistoryPageView: View {
    @ObservedObject var historyManager: HistoryManager
    @AppStorage(HistoryManager.settingKey) private var isHistoryEnabled = false

    // Ligne en cours de déplacement d'une section à l'autre : elle est retirée
    // des deux listes le temps que son retrait s'anime, puis réinsérée à sa
    // nouvelle place. Sans ça SwiftUI retire et insère dans la même passe, et
    // le déplacement inter-sections n'est pas animé.
    @State private var movingRecordID: UUID?

    private static let moveDuration = 0.3

    private var pinned: [ScanRecord] {
        historyManager.pinnedRecords.filter { $0.id != movingRecordID }
    }

    private var unpinned: [ScanRecord] {
        historyManager.unpinnedRecords.filter { $0.id != movingRecordID }
    }

    private func movePin(_ record: ScanRecord) {
        guard movingRecordID == nil else { return }

        // 1. La ligne disparaît, le trou se referme.
        withAnimation(.easeInOut(duration: Self.moveDuration)) {
            movingRecordID = record.id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.moveDuration) {
            // La ligne est masquée : basculer l'épinglage ne se voit pas.
            historyManager.togglePin(for: record)

            // 2. Un trou s'ouvre à la nouvelle place et la ligne le remplit.
            withAnimation(.easeInOut(duration: Self.moveDuration)) {
                movingRecordID = nil
            }
        }
    }

    var body: some View {
        List {
            // Section des épinglés
            if !pinned.isEmpty {
                Section(header: HStack {
                    Image(systemName: "pin.fill")
                    Text("Épinglés")
                }.foregroundColor(.yellow)) {
                    ForEach(pinned) { record in
                        HistoryRowButton(record: record, historyManager: historyManager) {
                            movePin(record)
                        }
                    }
                }
            }

            // Section des récents. Sans épinglés, pas de titre : l'onglet dit
            // déjà « Historique ».
            Section {
                ForEach(unpinned) { record in
                    HistoryRowButton(record: record, historyManager: historyManager) {
                        movePin(record)
                    }
                }
                .onDelete { indexSet in
                    // Les index portent sur la liste affichée, pas sur l'historique
                    let recordsToDelete = indexSet.map { unpinned[$0] }
                    for record in recordsToDelete {
                        if let index = historyManager.history.firstIndex(where: { $0.id == record.id }) {
                            historyManager.deleteItems(at: IndexSet(integer: index))
                        }
                    }
                }
            } header: {
                if !pinned.isEmpty {
                    Text("Récents")
                }
            }
        }
        .overlay {
            // L'historique est éteint d'origine : sans ce mot, la page vide
            // ne dit ni pourquoi elle l'est, ni ce qu'on gagnerait à l'allumer.
            if historyManager.history.isEmpty {
                if isHistoryEnabled {
                    ContentUnavailableView {
                        Label("Aucun scan", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Les cartes que tu scannes ou importes s'enregistreront ici.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("Historique désactivé", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("En activant l'historique, tu gardes la mémoire de tes déplacements passés et tu peux consulter tes anciens scans.")
                    } actions: {
                        Button("Activer l'historique") {
                            withAnimation { isHistoryEnabled = true }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

#Preview {
    HistoryPageView(historyManager: HistoryManager())
}
