//
//  TimersView.swift
//  metroreader
//

import SwiftUI
import Combine


/// Clés des interrupteurs de Réglages
enum TimerSettings {
    static let alreadyValidated = "timerAlreadyValidated"
    static let sale = "timerSale"
    static let control = "timerControl"

    // Options du contrôle
    static let controlOutline = "timerControlOutline"
    static let controlMode = "timerControlMode"
    static let controlTolerance = "timerControlTolerance"
    static let controlToleranceMinutes = "timerControlToleranceMinutes"

    static let defaultToleranceMinutes = 30
    static let toleranceRange: ClosedRange<Double> = 10...120
}


extension Color {
    /// L'oubli de validation : ni le vert du droit ouvert, ni le rouge de la
    /// fraude. Un rouge chaud qui alerte sans accuser.
    static let orangeSanguine = Color(red: 0.79, green: 0.25, blue: 0.09)
}


extension PassTimers.Validity {
    /// La couleur de l'état, la même pour l'encart et pour le contour du pass.
    var color: Color {
        switch self {
        case .valid:        return .green
        case .tolerated:    return .yellow
        case .wrongMode:    return .red
        case .notValidated: return .orangeSanguine
        case .none:         return .red
        }
    }

    /// Le halo du contour. Ce qui demande une seconde d'attention rayonne plus.
    var glow: CGFloat {
        switch self {
        case .tolerated:    return 16
        case .notValidated: return 12
        default:            return 6
        }
    }
}


/// Une horloge qui bat la seconde.
///
/// Les décomptes ne changent pas de contenu, ils changent d'état : à zéro, le
/// « Pass déjà validé » n'a plus lieu d'être affiché, et un titre valable
/// devient expiré. Rien dans les données ne bouge à cet instant-là, donc rien
/// ne redemande le rendu — la vue restait figée sur 0:00:00 jusqu'à ce qu'on
/// change d'onglet. C'est cette horloge qui la réveille.
final class SecondTicker: ObservableObject {
    @Published private(set) var now = Date()

    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
    }
}


struct TimersView: View {
    let timers: PassTimers

    @StateObject private var ticker = SecondTicker()

    @AppStorage(TimerSettings.alreadyValidated) private var alreadyValidatedEnabled = true
    @AppStorage(TimerSettings.sale) private var saleEnabled = true
    @AppStorage(TimerSettings.control) private var controlEnabled = true
    @AppStorage(TimerSettings.controlMode) private var controlMode = ControlMode.automatique.rawValue
    @AppStorage(TimerSettings.controlTolerance) private var toleranceEnabled = true
    @AppStorage(TimerSettings.controlToleranceMinutes) private var toleranceMinutes = TimerSettings.defaultToleranceMinutes

    private var mode: ControlMode { ControlMode(rawValue: controlMode) ?? .automatique }

    private var tolerance: TimeInterval? {
        toleranceEnabled ? TimeInterval(toleranceMinutes) * 60 : nil
    }

    var body: some View {
        // `ticker.now` n'est pas affiché : le lire suffit à faire dépendre le
        // rendu de l'heure, donc à le refaire à chaque seconde.
        let _ = ticker.now

        Group {
            if alreadyValidatedEnabled, let countdown = timers.alreadyValidated, countdown.isRunning {
                box(color: .orange) {
                    row("Pass déjà validé", countdown: countdown)
                }
            }

            if saleEnabled, let sale = timers.sale, sale.countdown?.isRunning ?? true {
                box(color: .red) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Achat impossible pour \(TimersView.list(sale.blocked))")
                            .fontWeight(.semibold)
                        if let countdown = sale.countdown {
                            Text("Disponible dans \(TimersView.hoursMinutes(countdown.remaining))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Tant qu'un titre bloquant reste sur le pass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if controlEnabled {
                let validity = timers.validity(mode: mode, tolerance: tolerance)
                box(color: validity.color) { controle(validity) }
            }
        }
    }

    @ViewBuilder
    private func controle(_ validity: PassTimers.Validity) -> some View {
        switch validity {
        case .valid(let countdown):
            row(TimersView.titreValable(timers.coverage),
                countdown: countdown,
                coverage: timers.coverage)

        case .tolerated(.neighbouringMode(let countdown, let validated)):
            // La correspondance n'a pas été revalidée. Ça se plaide.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let coverage = timers.coverage { ModeBadges(coverage: coverage) }
                    Text("Validé \(validated?.enPhrase ?? "ailleurs"), contrôlé \(mode.enPhrase)")
                        .fontWeight(.semibold)
                }
                Text("Correspondance non revalidée · restant \(TimersView.clock(countdown.remaining))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .tolerated(.recentlyExpired(let countdown)):
            VStack(alignment: .leading, spacing: 6) {
                Text("Titre expiré")
                    .fontWeight(.semibold)
                Text("Depuis \(TimersView.clock(-countdown.remaining))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

        case .wrongMode:
            VStack(alignment: .leading, spacing: 6) {
                Text("Titre non valable \(mode.enPhrase)")
                    .fontWeight(.semibold)
                if let coverage = timers.coverage,
                   let valide = ControlMode.couvrant(coverage.mode) {
                    Text("La validation ne couvre que \(valide.label.lowercased()).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .notValidated:
            VStack(alignment: .leading, spacing: 6) {
                Text("Pas de titre validé")
                    .fontWeight(.semibold)
                Text("Un titre valable est chargé sur le pass, mais il n'a pas été validé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .none:
            VStack(alignment: .leading, spacing: 6) {
                Text("Pas de titre valable")
                    .fontWeight(.semibold)
                Text("Aucune validation, et aucun titre utilisable sur le pass.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func box<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(color.opacity(0.2))
    }

    private func row(_ title: String,
                     countdown: PassTimers.Countdown,
                     coverage: PassTimers.Coverage? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let coverage { ModeBadges(coverage: coverage) }
                Text(title)
                    .fontWeight(.semibold)
            }
            Text("Restant : \(TimersView.clock(countdown.remaining))")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ce que le titre couvre

    /// « Titre valable », suivi de ce sur quoi il l'est. Sans cette précision
    /// la phrase se lit comme un droit général, alors qu'une validation en bus
    /// ne couvre pas le métro.
    static func titreValable(_ coverage: PassTimers.Coverage?) -> String {
        guard let coverage, let portee = portee(coverage) else { return "Titre valable" }
        return "Titre valable \(portee)"
    }

    private static func portee(_ coverage: PassTimers.Coverage) -> String? {
        guard let mode = modeLabel(coverage.mode) else { return nil }
        return coverage.airport ? "\(mode), aéroports compris" : mode
    }

    private static func modeLabel(_ mode: String) -> String? {
        switch mode {
        case "Bus urbain", "Bus interurbain": return "en bus"
        case "Noctilien":                     return "en Noctilien"
        case "Métro":                         return "en métro"
        case "RER", "Train", "Transilien":    return "en RER et train"
        case "Tramway":                       return "en tramway"
        case "Câble":                         return "en câble"
        default:                              return nil
        }
    }

    /// Le pictogramme du mode, celui-là même qui est affiché sur les quais.
    static func modeIcon(_ mode: String) -> String? {
        switch mode {
        case "Bus urbain", "Bus interurbain": return "mode_bus"
        case "Noctilien":                     return "mode_noctilien"
        case "Métro":                         return "mode_metro"
        case "RER", "Train", "Transilien":    return "mode_train_rer"
        case "Tramway":                       return "mode_tram"
        case "Câble":                         return "mode_cable"
        default:                              return nil
        }
    }

    // MARK: - Mise en forme

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)min" }
        return "\(hours)h et \(minutes)min"
    }

    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        if items.count == 1 { return last }
        return items.dropLast().joined(separator: ", ") + " et " + last
    }
}


/// Les pictogrammes de ce que la validation en cours couvre. Ce sont ceux des
/// quais : c'est à eux qu'on reconnaît ce qu'on a le droit de prendre.
private struct ModeBadges: View {
    let coverage: PassTimers.Coverage

    var body: some View {
        HStack(spacing: 4) {
            if let mode = TimersView.modeIcon(coverage.mode) {
                badge(mode)
            }
            if coverage.airport {
                badge(ControlMode.aeroport.icon)
            }
        }
    }

    private func badge(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(.primary)
    }
}
