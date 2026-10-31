//
//  PrixDesTrajets.swift
//  metroreader
//

import Foundation


/// La grille d'Île-de-France Mobilités au 1er janvier 2026, plein tarif.
///
/// Le site d'IDFM refuse qu'on le lise automatiquement : ces montants viennent
/// de sa grille tarifaire telle que la presse l'a relayée, et se revérifient à
/// chaque hausse de janvier.
enum TarifsIDFM {
    static let annee = 2026
    /// Un trajet Liberté+ en métro, train ou RER.
    static let libertePlusRail = 2.04
    /// Un trajet Liberté+ en bus ou en tram.
    static let libertePlusSurface = 1.64
    static let navigoMois = 90.80
    static let navigoSemaine = 32.40
    static let navigoAnnuel = 998.80
    /// Imagine R, scolaire comme étudiant, à l'année.
    static let imagineR = 401.30
    static var navigoAnnuelParMois: Double { navigoAnnuel / 12 }
}

/// Le réglage qui montre le prix sous chaque trajet de l'historique.
enum PrixSettings {
    static let afficher = "prixDesTrajets"
}


/// La période sur laquelle un forfait s'amortit.
enum PeriodeForfait {
    case jour, semaine, mois, annee

    /// Le libellé d'un montant sur cette période.
    var parPeriode: String {
        switch self {
        case .jour:    return "par jour"
        case .semaine: return "par semaine"
        case .mois:    return "par mois"
        case .annee:   return "par an"
        }
    }
}

/// Ce qu'un forfait coûte, et d'où vient le montant.
struct PrixForfait {
    enum Source { case saisi, carte, grille }

    let montant: Double
    let periode: PeriodeForfait
    let source: Source

    /// Ce que le forfait coûte sur le seau où ses trajets se comptent : le
    /// jour, la semaine ou le mois. Un forfait annuel se compte au mois, pour
    /// un douzième de son prix.
    var coutDuSeau: Double {
        periode == .annee ? montant / 12 : montant
    }
}


/// Les forfaits, leur prix et leur période.
enum PrixDesForfaits {
    /// La clé sous laquelle se range le prix saisi pour un code de tarif.
    static func cle(_ tarif: Int) -> String { "prixForfait.\(tarif)" }

    static func tarif(_ contrat: [String: Any]) -> Int? {
        getKey(contrat, "ContractTariff").flatMap { Int($0, radix: 2) }
    }

    /// Un forfait illimité : ni compteur ni Liberté+.
    static func estForfait(_ contrat: [String: Any]) -> Bool {
        getKey(contrat, "CounterContractCount") == nil && !estLibertePlus(contrat)
    }

    /// Les forfaits de la grille, à défaut de prix sur la carte ou saisi. Les
    /// forfaits à 75 % de la Solidarité Transport coûtent le quart du plein
    /// tarif ; la gratuité, rien.
    private static let grille: [Int: (Double, PeriodeForfait)] = [
        0x0000: (TarifsIDFM.navigoMois, .mois),
        0x0001: (TarifsIDFM.navigoSemaine, .semaine),
        0x0002: (TarifsIDFM.navigoAnnuel, .annee),
        0x0004: (TarifsIDFM.imagineR, .annee),
        0x0005: (TarifsIDFM.imagineR, .annee),
        0x4000: (TarifsIDFM.navigoMois / 4, .mois),
        0x4001: (TarifsIDFM.navigoSemaine / 4, .semaine),
        0x8003: (0, .mois),
    ]

    /// Les forfaits du catalogue dont on peut saisir le prix, dans l'ordre où
    /// les Réglages les présentent. Le Navigo JOP n'est plus vendu, le Pass
    /// Interne ne s'achète pas.
    static let duCatalogue: [Int] = [
        0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x000D, 0x000F,
        0x0015, 0x4015, 0x4000, 0x4001, 0x8003, 0x8010,
    ]

    /// La période d'un forfait d'après son seul code : celle de la grille, le
    /// jour pour les titres d'un jour, le mois à défaut.
    static func periode(tarif: Int) -> PeriodeForfait {
        if let connu = grille[tarif] { return connu.1 }
        switch tarif {
        case 0x0003, 0x000D, 0x000F, 0x0015, 0x4015: return .jour
        default: return .mois
        }
    }

    /// Le prix d'un forfait d'après son seul code : saisi, sinon de la grille.
    static func prix(tarif: Int, saisis: [Int: Double]) -> PrixForfait? {
        let periode = periode(tarif: tarif)
        if let saisi = saisis[tarif], saisi > 0 {
            return PrixForfait(montant: saisi, periode: periode, source: .saisi)
        }
        return grille[tarif].map { PrixForfait(montant: $0.0, periode: $0.1, source: .grille) }
    }

    /// Les prix saisis pour tout le catalogue.
    static func saisis() -> [Int: Double] {
        saisis(duCatalogue)
    }

    /// La période d'un forfait : celle de la grille, sinon celle que disent ses
    /// dates de validité. Un Navigo Annuel à tacite reconduction court dix ans
    /// sur la carte, un Imagine R un an : tous deux s'amortissent au mois.
    static func periode(_ contrat: [String: Any]) -> PeriodeForfait {
        if let tarif = tarif(contrat), let connu = grille[tarif] { return connu.1 }
        if let debut = getKey(contrat, "ContractValidityStartDate"),
           let fin = getKey(contrat, "ContractValidityEndDate") {
            let jours = interpretDateAsDate(fin).timeIntervalSince(interpretDateAsDate(debut)) / 86400
            if jours < 2 { return .jour }
            if jours < 10 { return .semaine }
            if jours < 45 { return .mois }
        }
        return .annee
    }

    /// Le prix d'un forfait : celui qu'on a saisi, sinon celui que la carte
    /// écrit, sinon celui de la grille. Rien pour un forfait hors grille dont on
    /// ne sait pas le prix — un Navigo Jour, faute de saisie.
    static func prix(_ contrat: [String: Any], saisis: [Int: Double]) -> PrixForfait? {
        let periode = periode(contrat)
        if let tarif = tarif(contrat), let saisi = saisis[tarif], saisi > 0 {
            return PrixForfait(montant: saisi, periode: periode, source: .saisi)
        }
        if let bits = getKey(contrat, "ContractPriceAmount") {
            let montant = interpretAmount(bits)
            if montant > 0 { return PrixForfait(montant: montant, periode: periode, source: .carte) }
        }
        if let tarif = tarif(contrat), let connu = grille[tarif] {
            return PrixForfait(montant: connu.0, periode: connu.1, source: .grille)
        }
        return nil
    }

    /// Les prix saisis, pour ces codes de tarif.
    static func saisis(_ tarifs: some Sequence<Int>, defaults: UserDefaults = .standard) -> [Int: Double] {
        var prix: [Int: Double] = [:]
        for tarif in tarifs {
            let valeur = defaults.double(forKey: cle(tarif))
            if valeur > 0 { prix[tarif] = valeur }
        }
        return prix
    }
}


/// Un trajet, lu pour ce qu'il coûte.
struct TrajetChiffre {
    let id: Int
    let debut: Date
    /// Ce que le trajet coûterait en Liberté+, correspondances comprises.
    let libertePlus: Double
    /// Le titre que désigne la validation qui l'ouvre.
    let contrat: [String: Any]?
    /// Payé en Liberté+ : l'estimation est son prix.
    let payeEnLibertePlus: Bool
}

/// Ce qu'un trajet a coûté.
struct PrixTrajet {
    let libertePlus: Double
    /// La part du forfait qui lui revient, quand un forfait de prix connu l'a
    /// payé.
    let forfait: Double?
    let payeEnLibertePlus: Bool
}

/// Un mois de trajets, et ce qu'ils auraient coûté selon le titre.
struct BilanDuMois: Identifiable {
    let mois: Date
    let trajets: Int
    let libertePlus: Double
    /// Ce que les forfaits de prix connu ont coûté sur le mois.
    let forfaits: Double?
    /// Le mois de la plus ancienne validation : la carte n'en garde peut-être
    /// pas le début.
    let partiel: Bool

    var id: Date { mois }
}


/// Les trajets d'une carte, chiffrés.
///
/// Le gros du calcul — ranger les validations en trajets, estimer chacun en
/// Liberté+ — se fait une fois. Le prix des forfaits s'y applique ensuite à la
/// demande : changer celui qu'on a saisi ne relit pas la carte.
struct ChiffrageDesTrajets {
    let trajets: [TrajetChiffre]

    /// Ce que dure une correspondance Liberté+, comptée depuis la validation
    /// qui ouvre le titre : 2 h dans le rail, 1 h 30 entre bus et tram.
    private static let delaiRail: TimeInterval = 2 * 3600
    private static let delaiSurface: TimeInterval = 90 * 60

    init(trajets: [TrajetChiffre]) {
        self.trajets = trajets
    }

    init(events: [[String: Any]], contrats: [[String: Any]]) {
        let validations = Validations(events, contrats: contrats)
        var chiffres: [TrajetChiffre] = []
        for journee in trajetsParJour(events, contrats: contrats) {
            for trajet in journee.trajets {
                let chrono = Array(trajet.indices.reversed())
                guard let ouverture = chrono.first(where: { Self.entreeDeVoyage(validations[$0]) }),
                      let debut = validations[ouverture].instant else { continue }
                let contrat = validations[ouverture].contrat
                chiffres.append(TrajetChiffre(
                    id: trajet.id, debut: debut,
                    libertePlus: Self.libertePlus(chrono.map { validations[$0] }),
                    contrat: contrat,
                    payeEnLibertePlus: contrat.map(estLibertePlus) ?? false))
            }
        }
        trajets = chiffres
    }

    /// Une entrée en voyage qui n'a pas été refusée.
    private static func entreeDeVoyage(_ lue: LectureValidation) -> Bool {
        guard !lue.refus, lue.transition.hasPrefix("Entrée") || lue.transition == "Validation",
              let mode = ModeTransport(rawValue: lue.mode) else { return false }
        return mode.estFerre || mode.estSurface
    }

    /// Ce qu'un trajet coûte en Liberté+.
    ///
    /// Les deux réseaux se paient à part : un trajet métro-train-RER court 2 h
    /// depuis sa première validation, un trajet bus-tram 1 h 30, et passer de
    /// l'un à l'autre en ouvre un second. Dans le rail, le rangement en trajets
    /// a déjà tranché : une sortie franche hors des correspondances par la voie
    /// publique en commence un autre. Entre bus et tram, reprendre une ligne
    /// déjà empruntée se repaie, l'aller-retour n'étant pas une correspondance.
    static func libertePlus(_ chrono: [LectureValidation]) -> Double {
        var total = 0.0
        var rail: Date?
        var surface: (debut: Date, lignes: Set<LigneEmpruntee>)?
        for lue in chrono {
            guard entreeDeVoyage(lue), let date = lue.instant,
                  let mode = ModeTransport(rawValue: lue.mode) else { continue }
            if mode.estFerre {
                if rail.map({ date.timeIntervalSince($0) > delaiRail }) ?? true {
                    total += TarifsIDFM.libertePlusRail
                    rail = date
                }
            } else {
                let reprise = lue.ligne.map { surface?.lignes.contains($0) ?? false } ?? false
                if reprise || (surface.map { date.timeIntervalSince($0.debut) > delaiSurface } ?? true) {
                    total += TarifsIDFM.libertePlusSurface
                    surface = (debut: date, lignes: [])
                }
                if let ligne = lue.ligne { surface?.lignes.insert(ligne) }
            }
        }
        return total
    }

    /// Les codes de tarif des forfaits qui ont payé un trajet.
    var tarifsDesForfaits: [Int] {
        var vus: [Int] = []
        for trajet in trajets {
            guard let contrat = trajet.contrat, PrixDesForfaits.estForfait(contrat),
                  let tarif = PrixDesForfaits.tarif(contrat), !vus.contains(tarif) else { continue }
            vus.append(tarif)
        }
        return vus
    }

    /// Le seau où se compte un trajet payé par ce forfait : son jour, sa
    /// semaine ou son mois, et le titre lui-même.
    private func seau(_ trajet: TrajetChiffre, _ contrat: [String: Any], _ periode: PeriodeForfait) -> String {
        let composants: Set<Calendar.Component>
        switch periode {
        case .jour:          composants = [.year, .month, .day]
        case .semaine:       composants = [.yearForWeekOfYear, .weekOfYear]
        case .mois, .annee:  composants = [.year, .month]
        }
        let date = intercodeCalendar.dateComponents(composants, from: trajet.debut)
        let titre = getKey(contrat, "ContractSerialNumber")
            ?? "\(getKey(contrat, "ContractTariff") ?? "")|\(getKey(contrat, "ContractValidityStartDate") ?? "")"
        return "\(titre)|\(date.year ?? date.yearForWeekOfYear ?? 0)|\(date.month ?? 0)|\(date.day ?? 0)|\(date.weekOfYear ?? 0)"
    }

    /// Le prix de chaque trajet, par identifiant.
    ///
    /// Un trajet payé par un forfait reçoit sa part du forfait : son coût sur
    /// la période, partagé entre les trajets qu'il y a payés.
    func prix(saisis: [Int: Double]) -> [Int: PrixTrajet] {
        var parSeau: [String: (cout: Double, ids: [Int])] = [:]
        for trajet in trajets {
            guard let contrat = trajet.contrat, PrixDesForfaits.estForfait(contrat),
                  let prix = PrixDesForfaits.prix(contrat, saisis: saisis) else { continue }
            let cle = seau(trajet, contrat, prix.periode)
            parSeau[cle, default: (prix.coutDuSeau, [])].ids.append(trajet.id)
        }
        var parts: [Int: Double] = [:]
        for (_, seau) in parSeau {
            let part = seau.cout / Double(seau.ids.count)
            for id in seau.ids { parts[id] = part }
        }
        var resultat: [Int: PrixTrajet] = [:]
        for trajet in trajets {
            resultat[trajet.id] = PrixTrajet(libertePlus: trajet.libertePlus, forfait: parts[trajet.id],
                                             payeEnLibertePlus: trajet.payeEnLibertePlus)
        }
        return resultat
    }

    /// Les mois, du plus récent au plus ancien.
    func bilans(saisis: [Int: Double]) -> [BilanDuMois] {
        let prix = prix(saisis: saisis)
        var parMois: [Date: (trajets: Int, libertePlus: Double, forfaits: Double?)] = [:]
        for trajet in trajets {
            let mois = intercodeCalendar.date(from: intercodeCalendar.dateComponents([.year, .month], from: trajet.debut))
                ?? trajet.debut
            var bilan = parMois[mois] ?? (0, 0, nil)
            bilan.trajets += 1
            bilan.libertePlus += trajet.libertePlus
            if let part = prix[trajet.id]?.forfait {
                bilan.forfaits = (bilan.forfaits ?? 0) + part
            }
            parMois[mois] = bilan
        }
        let ancien = parMois.keys.min()
        return parMois
            .map { BilanDuMois(mois: $0.key, trajets: $0.value.trajets, libertePlus: $0.value.libertePlus,
                               forfaits: $0.value.forfaits, partiel: $0.key == ancien) }
            .sorted { $0.mois > $1.mois }
    }
}


/// Un montant en euros, à la française.
func enEuros(_ montant: Double) -> String {
    montant.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
}
