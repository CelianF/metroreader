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
    @Binding var selectedRecord: ScanRecord?
    @ObservedObject var historyManager: HistoryManager
    
    var body: some View {
        Button {
            selectedRecord = record
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
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation {
                    historyManager.togglePin(for: record)
                }
            } label: {
                Label(record.isPinned ? "Désépingler" : "Épingler",
                      systemImage: record.isPinned ? "pin.slash" : "pin.fill")
            }
            .tint(record.isPinned ? .gray : .yellow)
        }
    }
}
