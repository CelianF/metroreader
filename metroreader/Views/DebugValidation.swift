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

        Section {
            ligne("Arrêt", origineDeLArret)
            ligne("Ligne", origineDeLaLigne)
            ligne("Réseau", provenanceReseau(event.providerId))
            ligne("Recherché avec", cleDeRecherche)
        } header: {
            Text("Debug · origine des noms")
        }
    }

    // MARK: - Origine des noms

    /// L'exploitant et le lieu, tels que `ResolvedEvent` les lit : le refus
    /// abrégé d'une porte SNCF relevée prend ceux de la porte.
    private var exploitantEtLieu: (exploitant: String, lieu: String) {
        let porte = GateCorrections.porteDuRefus(eventInfo)
        return (porte.map { String($0.provider_id, radix: 2) } ?? getKey(eventInfo, "EventServiceProvider") ?? "",
                porte.map { String($0.location_id, radix: 2) } ?? getKey(eventInfo, "EventLocationId") ?? "")
    }

    private var origineDeLArret: String {
        let (exploitant, lieu) = exploitantEtLieu
        var origine = provenanceArret(lieu, getKey(eventInfo, "EventCode") ?? "", exploitant,
                                      getKey(eventInfo, "EventRouteNumber"))
        if GateCorrections.porteDuRefus(eventInfo) != nil {
            origine = "Porte relevée d'un refus SNCF · " + origine
        }
        if event.isStopIgnored {
            origine += " · ignoré pour ce trajet"
        }
        return origine
    }

    private var origineDeLaLigne: String {
        guard let course = getKey(eventInfo, "EventRouteNumber") else {
            // Sans course, un train prend le nom de la seule ligne de sa gare.
            return event.routeName == nil
                ? "Pas de numéro de course"
                : "Pas de numéro de course : celle de la gare, qui n'en a qu'une"
        }
        return provenanceLigne(course, getKey(eventInfo, "EventCode") ?? "", exploitantEtLieu.exploitant)
    }

    private var cleDeRecherche: String {
        var morceaux = ["exploitant \(event.providerId)"]
        if let lieu = event.locationId { morceaux.append("lieu \(lieu)") }
        if let course = event.routeNumber { morceaux.append("course \(course)") }
        morceaux.append("mode \(event.lookupMode)")
        return morceaux.joined(separator: " · ")
    }

    /// Un intitulé, et ce qu'on en sait, qui peut tenir sur plusieurs lignes.
    private func ligne(_ titre: String, _ valeur: String) -> some View {
        LabeledContent(titre) {
            Text(valeur)
                .multilineTextAlignment(.trailing)
        }
    }
}
