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

/// Le libellé à afficher. Les deux correspondances se disent d'un même mot :
/// sortir d'un réseau pour entrer dans l'autre, c'est le même geste, et c'est
/// l'entrée qui renseigne. Le mode, quand il est connu, permet de nommer celle
/// qui mène au métro.
func interpretTransitionLabel(_ transition: String, mode: String? = nil) -> String {
    if let mode, correspondanceVersMetro(transition: transition, mode: mode) {
        return "Correspondance vers le métro"
    }
    return TransitionKind(transition) == .correspondance ? "Correspondance" : transition
}
