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

    /// L'entrée ouvre le voyage en vert pâle, la sortie le clôt en bleu. Une
    /// correspondance n'est ni l'une ni l'autre : le voyage continue, mais
    /// ailleurs, et elle se peint du cyan. Le rouge reste à ce qui arrête, les
    /// refus.
    var color: Color {
        switch self {
        case .entree:         return .vertPale
        case .correspondance: return .cyan
        case .sortie:         return .blue
        case .refus:          return .red
        case .autre:          return .purple
        }
    }
}


extension Color {
    /// L'entrée : un vert adouci, qui ne se confond pas avec le vert franc d'un
    /// titre valable dans l'encart Contrôle.
    static let vertPale = Color(red: 0.49, green: 0.80, blue: 0.53)
}

/// Ce qu'une validation refusée raconte : rien n'a été franchi, quoi que la
/// borne ait tenté d'écrire. Elle se peint du rouge de ce qui arrête.
let transitionRefus = "Refus"


/// Une correspondance qui fait entrer dans le métro.
///
/// Quitter le RER à Gare de Lyon ou à Denfert-Rochereau pour prendre le métro
/// s'inscrit « Sortie (correspondance) » : la borne dit qu'on quitte son
/// réseau, pas où l'on va. Mais l'autre sens — le métro vers le RER — s'écrit
/// « Entrée (correspondance) » sur cette même borne : la sortie, elle, ne peut
/// mener qu'au métro.
func correspondanceVersMetro(transition: String, mode: String) -> Bool {
    // Le métro en est exclu à dessein : à Denfert-Rochereau comme à Gare de
    // Lyon, c'est la borne du RER qui écrit le passage dans les deux sens,
    // jamais celle du métro. Le funiculaire, que la carte écrit en métro, aussi.
    guard transition == "Sortie (correspondance)", let rail = ModeTransport(rawValue: mode) else { return false }
    return rail.estFerre && rail != .metro && rail != .funiculaire
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
private func ferre(_ mode: String) -> Bool {
    ModeTransport(rawValue: mode)?.estFerre ?? false
}

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
func sortieVersCorrespondance(_ lue: LectureValidation, suivants: some Collection<LectureValidation>) -> Bool {
    guard lue.brute == "Sortie (voie publique)", let instant = lue.instant else { return false }
    return suivants.contains { suivant in
        guard let date = suivant.instant else { return false }
        let ecart = date.timeIntervalSince(instant)
        return ecart >= 0 && ecart <= delaiCorrespondance && estEntreeFerree(suivant.mode, suivant.transition)
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
func entreeApresCorrespondance(transition: String, mode: String, instant: Date?,
                               precedents: some Collection<LectureValidation>) -> Bool {
    guard let instant, estEntreeFerree(mode, transition) else { return false }
    for precedent in precedents {
        guard let date = precedent.instant,
              instant.timeIntervalSince(date) <= delaiCorrespondance else { return false }
        if precedent.transition == "Sortie (voie publique)" { return true }
        if estEntreeFerree(precedent.mode, precedent.transition) { return false }
    }
    return false
}

private func estEntreeFerree(_ mode: String, _ transition: String) -> Bool {
    ferre(mode) && (transition.hasPrefix("Entrée") || transition == "Validation")
}

/// Les modes de surface, ceux du ticket Bus-Tram.
private func surface(_ mode: String) -> Bool {
    ModeTransport(rawValue: mode)?.estSurface ?? false
}

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
func entreeDansLeDelai(_ lue: LectureValidation, precedents: some Collection<LectureValidation>) -> Bool {
    guard !lue.refus, entreeDeVoyage(lue), let instant = lue.instant else { return false }

    // Deux validations séparées de plus de 2 h ne tiennent dans aucun trajet :
    // on ne remonte pas au-delà du premier écart de cette taille.
    var fenetre = [lue]
    var plusRecente = instant
    for precedent in precedents {
        guard let date = precedent.instant,
              plusRecente.timeIntervalSince(date) <= delaiRail else { break }
        fenetre.append(precedent)
        plusRecente = date
    }

    // Puis on rejoue les entrées dans l'ordre, trajet par trajet. La dernière
    // est celle qu'on juge.
    let chrono = Array(fenetre.reversed())
    var trajet: (debut: Date, depuisLeRail: Bool, forfait: Bool, lignes: Set<LigneEmpruntee>,
                 changements: Int, dansLeRail: Bool)?
    var prolongee = false
    for (k, evenement) in chrono.enumerated() {
        guard !evenement.refus, let date = evenement.instant, entreeDeVoyage(evenement) else { continue }
        let rail = ferre(evenement.mode)
        let ligne = evenement.ligne
        // Ce que les portes ou la voie publique disent déjà correspondance est
        // un passage dans le rail : il prolonge le trajet sans compter pour un
        // changement.
        let dejaDite = evenement.transition.localizedCaseInsensitiveContains("correspondance")
            || entreeApresCorrespondance(transition: evenement.transition, mode: evenement.mode, instant: date,
                                         precedents: chrono[..<k].reversed())
        var prolonge = false
        var change = false
        if let t = trajet, date.timeIntervalSince(t.debut) <= (t.depuisLeRail ? delaiRail : delaiSurface) {
            if dejaDite {
                prolonge = true
            } else if t.forfait, evenement.forfait, !(ligne.map { t.lignes.contains($0) } ?? false) {
                if t.dansLeRail && ModeTransport(rawValue: evenement.mode) == .train {
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
            trajet = (debut: date, depuisLeRail: rail, forfait: evenement.forfait,
                      lignes: Set([ligne].compactMap { $0 }), changements: 0, dansLeRail: rail)
        }
        prolongee = prolonge && !dejaDite
    }
    return prolongee
}

/// Une entrée en voyage — métro, RER, train, bus, tram ou câble.
private func entreeDeVoyage(_ lue: LectureValidation) -> Bool {
    (lue.transition.hasPrefix("Entrée") || lue.transition == "Validation")
        && (ferre(lue.mode) || surface(lue.mode))
}

/// La transition telle que le trajet la raconte, et non telle que la borne l'a
/// écrite. Un refus n'a rien franchi. Une porte relevée tranche d'elle-même ;
/// ailleurs, la sortie « voie publique » et l'entrée qui la suit se
/// reconnaissent l'une l'autre ; sous forfait enfin, une entrée dans le délai
/// d'un trajet le prolonge.
///
/// Les pastilles et le rangement de l'historique en trajets s'en remettent
/// tous deux à elle : une validation ne peut pas se peindre en correspondance
/// et ouvrir un trajet à la fois.
func transitionRacontee(_ lue: LectureValidation, suivants: some Collection<LectureValidation>,
                        precedents: some Collection<LectureValidation>) -> String {
    if lue.refus { return transitionRefus }
    if lue.transition != lue.brute { return lue.transition }
    if sortieVersCorrespondance(lue, suivants: suivants)
        || entreeApresCorrespondance(transition: lue.brute, mode: lue.mode, instant: lue.instant, precedents: precedents) {
        return correspondanceVoiePublique
    }
    if entreeDansLeDelai(lue, precedents: precedents) {
        return "Entrée (correspondance)"
    }
    return lue.brute
}

/// Le libellé à afficher. Les deux correspondances se disent d'un même mot :
/// sortir d'un réseau pour entrer dans l'autre, c'est le même geste, et c'est
/// l'entrée qui renseigne. Le mode, quand il est connu, permet de nommer celle
/// qui mène au métro. Celle qui passe par la voie publique garde le nom que lui
/// donne Île-de-France Mobilités.
func interpretTransitionLabel(_ transition: String, mode: String? = nil) -> String {
    // Sans correspondances déduites, le libellé du valideur, tel quel.
    if transitionsBrutes { return transition }
    if let mode, correspondanceVersMetro(transition: transition, mode: mode) {
        return "Correspondance vers le métro"
    }
    if transition == correspondanceVoiePublique {
        return transition
    }
    return TransitionKind(transition) == .correspondance ? "Correspondance" : transition
}
