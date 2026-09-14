//
//  DebugTimers.swift
//  metroreader
//

import SwiftUI

/// Ce que le mode debug dit des timers, sous l'environnement de la carte : l'état
/// que calcule le contrôle et les fenêtres dont il part, pour comprendre un
/// encart qui surprend. Il se calcule avec les mêmes réglages que l'encart, et
/// même là où l'encart se tait, dans l'historique.
struct DebugDesTimers: View {
    let contracts: [[String: Any]]
    let events: [[String: Any]]

    @AppStorage(TimerSettings.controlMode) private var controlMode = ControlMode.automatique.rawValue
    @AppStorage(TimerSettings.controlTolerance) private var toleranceEnabled = true
    @AppStorage(TimerSettings.controlToleranceMinutes) private var toleranceMinutes = TimerSettings.defaultToleranceMinutes

    private static let jourHeure: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = intercodeTimeZone
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    var body: some View {
        let timers = PassTimers(contracts: contracts, events: events)
        let mode = ControlMode(rawValue: controlMode) ?? .automatique
        let tolerance: TimeInterval? = toleranceEnabled ? TimeInterval(toleranceMinutes) * 60 : nil
        Section {
            ligne("État du contrôle", Self.etat(timers.validity(mode: mode, tolerance: tolerance)))
            ligne("Contrôlé", mode.label + (tolerance.map { " · tolérance \(Int($0 / 60)) min" } ?? " · sans tolérance"))
            ligne("Temps de validité", Self.fenetre(timers.control))
            ligne("Mode couvert", timers.coverage.map { $0.mode + ($0.airport ? ", aéroports compris" : "") } ?? "—")
            ligne("Pass déjà validé", Self.fenetre(timers.alreadyValidated))
            ligne("Achat impossible", Self.vente(timers.sale))
            ligne("Titre utilisable", timers.hasUsableContract ? "Oui" : "Non")
            ligne("Forfait illimité", timers.hasUsableForfait ? "Oui" : "Non")
        } header: {
            Text("Debug · timers")
        }
    }

    private static func etat(_ validity: PassTimers.Validity) -> String {
        switch validity {
        case .valid:
            return "Valide"
        case .tolerated(.recentlyExpired):
            return "Toléré : expiré depuis moins que la tolérance"
        case .tolerated(.neighbouringMode(_, let validated)):
            return "Toléré : validé sur le mode voisin (\(validated?.label ?? "inconnu"))"
        case .tolerated(.unvalidatedPass):
            return "Toléré : forfait chargé, pas validé"
        case .wrongMode:
            return "Mode non couvert"
        case .notValidated:
            return "Pas validé, titre chargé"
        case .none:
            return "Ni validation ni titre utilisable"
        }
    }

    /// Le début et la fin d'un décompte, sa durée, et s'il court encore.
    private static func fenetre(_ countdown: PassTimers.Countdown?) -> String {
        guard let countdown else { return "—" }
        let etat = countdown.isRunning ? "en cours" : "écoulé"
        return "\(jourHeure.string(from: countdown.start)) → \(jourHeure.string(from: countdown.end)) · \(Int(countdown.duration / 60)) min, \(etat)"
    }

    private static func vente(_ sale: PassTimers.SaleBlock?) -> String {
        guard let sale else { return "—" }
        let fin = sale.countdown.map { "jusqu'au \(jourHeure.string(from: $0.end))" }
            ?? "tant qu'un titre bloquant reste chargé"
        return "\(sale.blocked.joined(separator: ", ")) · \(fin)"
    }

    /// Un intitulé, et ce qu'on en sait, qui peut tenir sur plusieurs lignes.
    private func ligne(_ titre: String, _ valeur: String) -> some View {
        LabeledContent(titre) {
            Text(valeur)
                .multilineTextAlignment(.trailing)
        }
    }
}
