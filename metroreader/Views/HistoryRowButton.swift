//
//  HistoryRowButton.swift
//  PassReader
//
//  Created by Célian Faucille on 10/01/2026.
//  Edited by Antoine Souben-Fink on 10/01/2026.
//


import SwiftUI

struct HistoryRowButton: View {
    let record: ScanRecord
    let historyManager: HistoryManager
    // Le déplacement entre sections est séquencé par HistoryPageView
    let onTogglePin: () -> Void
    
    var body: some View {
        // Une vraie page, poussée dans la pile de l'onglet : flèche de retour
        // et geste depuis le bord gauche, comme dans les réglages.
        NavigationLink {
            ScanView(
                cardID: record.cardID,
                tagIcc: record.icc,
                tagEnvHolder: record.envHolder,
                tagContracts: record.contracts,
                tagEvents: record.events,
                tagSpecialEvents: record.specialEvents,
                exportDataAsJSON: record.exportDataAsJSON,
                depuisHistorique: true,
                historyManager: historyManager
            )
        } label: {
            HStack(spacing: 8) {
                NavigoImage(imageName: record.image)
                    .shadow(radius: 2)
                    .frame(height: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(record.displayTitle)")
                            .font(.headline)
                        
                        if record.isPinned {
                            Image(systemName: "pin.circle.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    HStack {
                        if record.cardID != 0 {
                            Text("\(record.cardID)")
                                .font(.caption)
                                .padding(4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                                .foregroundStyle(.secondary)
                        }
                     
                        Spacer()
                        
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onTogglePin) {
                Label(record.isPinned ? "Désépingler" : "Épingler",
                      systemImage: record.isPinned ? "pin.slash" : "pin.fill")
            }
            .tint(record.isPinned ? .gray : .yellow)
        }
    }
}
