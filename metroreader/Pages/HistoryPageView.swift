//
//  HistoryPageView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2026.
//  Edited by Célian Faucille on 10/01/2026

import SwiftUI


struct HistoryPageView: View {
    @ObservedObject var historyManager: HistoryManager
    @State private var selectedRecord: ScanRecord?
    
    var body: some View {
        List {
            // Section des épinglés
            if !historyManager.pinnedRecords.isEmpty {
                Section(header: HStack {
                    Image(systemName: "pin.fill")
                    Text("Épinglés")
                }.foregroundColor(.yellow)) {
                    ForEach(historyManager.pinnedRecords) { record in
                        HistoryRowButton(record: record, selectedRecord: $selectedRecord, historyManager: historyManager)
                    }
                }
            }
            
            // Section des récents
            Section(header: Text(historyManager.pinnedRecords.isEmpty ? "Historique" : "Récents")) {
                ForEach(historyManager.unpinnedRecords) { record in
                    HistoryRowButton(record: record, selectedRecord: $selectedRecord, historyManager: historyManager)
                }
                .onDelete { indexSet in
                    // Adapter la suppression pour les unpinnedRecords
                    let recordsToDelete = indexSet.map { historyManager.unpinnedRecords[$0] }
                    for record in recordsToDelete {
                        if let index = historyManager.history.firstIndex(where: { $0.id == record.id }) {
                            historyManager.deleteItems(at: IndexSet(integer: index))
                        }
                    }
                }
            }
        }
        .navigationTitle("Historique")
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                ScanView(
                    cardID: record.cardID,
                    tagIcc: record.icc,
                    tagEnvHolder: record.envHolder,
                    tagContracts: record.contracts,
                    tagEvents: record.events,
                    tagSpecialEvents: record.specialEvents,
                    exportDataAsJSON: record.exportDataAsJSON,
                    historyManager: historyManager
                )
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer") { selectedRecord = nil }
                    }
                    #else
                    ToolbarItem {
                        Button("Fermer") { selectedRecord = nil }
                    }
                    #endif
                }
            }
        }
    }
}

#Preview {
    HistoryPageView(historyManager: HistoryManager())
}
