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
        let blocked: [String] // Titres dont l'achat est impossible
        let countdown: Countdown? // nil : blocage permanent, un titre bloquant est encore sur le pass
    }

    /// Validité opposable à un contrôle, telle que la calcule le timer
    /// « Contrôle ».
    ///
    /// Deux choses s'y jouent à la fois : le temps, et le mode. Une validation
    /// peut courir encore et ne rien valoir — un titre ferré ne couvre pas un
    /// bus. Elle peut être éteinte depuis peu et passer quand même.
    enum Validity {
        /// Vert : une validation en cours, qui couvre le mode contrôlé.
        case valid(Countdown)
        /// Jaune : ça devrait passer sans que ce soit net.
        case tolerated(Tolerance)
        /// Rouge : une validation en cours, mais pas pour ce mode-là.
        case wrongMode
        /// Orange sanguin : rien de validé, mais un titre valable est chargé.
        /// C'est l'oubli de validation, pas la fraude.
        case notValidated
        /// Rouge : ni validation ni titre valable.
        case none

        enum Tolerance {
            /// Éteinte depuis moins que le délai de tolérance.
            case recentlyExpired(Countdown)
            /// En cours, mais validée sur le mode voisin : la correspondance
            /// n'a pas été revalidée.
            case neighbouringMode(Countdown, validated: ControlMode?)
        }
    }

    /// Ce sur quoi la validation en cours donne un droit.
    ///
    /// Le décompte de contrôle peut courir depuis une validation antérieure —
    /// un bus puis un tram le fait partir du bus — mais c'est le dernier mode
    /// emprunté qui dit ce qui est légal maintenant. Un titre valable en bus ne
    /// l'est pas dans le métro : afficher « Titre valable » sans le préciser
    /// laissait croire le contraire.
    struct Coverage {
        /// Le mode de la dernière validation, tel que la carte l'encode.
        let mode: String
        /// Le titre ouvre en plus les liaisons aéroport.
        let airport: Bool
    }

    static let defaultToleranceWindow: TimeInterval = 1800 // 30 min

    let alreadyValidated: Countdown? // 7 min après une entrée ou une correspondance
    let sale: SaleBlock? // 4 h après la consommation d'un T+, TMTR ou Aéroport
    let control: Countdown? // Temps de validité : 2 h en rail, 1 h 30 en surface
    let coverage: Coverage? // Le mode que ce temps de validité couvre

    /// Un titre utilisable est chargé sur le pass, indépendamment de toute
    /// validation. C'est ce qui sépare l'oubli — un forfait au fond de la
    /// poche — de l'absence de titre.
    let hasUsableContract: Bool

    /// - Parameters:
    ///   - mode: le mode dans lequel on se déclare contrôlé.
    ///   - tolerance: le délai pendant lequel un titre éteint passe encore,
    ///     ou nil si la tolérance est désactivée.
    func validity(mode: ControlMode = .automatique,
                  tolerance: TimeInterval? = defaultToleranceWindow) -> Validity {
        guard let control else { return sansValidation }

        // Le mode d'abord : une validation qui ne couvre pas ce qu'on contrôle
        // ne vaut rien, si récente soit-elle.
        let accord = coverage.map { mode.accord(avec: $0) } ?? .exact

        if control.isRunning {
            switch accord {
            case .exact:  return .valid(control)
            case .voisin: return .tolerated(.neighbouringMode(control,
                                                              validated: coverage.flatMap { ControlMode.couvrant($0.mode) }))
            case .non:    return .wrongMode
            }
        }

        if accord == .non { return .wrongMode }
        if let tolerance, -control.remaining < tolerance {
            return .tolerated(.recentlyExpired(control))
        }
        return sansValidation
    }

    /// Rien qui coure : reste à savoir si le pass porte quand même de quoi
    /// voyager.
    private var sansValidation: Validity {
        hasUsableContract ? .notValidated : .none
    }

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

    // Ordre d'affichage canonique des titres bloqués
    private static let saleOrder = ["Métro-Train-RER", "Paris <> Aéroports"]

    // Titres soumis à la règle de vente, et ce que leur présence ou leur
    // consommation bloque. Le Bus-Tram est compatible avec tout, et le T+ n'est
    // plus vendu donc il n'apparaît jamais parmi les titres bloqués.
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
            let date = interpretEventInstant(dateBits, getKey(event, "EventTimeStamp") ?? "")

            let routeNumber = getKey(event, "EventRouteNumber").flatMap { Int($0, radix: 2) }
            let provider = getKey(event, "EventServiceProvider").flatMap { Int($0, radix: 2) }
            let (mode, transition) = interpretEventCode(getKey(event, "EventCode") ?? "",
                                                        isRouteNumberPresent: routeNumber != nil,
                                                        routeNumber: routeNumber,
                                                        serviceProvider: provider)

            let pointer = interpretInt(getKey(event, "EventContractPointer") ?? "")
            let contract = (pointer > 0 && pointer <= contracts.count) ? contracts[pointer - 1] : nil

            return TimedEvent(date: date, mode: mode, kind: Kind(transition: transition), contract: contract)
        }

        alreadyValidated = Self.alreadyValidatedTimer(parsed)
        sale = Self.saleTimer(contracts: contracts, events: parsed)
        control = Self.controlTimer(parsed)
        coverage = Self.coverage(parsed)
        hasUsableContract = Self.usableContract(contracts)
    }

    /// Un titre encore utilisable aujourd'hui. `isContractDisabled` couvre le
    /// statut, l'échéance et le compteur ; reste la date de début, qu'un titre
    /// acheté pour le mois prochain n'a pas encore atteinte.
    private static func usableContract(_ contracts: [[String: Any]]) -> Bool {
        contracts.contains { contract in
            guard !isContractDisabled(contract) else { return false }
            guard let start = getKey(contract, "ContractValidityStartDate") else { return true }
            return interpretDateAsDate(start) <= Date()
        }
    }

    /// Le dernier mode emprunté, et si le titre qui l'a payé ouvre aussi les
    /// aéroports.
    private static func coverage(_ events: [TimedEvent]) -> Coverage? {
        guard let last = events.first, last.isTransit else { return nil }
        return Coverage(mode: last.mode, airport: airportAllowed(last))
    }

    // Titres qui couvrent les liaisons aéroport quelles que soient les zones.
    private static let airportTariffs: Set<Int> = [
        0x500B, 0x501B, // Paris <> Aéroports
        0x1000, 0x1001, // Navigo Liberté +
    ]

    /// Les aéroports ne s'ajoutent qu'au rail, et qu'avec un titre qui les
    /// couvre : le ticket dédié, Liberté+ qui facture le trajet réellement
    /// effectué, ou un abonnement dont les zones vont jusqu'à la quatrième.
    private static func airportAllowed(_ event: TimedEvent) -> Bool {
        guard event.isRail, let contract = event.contract else { return false }
        if let tariff = tariffCode(contract), airportTariffs.contains(tariff) { return true }
        guard let zoneBits = getKey(contract, "ContractValidityZones") else { return false }
        return interpretZoneSet(zoneBits).contains(4)
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

    /// Un titre soumis à la règle de vente bloque tant qu'il reste sur le pass,
    /// puis encore 4 h après la consommation du dernier d'entre eux.
    private static func saleTimer(contracts: [[String: Any]], events: [TimedEvent]) -> SaleBlock? {
        var permanent: Set<String> = []
        var timed: Set<String> = []
        var countdown: Countdown?

        // Titres bloquants encore chargés : le blocage n'a pas de fin connue.
        for contract in contracts {
            guard let tariff = tariffCode(contract),
                  let blocks = saleRules[tariff],
                  let countBits = getKey(contract, "CounterContractCount"),
                  interpretInt(countBits) > 0 else { continue }
            permanent.formUnion(blocks)
        }

        // Sinon, les 4 h qui suivent la consommation du dernier titre bloquant.
        if let event = events.first(where: { $0.contract.flatMap(tariffCode).map { saleRules[$0] != nil } ?? false }),
           let tariff = event.contract.flatMap(tariffCode),
           let blocks = saleRules[tariff] {
            let elapsed = Countdown(start: event.date, duration: 4 * 3600)
            if elapsed.isRunning {
                timed.formUnion(blocks)
                countdown = elapsed
            }
        }

        let blocked = saleOrder.filter { permanent.contains($0) || timed.contains($0) }
        guard !blocked.isEmpty else { return nil }
        return SaleBlock(blocked: blocked, countdown: permanent.isEmpty ? countdown : nil)
    }

    private static func tariffCode(_ contract: [String: Any]) -> Int? {
        guard let bits = getKey(contract, "ContractTariff") else { return nil }
        return Int(bits, radix: 2)
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
