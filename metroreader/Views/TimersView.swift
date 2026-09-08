//
//  TimersView.swift
//  metroreader
//

import SwiftUI
import Combine


/// Clés des trois interrupteurs de Réglages
enum TimerSettings {
    static let alreadyValidated = "timerAlreadyValidated"
    static let sale = "timerSale"
    static let control = "timerControl"
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
                switch timers.validity {
                case .valid(let countdown):
                    box(color: .green) {
                        row(TimersView.titreValable(timers.coverage),
                            countdown: countdown,
                            coverage: timers.coverage)
                    }
                case .recentlyExpired(let countdown):
                    box(color: .orange) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Titre expiré")
                                .fontWeight(.semibold)
                            Text("Depuis \(TimersView.clock(-countdown.remaining))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                case .expired:
                    box(color: .red) {
                        Text("Titre non valable")
                            .fontWeight(.semibold)
                    }
                }
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
                badge("ic_ticketing_orly_roissy")
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
