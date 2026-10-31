//
//  CorrespondancesVoiePublique.swift
//  metroreader
//

import Foundation


/// Une correspondance par la voie publique, telle qu'Île-de-France Mobilités
/// la liste : les gares qu'elle relie, par le nom que leur donne la table des
/// arrêts.
struct CorrespondanceVoiePublique: Decodable, Identifiable {
    /// Le libellé de la liste IDFM, lignes comprises.
    let nom: String
    let gares: [String]

    var id: String { nom }
}


/// Les vingt-quatre correspondances qu'IDFM autorise hors de la zone contrôlée.
///
/// Partout ailleurs, sortir puis revalider fait payer un second trajet, même
/// sans changer de gare : à Persan - Beaumont, le 25/10, la sortie puis
/// l'entrée de 17:35 sont deux voyages. Dans ces gares-là, on sort d'un réseau
/// pour entrer dans l'autre — le RER à Châtelet les Halles, le métro 4 aux
/// Halles — sans rien payer de plus, dans les 2 h qui suivent la première
/// validation.
///
/// Saint-Lazare y figure trois fois, avec Saint-Augustin, Havre-Caumartin et
/// Auber : chacune se relie à Saint-Lazare, pas aux deux autres.
enum CorrespondancesVoiePublique {
    static let all: [CorrespondanceVoiePublique] =
        DonneesLivrees.charger("CorrespondancesVoiePublique", comme: [CorrespondanceVoiePublique].self) ?? []

    /// Les groupes de chaque gare.
    private static let parGare: [String: [Set<String>]] = {
        var index: [String: [Set<String>]] = [:]
        for correspondance in all {
            let groupe = Set(correspondance.gares)
            for gare in groupe { index[gare, default: []].append(groupe) }
        }
        return index
    }()

    /// Sortir de `sortie` puis entrer à `entree` est-il une correspondance ?
    static func relie(_ sortie: String, _ entree: String) -> Bool {
        parGare[sortie]?.contains { $0.contains(entree) } ?? false
    }
}
