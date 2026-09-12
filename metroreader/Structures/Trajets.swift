//
//  Trajets.swift
//  metroreader
//

import Foundation


/// Un trajet : l'entrée qui l'ouvre et ce qui la suit.
struct Trajet: Identifiable {
    /// Les positions des validations dans la liste de la carte, de la plus
    /// récente à la plus ancienne.
    let indices: [Int]
    var id: Int { indices.first ?? -1 }
}

/// Les trajets d'un même jour, du plus récent au plus ancien.
struct JourneeDeTrajets: Identifiable {
    let jour: Date
    let trajets: [Trajet]
    var id: Date { jour }
}

/// Au-delà, une validation qui n'ouvre pas de trajet n'en prolonge plus aucun :
/// il manque ce qui s'est passé entre les deux.
private let ecartMaximal: TimeInterval = 3 * 3600

/// Le calendrier des cartes : un jour s'y découpe à l'heure de Paris.
private let calendrierDeParis: Calendar = {
    var calendrier = Calendar(identifier: .gregorian)
    calendrier.timeZone = intercodeTimeZone
    return calendrier
}()

/// Le premier des `jours` derniers jours de la carte, à minuit. Comptés depuis
/// sa validation la plus récente, et non depuis aujourd'hui : un vieux relevé
/// ne s'ouvre pas sur une page vide.
func debutDesDerniersJours(_ events: [[String: Any]], jours: Int) -> Date? {
    guard let recente = events.compactMap({ ResolvedEvent.instant($0) }).max() else { return nil }
    return debutDesDerniersJours(depuis: recente, jours: jours)
}

/// Le premier des `jours` derniers jours comptés depuis `recente`, à minuit.
func debutDesDerniersJours(depuis recente: Date, jours: Int) -> Date {
    calendrierDeParis.date(byAdding: .day, value: -(max(jours, 1) - 1),
                           to: calendrierDeParis.startOfDay(for: recente)) ?? recente
}

/// Combien de validations, en tête de la carte, datent de `limite` ou d'après.
/// La carte les range de la plus récente à la plus ancienne.
func nombreDeValidations(_ events: [[String: Any]], depuis limite: Date) -> Int {
    events.firstIndex { (ResolvedEvent.instant($0) ?? .distantPast) < limite } ?? events.count
}

/// Combien de jours la carte couvre, de sa plus ancienne validation datée à la
/// plus récente, bornes comprises.
func joursCouverts(_ events: [[String: Any]]) -> Int {
    joursCouverts(events.compactMap { ResolvedEvent.instant($0) })
}

/// Le même, sur des dates déjà lues.
func joursCouverts(_ dates: [Date]) -> Int {
    guard let recente = dates.max(), let ancienne = dates.min() else { return 0 }
    let ecart = calendrierDeParis.dateComponents([.day],
                                                 from: calendrierDeParis.startOfDay(for: ancienne),
                                                 to: calendrierDeParis.startOfDay(for: recente)).day ?? 0
    return ecart + 1
}

/// Les validations d'une carte rangées en trajets, et les trajets en jours.
///
/// Une entrée ouvre un trajet, la « Validation » d'une borne sans portique
/// aussi ; tout le reste s'y rattache — correspondances, sorties, refus. Ce
/// qu'est une validation, `transitionRacontee` en décide, la même qui peint les
/// pastilles. Un trajet se range au jour où il commence : parti avant minuit,
/// il reste à la veille. Tout se lit du plus récent au plus ancien : les jours,
/// les trajets d'un jour, les validations d'un trajet.
func trajetsParJour(_ events: [[String: Any]], contrats: [[String: Any]]) -> [JourneeDeTrajets] {
    var trajets: [(debut: Date, dernier: Date, indices: [Int])] = []
    // La carte range ses événements du plus récent au plus ancien : on la lit
    // à rebours pour les prendre dans l'ordre.
    for i in events.indices.reversed() {
        guard let date = ResolvedEvent.instant(events[i]) else { continue }
        let transition = transitionRacontee(events[i],
                                            suivants: Array(events[..<i]),
                                            precedents: Array(events[(i + 1)...]),
                                            contrats: contrats)
        let ouvre = TransitionKind(transition) == .entree || transition == "Validation"
        if !ouvre, let courant = trajets.last, date.timeIntervalSince(courant.dernier) <= ecartMaximal {
            trajets[trajets.count - 1].indices.append(i)
            trajets[trajets.count - 1].dernier = date
        } else {
            trajets.append((debut: date, dernier: date, indices: [i]))
        }
    }

    var parJour: [Date: [Trajet]] = [:]
    for trajet in trajets {
        parJour[calendrierDeParis.startOfDay(for: trajet.debut), default: []].append(Trajet(indices: trajet.indices.reversed()))
    }
    return parJour
        .map { JourneeDeTrajets(jour: $0.key, trajets: $0.value.reversed()) }
        .sorted { $0.jour > $1.jour }
}
