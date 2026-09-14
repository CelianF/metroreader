//
//  DebugValidation.swift
//  metroreader
//

import SwiftUI

/// Ce que le mode debug ajoute à la fiche d'une validation : de quoi comprendre
/// ce que l'app a tiré de ce que la carte écrit.
struct DebugDeLaValidation: View {
    let eventInfo: [String: Any]
    let event: ResolvedEvent
    let regle: RegleDeTransition

    var body: some View {
        Section {
            ligne("Écrite par le valideur", LectureValidation(eventInfo, contrats: []).brute)
            ligne("Racontée", event.transition)
            ligne("Règle", regle.explication)
        } header: {
            Text("Debug · transition")
        }
    }

    /// Un intitulé, et ce qu'on en sait, qui peut tenir sur plusieurs lignes.
    private func ligne(_ titre: String, _ valeur: String) -> some View {
        LabeledContent(titre) {
            Text(valeur)
                .multilineTextAlignment(.trailing)
        }
    }
}
