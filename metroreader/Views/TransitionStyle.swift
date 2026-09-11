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
    case autre

    init(_ transition: String) {
        if transition.localizedCaseInsensitiveContains("correspondance") {
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
    /// bleu de l'entrée sans s'y confondre, et loin du rouge qui arrête.
    var color: Color {
        switch self {
        case .entree:         return .blue
        case .correspondance: return .cyan
        case .sortie:         return .red
        case .autre:          return .purple
        }
    }
}


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
/// L'entrée de ces mêmes gares s'écrit « Entrée (voie publique) ». Souvent
/// première validation du trajet, elle reste une entrée.
func sortieVersCorrespondance(transition: String, instant: Date?, suivants: [[String: Any]]) -> Bool {
    guard transition == "Sortie (voie publique)", let instant else { return false }
    return suivants.contains { suivant in
        guard let date = ResolvedEvent.instant(suivant) else { return false }
        let ecart = date.timeIntervalSince(instant)
        guard ecart >= 0, ecart <= delaiCorrespondance else { return false }
        let route = getKey(suivant, "EventRouteNumber").flatMap { Int($0, radix: 2) }
        let provider = getKey(suivant, "EventServiceProvider").flatMap { Int($0, radix: 2) }
        let (mode, entree) = interpretEventCode(getKey(suivant, "EventCode") ?? "",
                                                isRouteNumberPresent: route != nil,
                                                routeNumber: route,
                                                serviceProvider: provider)
        return modesFerres.contains(mode) && (entree.hasPrefix("Entrée") || entree == "Validation")
    }
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
