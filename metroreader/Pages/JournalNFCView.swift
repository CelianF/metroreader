//
//  JournalNFCView.swift
//  metroreader
//

import SwiftUI

/// Le journal de la dernière lecture NFC, ligne à ligne : l'écart depuis
/// l'ouverture de la session, le sens de l'échange et ce qui s'est dit.
struct JournalNFCView: View {
    @ObservedObject private var journal = JournalNFC.shared
    @State private var copie = false

    var body: some View {
        List {
            if let debut = journal.lignes.first?.instant {
                ForEach(journal.lignes) { ligne in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("+\(JournalNFC.millisecondes(ligne.instant, depuis: debut)) ms  \(JournalNFC.marque(ligne.sorte))")
                            .font(.caption2.monospaced())
                            .foregroundColor(ligne.sorte == .erreur ? .red : .secondary)
                        Text(ligne.texte)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("Aucune lecture NFC depuis le lancement de l'app.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Journal NFC")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !journal.lignes.isEmpty {
                    Button(copie ? "Copié" : "Copier") {
                        copierDansLePressePapiers(journal.texte)
                        copie = true
                    }
                }
            }
        }
    }
}
