//
//  TransitionStyle.swift
//  metroreader
//

import SwiftUI


/// Ce qu'une validation raconte du trajet, plutôt que ce que la borne a écrit.
///
/// Quitter le RER à Gare de Lyon pour prendre le métro s'inscrit « Sortie
/// (correspondance) » : la borne dit qu'on quitte son réseau, pas qu'on
/// s'arrête. L'annoncer comme une sortie, en rouge, laisse croire que le
/// voyage s'achève — alors que ce qui compte est l'entrée qui suit.
enum TransitionKind {
    case entree
    case correspondance
    case sortie
    case refus
    case autre

    init(_ transition: String) {
        if transition == transitionRefus {
            self = .refus
        } else if transition.localizedCaseInsensitiveContains("correspondance") {
            self = .correspondance
        } else if transition.hasPrefix("Entrée") {
            self = .entree
        } else if transition.hasPrefix("Sortie") {
            self = .sortie
        } else {
            self = .autre
        }
    }

    /// Une correspondance n'est ni tout à fait une entrée ni une sortie : le
    /// voyage continue, mais ailleurs. Elle se peint donc du cyan, voisin du
    /// bleu de l'entrée sans s'y confondre. La sortie prend le vert d'un
    /// voyage mené à son terme ; le rouge reste à ce qui arrête, les refus.
    var color: Color {
        switch self {
        case .entree:         return .blue
        case .correspondance: return .cyan
        case .sortie:         return .green
        case .refus:          return .red
        case .autre:          return .purple
        }
    }
}

/// Ce qu'une validation refusée raconte : rien n'a été franchi, quoi que la
/// borne ait tenté d'écrire. Elle se peint du rouge de ce qui arrête.
let transitionRefus = "Refus"


/// Les modes ferrés dont on sort par une porte de correspondance. Le métro en
/// est exclu à dessein : à Denfert-Rochereau comme à Gare de Lyon, c'est la
/// borne du RER qui écrit le passage dans les deux sens, jamais celle du métro.
private let modesFerresCorrespondance: Set<String> = [
    "RER", "Train", "Transilien", "Train / RER",
]

/// Une correspondance qui fait entrer dans le métro.
///
/// Quitter le RER à Gare de Lyon ou à Denfert-Rochereau pour prendre le métro
/// s'inscrit « Sortie (correspondance) » : la borne dit qu'on quitte son
/// réseau, pas où l'on va. Mais l'autre sens — le métro vers le RER — s'écrit
/// « Entrée (correspondance) » sur cette même borne : la sortie, elle, ne peut
/// mener qu'au métro.
func correspondanceVersMetro(transition: String, mode: String) -> Bool {
    transition == "Sortie (correspondance)" && modesFerresCorrespondance.contains(mode)
}

/// La transition d'une porte SNCF relevée comme menant au métro. La borne y
/// écrit « Entrée » ou « Sortie (voie publique) » comme partout ailleurs ; on
/// la lit comme les portes RATP qui écrivent 6 et 7, puisque c'en est une.
func transitionAuxPortes(_ transition: String, _ eventInfo: [String: Any]) -> String {
    guard GateCorrections.contains(eventInfo) else { return transition }
    if transition.hasPrefix("Sortie") { return "Sortie (correspondance)" }
    if transition.hasPrefix("Entrée") { return "Entrée (correspondance)" }
    return transition
}

/// Les modes dont une entrée prolonge le trajet, tels que la carte les encode.
private let modesFerres: Set<String> = ["Métro", "RER", "Train"]

/// Au-delà, une sortie « voie publique » ne se lit plus comme une correspondance.
private let delaiCorrespondance: TimeInterval = 15 * 60

/// Le nom qu'Île-de-France Mobilités donne à ces correspondances.
let correspondanceVoiePublique = "Correspondance (voie publique)"

/// Une sortie « voie publique » que suit de près une entrée ferrée.
///
/// « Voie publique » ne dit pas qu'on est sorti dans la rue. Île-de-France
/// Mobilités tient une liste de correspondances par la voie publique — Gare du
/// Nord avec Gare de l'Est et Magenta, Saint-Lazare avec Haussmann et Auber,
/// Montparnasse, Austerlitz, Saint-Michel… — où l'on peut sortir puis revalider
/// plus loin sans payer deux trajets. Les portes de ces gares écrivent ce code à
/// chaque sortie, que l'on gagne la rue, le métro par la rue, ou le quai du
/// métro directement comme à la porte 18 de Gare du Nord. La borne n'en sait
/// pas plus ; la validation suivante, si. Sur 44 sorties de ce genre relevées,
/// 29 sont suivies d'une entrée ferrée en moins de dix minutes, les autres
/// après vingt minutes au moins, parfois des jours : quinze minutes les
/// départagent.
///
/// Reste un angle mort : la porte qui donne droit sur le quai du métro n'est
/// suivie d'aucune validation, et sa sortie se lit donc comme une vraie.
///
/// L'entrée de ces mêmes gares s'écrit « Entrée (voie publique) », mais elle
/// est souvent la première validation du trajet : elle ne se lit comme
/// correspondance que si une telle sortie la précède — voir
/// `entreeApresCorrespondance`.
func sortieVersCorrespondance(transition: String, instant: Date?, suivants: [[String: Any]]) -> Bool {
    guard transition == "Sortie (voie publique)", let instant else { return false }
    return suivants.contains { suivant in
        guard let date = ResolvedEvent.instant(suivant) else { return false }
        let ecart = date.timeIntervalSince(instant)
        return ecart >= 0 && ecart <= delaiCorrespondance && estEntreeFerree(lecture(suivant))
    }
}

/// L'autre moitié de la même correspondance : l'entrée ferrée qui suit une
/// sortie « voie publique » de moins de quinze minutes — le métro pris après
/// le train, et non plus le train seul.
///
/// On remonte les validations précédentes, de la plus récente à la plus
/// ancienne comme la carte les range. La sortie doit venir avant toute autre
/// entrée ferrée : une entrée intermédiaire aurait déjà formé la paire, et
/// celle-ci recommence un trajet.
func entreeApresCorrespondance(transition: String, mode: String, instant: Date?, precedents: [[String: Any]]) -> Bool {
    guard let instant, estEntreeFerree((mode, transition)) else { return false }
    for precedent in precedents {
        guard let date = ResolvedEvent.instant(precedent),
              instant.timeIntervalSince(date) <= delaiCorrespondance else { return false }
        let lu = lecture(precedent)
        if lu.transition == "Sortie (voie publique)" { return true }
        if estEntreeFerree(lu) { return false }
    }
    return false
}

/// Le mode et la transition d'un événement voisin, tels que la carte les encode.
private func lecture(_ evenement: [String: Any]) -> (mode: String, transition: String) {
    let route = getKey(evenement, "EventRouteNumber").flatMap { Int($0, radix: 2) }
    let provider = getKey(evenement, "EventServiceProvider").flatMap { Int($0, radix: 2) }
    let (mode, transition) = interpretEventCode(getKey(evenement, "EventCode") ?? "",
                                                isRouteNumberPresent: route != nil,
                                                routeNumber: route,
                                                serviceProvider: provider)
    return (mode, transitionAuxPortes(transition, evenement))
}

private func estEntreeFerree(_ lu: (mode: String, transition: String)) -> Bool {
    modesFerres.contains(lu.mode) && (lu.transition.hasPrefix("Entrée") || lu.transition == "Validation")
}

/// Les modes de surface, ceux du ticket Bus-Tram.
private let modesSurface: Set<String> = ["Bus urbain", "Bus interurbain", "Tramway", "Câble"]

/// Ce que dure un trajet, compté depuis l'entrée qui l'ouvre.
private let delaiRail: TimeInterval = 2 * 3600
private let delaiSurface: TimeInterval = 90 * 60

/// Une entrée qui prolonge, sous forfait, un trajet déjà ouvert.
///
/// Un forfait ne laisse aucune trace du changement : on valide dans le bus
/// comme au départ. Liberté+ non plus, et il offre pourtant la correspondance.
/// Ce qui la révèle, c'est le délai. Un trajet s'ouvre par une entrée et court
/// 2 h s'il part du métro, du RER ou du train, 1 h 30 s'il part du bus, du tram
/// ou du câble, compté depuis cette entrée et jamais relancé. Dans ce délai :
/// - après le rail, une entrée en bus, tram ou câble est une correspondance.
///   Une entrée en train aussi, sans compter pour un changement : métro, RER
///   et train ne font qu'un réseau. Une nouvelle entrée en métro ou en RER ne
///   l'est pas — on n'y revalide pas pour changer de ligne, revalider c'est en
///   être ressorti ;
/// - après le bus, le tram ou le câble, toute entrée l'est.
///
/// Un trajet ne compte qu'un changement : bus, bus puis bus, ou bus, tram puis
/// métro, en commencent un autre, quand bus, métro puis train reste d'un seul
/// tenant. Reprendre une ligne déjà empruntée en commence un autre aussi :
/// l'aller-retour n'est pas une correspondance. Les tickets à l'unité — ceux
/// qui portent un compteur — en sont exclus, puisqu'un changement de réseau y
/// réclame un autre ticket.
func entreeDansLeDelai(_ eventInfo: [String: Any], precedents: [[String: Any]], contrats: [[String: Any]]) -> Bool {
    guard !isRefus(eventInfo), entreeDeVoyage(eventInfo) != nil,
          let instant = ResolvedEvent.instant(eventInfo) else { return false }

    // Deux validations séparées de plus de 2 h ne tiennent dans aucun trajet :
    // on ne remonte pas au-delà du premier écart de cette taille.
    var fenetre = [eventInfo]
    var plusRecente = instant
    for precedent in precedents {
        guard let date = ResolvedEvent.instant(precedent),
              plusRecente.timeIntervalSince(date) <= delaiRail else { break }
        fenetre.append(precedent)
        plusRecente = date
    }

    // Puis on rejoue les entrées dans l'ordre, trajet par trajet. La dernière
    // est celle qu'on juge.
    let chrono = Array(fenetre.reversed())
    var trajet: (debut: Date, depuisLeRail: Bool, forfait: Bool, lignes: Set<String>,
                 changements: Int, dansLeRail: Bool)?
    var prolongee = false
    for (k, evenement) in chrono.enumerated() {
        guard !isRefus(evenement), let date = ResolvedEvent.instant(evenement),
              let lu = entreeDeVoyage(evenement) else { continue }
        let rail = modesFerres.contains(lu.mode)
        let ligne = cleDeLigne(evenement)
        let forfait = estForfait(evenement, contrats)
        // Ce que les portes ou la voie publique disent déjà correspondance est
        // un passage dans le rail : il prolonge le trajet sans compter pour un
        // changement.
        let dejaDite = lu.transition.localizedCaseInsensitiveContains("correspondance")
            || entreeApresCorrespondance(transition: lu.transition, mode: lu.mode, instant: date,
                                         precedents: Array(chrono[..<k].reversed()))
        var prolonge = false
        var change = false
        if let t = trajet, date.timeIntervalSince(t.debut) <= (t.depuisLeRail ? delaiRail : delaiSurface) {
            if dejaDite {
                prolonge = true
            } else if t.forfait, forfait, !(ligne.map { t.lignes.contains($0) } ?? false) {
                if t.dansLeRail && lu.mode == "Train" {
                    prolonge = true
                } else if !(t.dansLeRail && rail) {
                    change = true
                    prolonge = t.changements == 0
                }
            }
        }
        if prolonge {
            if let ligne { trajet?.lignes.insert(ligne) }
            if change { trajet?.changements += 1 }
            trajet?.dansLeRail = rail
        } else {
            trajet = (debut: date, depuisLeRail: rail, forfait: forfait, lignes: Set([ligne].compactMap { $0 }),
                      changements: 0, dansLeRail: rail)
        }
        prolongee = prolonge && !dejaDite
    }
    return prolongee
}

/// Le mode et la transition d'une entrée en voyage — métro, RER, train, bus,
/// tram ou câble —, rien pour le reste.
private func entreeDeVoyage(_ evenement: [String: Any]) -> (mode: String, transition: String)? {
    let lu = lecture(evenement)
    guard lu.transition.hasPrefix("Entrée") || lu.transition == "Validation",
          modesFerres.contains(lu.mode) || modesSurface.contains(lu.mode) else { return nil }
    return lu
}

/// L'exploitant et la course, pour reconnaître une ligne reprise. Rien quand la
/// carte ne les écrit pas, comme aux portes SNCF.
private func cleDeLigne(_ evenement: [String: Any]) -> String? {
    guard let course = getKey(evenement, "EventRouteNumber").flatMap({ Int($0, radix: 2) }),
          let exploitant = getKey(evenement, "EventServiceProvider").flatMap({ Int($0, radix: 2) }) else { return nil }
    return "\(exploitant)|\(course)"
}

/// Le titre payé n'est pas un ticket à l'unité : un forfait, ou Liberté+, qui
/// ne porte pas de compteur. Faute de titre désigné, on ne se prononce pas.
private func estForfait(_ evenement: [String: Any], _ contrats: [[String: Any]]) -> Bool {
    guard let pointeur = getKey(evenement, "EventContractPointer").flatMap({ Int($0, radix: 2) }),
          pointeur > 0, pointeur <= contrats.count else { return false }
    return getKey(contrats[pointeur - 1], "CounterContractCount") == nil
}

/// Le libellé à afficher. Les deux correspondances se disent d'un même mot :
/// sortir d'un réseau pour entrer dans l'autre, c'est le même geste, et c'est
/// l'entrée qui renseigne. Le mode, quand il est connu, permet de nommer celle
/// qui mène au métro. Celle qui passe par la voie publique garde le nom que lui
/// donne Île-de-France Mobilités.
func interpretTransitionLabel(_ transition: String, mode: String? = nil) -> String {
    if let mode, correspondanceVersMetro(transition: transition, mode: mode) {
        return "Correspondance vers le métro"
    }
    if transition == correspondanceVoiePublique {
        return transition
    }
    return TransitionKind(transition) == .correspondance ? "Correspondance" : transition
}
