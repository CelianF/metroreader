//
//  PassTimers.swift
//  metroreader
//

import Foundation


struct PassTimers {

    struct Countdown {
        let start: Date
        let duration: TimeInterval

        var end: Date { start.addingTimeInterval(duration) }
        var remaining: TimeInterval { end.timeIntervalSinceNow }
        var isRunning: Bool { remaining > 0 }
    }

    struct SaleBlock {
        let countdown: Countdown
        let blocked: [String] // Titres dont l'achat est impossible
    }

    /// Validité opposable à un contrôle, telle que la calcule le timer « Contrôle ».
    enum Validity {
        case valid(Countdown)
        case recentlyExpired(Countdown) // Expiré depuis moins de recentlyExpiredWindow
        case expired
        case unknown // Aucun événement exploitable
    }

    static let recentlyExpiredWindow: TimeInterval = 1800 // 30 min

    let alreadyValidated: Countdown? // 7 min après une entrée ou une correspondance
    let sale: SaleBlock? // 4 h après la consommation d'un T+, TMTR ou Aéroport
    let control: Countdown? // Temps de validité : 2 h en rail, 1 h 30 en surface

    var validity: Validity {
        guard let control else { return hasUsableEvent ? .expired : .unknown }
        if control.isRunning { return .valid(control) }
        if -control.remaining < Self.recentlyExpiredWindow { return .recentlyExpired(control) }
        return .expired
    }

    private let hasUsableEvent: Bool

    // MARK: - Classification

    private enum Kind {
        case entry
        case exit
        case correspondence
        case other

        init(transition: String) {
            switch transition {
            case "Entrée", "Entrée (voie publique)", "Validation":
                self = .entry
            case "Entrée (correspondance)", "Sortie (correspondance)":
                self = .correspondence
            case "Sortie", "Sortie (voie publique)":
                self = .exit
            default:
                self = .other
            }
        }
    }

    private static let railModes: Set<String> = ["Métro", "RER", "Train", "Transilien"]
    private static let surfaceModes: Set<String> = ["Bus urbain", "Bus interurbain", "Tramway", "Câble"]

    private struct TimedEvent {
        let date: Date
        let mode: String
        let kind: Kind
        let contract: [String: Any]?

        var isRail: Bool { PassTimers.railModes.contains(mode) }
        var isSurface: Bool { PassTimers.surfaceModes.contains(mode) }
        var isTransit: Bool { isRail || isSurface }
    }

    // Titres soumis à la règle de vente, et ce que leur consommation bloque.
    // Le Bus-Tram est compatible avec tout, le T+ n'est plus vendu donc jamais bloqué.
    private static let saleRules: [Int: [String]] = [
        0x5000: ["Métro-Train-RER", "Paris <> Aéroports"], // Ticket T+
        0x5010: ["Métro-Train-RER", "Paris <> Aéroports"], // Ticket T+ (Réduit)
        0x5008: ["Paris <> Aéroports"],                    // Métro-Train-RER
        0x5018: ["Paris <> Aéroports"],                    // Métro-Train-RER (Réduit)
        0x500B: ["Métro-Train-RER"],                       // Paris <> Aéroports
        0x501B: ["Métro-Train-RER"],                       // Paris <> Aéroports (Réduit)
    ]

    // MARK: - Calcul

    init(contracts: [[String: Any]], events: [[String: Any]]) {
        // Les événements arrivent de la carte du plus récent au plus ancien.
        let parsed: [TimedEvent] = events.compactMap { event in
            guard let dateBits = getKey(event, "EventDateStamp") else { return nil }
            var date = interpretDateAsDate(dateBits)
            date.addTimeInterval(interpretTimeAsTimeInterval(getKey(event, "EventTimeStamp") ?? ""))

            let routeNumber = getKey(event, "EventRouteNumber").flatMap { Int($0, radix: 2) }
            let (mode, transition) = interpretEventCode(getKey(event, "EventCode") ?? "",
                                                        isRouteNumberPresent: routeNumber != nil,
                                                        routeNumber: routeNumber)

            let pointer = interpretInt(getKey(event, "EventContractPointer") ?? "")
            let contract = (pointer > 0 && pointer <= contracts.count) ? contracts[pointer - 1] : nil

            return TimedEvent(date: date, mode: mode, kind: Kind(transition: transition), contract: contract)
        }

        hasUsableEvent = parsed.contains { $0.isTransit }
        alreadyValidated = Self.alreadyValidatedTimer(parsed)
        sale = Self.saleTimer(parsed)
        control = Self.controlTimer(parsed)
    }

    /// 7 min après une entrée ou une correspondance, annulé par une sortie.
    private static func alreadyValidatedTimer(_ events: [TimedEvent]) -> Countdown? {
        guard let last = events.first, last.isTransit else { return nil }
        switch last.kind {
        case .entry, .correspondence:
            return Countdown(start: last.date, duration: 7 * 60)
        case .exit, .other:
            return nil
        }
    }

    /// 4 h après la consommation du dernier titre soumis à la règle de vente.
    private static func saleTimer(_ events: [TimedEvent]) -> SaleBlock? {
        for event in events {
            guard let contract = event.contract,
                  let tariffBits = getKey(contract, "ContractTariff"),
                  let tariff = Int(tariffBits, radix: 2),
                  let blocked = saleRules[tariff] else { continue }
            return SaleBlock(countdown: Countdown(start: event.date, duration: 4 * 3600),
                             blocked: blocked)
        }
        return nil
    }

    /// Temps de validité. La famille est choisie par le mode du dernier événement.
    private static func controlTimer(_ events: [TimedEvent]) -> Countdown? {
        guard let last = events.first else { return nil }

        if last.isRail {
            // Une correspondance n'ouvre pas de nouveau droit : on remonte
            // jusqu'à l'événement qui l'a ouvert, sur trois événements au plus.
            guard let reference = events.prefix(3).first(where: { $0.kind != .correspondence }),
                  reference.kind == .entry else { return nil }
            return Countdown(start: reference.date, duration: 2 * 3600)
        }

        guard last.isSurface, last.kind != .exit else { return nil }

        // Un ticket à l'unité ouvre une fenêtre de correspondance qui court depuis
        // la première validation ; un forfait la fait courir depuis la dernière.
        if isSingleUse(last.contract), events.count > 1 {
            let previous = events[1]
            if previous.isSurface, last.date.timeIntervalSince(previous.date) <= 5400 {
                return Countdown(start: previous.date, duration: 5400)
            }
        }
        return Countdown(start: last.date, duration: 5400)
    }

    /// Ticket à l'unité ou Liberté+, par opposition à un forfait illimité.
    private static func isSingleUse(_ contract: [String: Any]?) -> Bool {
        guard let contract else { return false }
        if getKey(contract, "CounterContractCount") != nil { return true }
        if let tariffBits = getKey(contract, "ContractTariff"),
           let tariff = Int(tariffBits, radix: 2) {
            return tariff == 0x1000 || tariff == 0x1001 // Navigo Liberté +
        }
        return false
    }
}
