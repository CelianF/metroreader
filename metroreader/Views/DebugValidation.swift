//
//  DebugValidation.swift
//  metroreader
//

import SwiftUI
import CoreLocation

/// Ce que le mode debug ajoute à la fiche d'une validation : de quoi comprendre
/// ce que l'app a tiré de ce que la carte écrit.
struct DebugDeLaValidation: View {
    let eventInfo: [String: Any]
    let event: ResolvedEvent
    let regle: RegleDeTransition

    @ObservedObject private var gps = LocationProvider.shared
    @AppStorage(LocationProvider.settingKey) private var locateOnScan = false

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

        Section {
            ligne("Relever au scan", locateOnScan ? "Allumé" : "Éteint")
            position
        } header: {
            Text("Debug · position du scan")
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

    // MARK: - Position du scan

    private static let heure: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = intercodeTimeZone
        formatter.dateFormat = "dd/MM HH:mm:ss"
        return formatter
    }()

    /// Le dernier relevé de l'app, et ce qu'il vaut pour cette validation : il
    /// n'éclaire l'arrêt que pris dans la fenêtre de fraîcheur autour d'elle.
    @ViewBuilder
    private var position: some View {
        switch gps.state {
        case .idle:
            ligne("Relevé", "Aucun depuis le lancement")
        case .requesting:
            ligne("Relevé", "En cours")
        case .denied:
            ligne("Relevé", "Refusé par iOS")
        case .failed:
            ligne("Relevé", "Échec")
        case .located(let point, let precision):
            ligne("Relevé", "\(String(format: "%.5f, %.5f", point.latitude, point.longitude)) ± \(precision.courte)")
            if let mesure = gps.capturedAt {
                ligne("Mesuré le", Self.heure.string(from: mesure))
            }
            if let ecart = gps.gap(from: ResolvedEvent.instant(eventInfo)) {
                ligne("Écart avec la validation", Self.duree(ecart))
                ligne("Utilisable", ecart < LocationProvider.freshnessWindow
                      ? "Oui"
                      : "Non : plus de \(Int(LocationProvider.freshnessWindow)) s d'écart")
            }
        }
    }

    private static func duree(_ secondes: TimeInterval) -> String {
        let s = Int(secondes.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        if s < 86400 { return "\(s / 3600) h \((s % 3600) / 60) min" }
        return "\(s / 86400) j \((s % 86400) / 3600) h"
    }

    /// Un intitulé, et ce qu'on en sait, qui peut tenir sur plusieurs lignes.
    private func ligne(_ titre: String, _ valeur: String) -> some View {
        LabeledContent(titre) {
            Text(valeur)
                .multilineTextAlignment(.trailing)
        }
    }
}
