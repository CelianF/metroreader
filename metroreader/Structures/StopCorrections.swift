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

    /// Décode la table et bâtit son index.
    static func prechauffer() {
        _ = index
    }

    /// Les exploitants couverts, et combien d'arrêts pour chacun.
    static var parExploitant: [(providerId: Int, arrets: Int)] {
        var ordre: [Int] = []
        var compte: [Int: Int] = [:]
        for arret in all {
            if compte[arret.provider_id] == nil { ordre.append(arret.provider_id) }
            compte[arret.provider_id, default: 0] += 1
        }
        return ordre.map { ($0, compte[$0] ?? 0) }
    }

    static func find(_ provider: Int, _ location_id: Int, _ mode: String) -> NavigoStationInfo? {
        guard let arret = index[CleReseau(exploitant: provider, numero: location_id, mode: mode)] else { return nil }
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
