//
//  StopCorrections.swift
//  metroreader
//

import Foundation


/// Les arrêts qu'un exploitant nous a communiqués faute de les avoir déclarés
/// au référentiel.
///
/// Treize réseaux en délégation n'ont jamais renseigné le code billettique de
/// leurs arrêts : le référentiel y recopie l'identifiant technique à huit
/// chiffres, quand la carte en écrit deux à quatre. Leurs validations restent
/// donc anonymes, un nombre et rien d'autre.
///
/// Ce que l'exploitant transmet directement comble ce trou. C'est de la donnée
/// livrée, pas du journal : elle se lit dans les Réglages mais ne s'y modifie
/// pas, et les saisies de l'utilisateur passent devant.
///
/// La table sert aussi de coffre : elle garde une copie des arrêts de bus RATP
/// qu'IDFM ne publie plus, pour qu'une régénération du référentiel ne les
/// perde pas. Cette copie-là ne se consulte pas — voir `consultables`.
struct ShippedStop: Decodable {
    let provider_id: Int
    let location_id: Int
    let mode: String
    let name: String
    /// Absentes quand le nom n'a pas pu être rapproché du référentiel sans
    /// ambiguïté. L'arrêt s'affiche alors sans être placé sur la carte.
    let lat: Double?
    let lon: Double?
}


public class StopCorrections {
    static let all: [ShippedStop] = DonneesLivrees.charger("StopCorrections", comme: [ShippedStop].self) ?? []

    private static let index: [CleReseau: ShippedStop] = {
        Dictionary(all.map { (CleReseau(exploitant: $0.provider_id, numero: $0.location_id, mode: $0.mode), $0) },
                   uniquingKeysWith: { first, _ in first })
    }()

    /// Décode la table, bâtit son index et trie ce qui reste consultable.
    static func prechauffer() {
        _ = index
        _ = consultables
    }

    /// Celles que l'app peut encore rendre : les arrêts dont le référentiel ne
    /// déclare pas le code.
    ///
    /// Les deux tiers de la table en sont la copie conforme — les arrêts de bus
    /// RATP qu'IDFM ne publie plus, gardés ici pour qu'une régénération du
    /// référentiel ne les perde pas. Utiles à ce titre, ils ne sont jamais lus :
    /// les annoncer dans les Réglages promettait des noms que rien ne va plus
    /// chercher.
    static let consultables: [ShippedStop] =
        all.filter { !NavigoStations.declare($0.provider_id, $0.location_id, $0.mode) }

    /// Les arrêts consultables d'un exploitant.
    static func arrets(exploitant: Int) -> [ShippedStop] {
        consultables.filter { $0.provider_id == exploitant }
    }

    /// Les exploitants couverts, et combien d'arrêts pour chacun.
    static var parExploitant: [(providerId: Int, arrets: Int)] {
        var ordre: [Int] = []
        var compte: [Int: Int] = [:]
        for arret in consultables {
            if compte[arret.provider_id] == nil { ordre.append(arret.provider_id) }
            compte[arret.provider_id, default: 0] += 1
        }
        return ordre.map { ($0, compte[$0] ?? 0) }
    }

    /// Le nom livré pour ce code, quand le référentiel n'en dit rien.
    ///
    /// Une correction livrée comble un trou, elle ne donne pas un second avis.
    /// Les deux tiers d'entre elles recopient un code que le référentiel déclare
    /// déjà, au mot près — ce sont les arrêts de bus RATP qu'IDFM ne publie plus,
    /// mis à l'abri d'une régénération. Consultées quand le référentiel a refusé
    /// de rattacher ce code à la ligne annoncée, elles redonnaient précisément
    /// l'arrêt qu'il venait d'écarter : la 14 s'affichait à Dupleix, à six
    /// kilomètres du TVM.
    static func find(_ provider: Int, _ location_id: Int, _ mode: String) -> NavigoStationInfo? {
        guard !NavigoStations.declare(provider, location_id, mode),
              let arret = index[CleReseau(exploitant: provider, numero: location_id, mode: mode)] else { return nil }
        return NavigoStationInfo(name: arret.name,
                                 provider_id: provider,
                                 line_id: nil,
                                 location_id: location_id,
                                 mode: mode,
                                 lat: arret.lat ?? 0,
                                 lon: arret.lon ?? 0,
                                 found: true)
    }
}
