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

    /// Une correspondance se peint comme une entrée : le voyage continue.
    var color: Color {
        switch self {
        case .entree, .correspondance: return .blue
        case .sortie:                  return .red
        case .autre:                   return .purple
        }
    }
}


/// Le libellé à afficher. Les deux correspondances se disent d'un même mot :
/// sortir d'un réseau pour entrer dans l'autre, c'est le même geste, et c'est
/// l'entrée qui renseigne.
func interpretTransitionLabel(_ transition: String) -> String {
    TransitionKind(transition) == .correspondance ? "Correspondance" : transition
}
