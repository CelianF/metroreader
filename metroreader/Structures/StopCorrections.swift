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

    /// La ligne, pour un mode qui numérote ses arrêts ligne par ligne : le 15
    /// du T7 n'est pas celui du T1. Absente, l'arrêt vaut pour le réseau.
    let line_id: Int?
    /// Quand l'arrêt a été relevé, sur quelle foi, et pourquoi la table livrée
    /// ne suffisait pas. Seuls les arrêts de ligne les portent.
    let constate: String?
    let fonde_sur: String?
    let raison: String?

    /// Le jour du constat, quand il se laisse lire.
    var jour: Date? {
        constate.flatMap { formatConstat.date(from: $0) }
    }
}

private let formatConstat: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

/// Un arrêt de ligne : l'exploitant annoncé, la course, le code et le mode.
private struct CleArretDeLigne: Hashable {
    let exploitant: Int
    let course: Int
    let numero: Int
    let mode: String
}


public class StopCorrections {
    static let all: [ShippedStop] = DonneesLivrees.charger("StopCorrections", comme: [ShippedStop].self) ?? []

    private static let index: [CleReseau: ShippedStop] = {
        Dictionary(all.filter { $0.line_id == nil }
                       .map { (CleReseau(exploitant: $0.provider_id, numero: $0.location_id, mode: $0.mode), $0) },
                   uniquingKeysWith: { first, _ in first })
    }()

    /// Les arrêts redressés sur une ligne : le T7, dont la table livrée tient un
    /// bloc saisi à la main où des codes manquaient ou portaient le nom du
    /// voisin.
    static let deLigne: [ShippedStop] = all.filter { $0.line_id != nil }

    private static let indexDeLigne: [CleArretDeLigne: ShippedStop] = {
        Dictionary(deLigne.map { (CleArretDeLigne(exploitant: $0.provider_id, course: $0.line_id ?? 0,
                                                  numero: $0.location_id, mode: $0.mode), $0) },
                   uniquingKeysWith: { first, _ in first })
    }()

    /// Les lignes redressées, et leurs arrêts, dans l'ordre du fichier.
    static var parLigne: [(providerId: Int, lineId: Int, mode: String, arrets: [ShippedStop])] {
        var ordre: [CleArretDeLigne] = []
        var arrets: [CleArretDeLigne: [ShippedStop]] = [:]
        for arret in deLigne {
            let cle = CleArretDeLigne(exploitant: arret.provider_id, course: arret.line_id ?? 0, numero: 0, mode: arret.mode)
            if arrets[cle] == nil { ordre.append(cle) }
            arrets[cle, default: []].append(arret)
        }
        return ordre.map { ($0.exploitant, $0.course, $0.mode, arrets[$0] ?? []) }
    }

    /// Décode la table, bâtit son index et trie ce qui reste consultable.
    static func prechauffer() {
        _ = index
        _ = indexDeLigne
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
        all.filter { $0.line_id == nil && !NavigoStations.declare($0.provider_id, $0.location_id, $0.mode) }

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
    ///
    /// Un arrêt de ligne, lui, se cherche sur la course annoncée, sans ce garde :
    /// le code est bien déclaré ailleurs — le 15 est Basilique de Saint-Denis
    /// sur le T1 —, c'est sur cette ligne-ci que la table se trompait.
    static func find(_ provider: Int, _ location_id: Int, _ mode: String, course: Int? = nil) -> NavigoStationInfo? {
        if let course {
            let codes = [location_id] + [NavigoStations.miroirDuSens(provider, course, location_id)].compactMap { $0 }
            for code in codes {
                if let arret = indexDeLigne[CleArretDeLigne(exploitant: provider, course: course, numero: code, mode: mode)] {
                    return NavigoStationInfo(name: arret.name, provider_id: provider, line_id: course,
                                             location_id: code, mode: mode,
                                             lat: arret.lat ?? 0, lon: arret.lon ?? 0, found: true)
                }
            }
        }
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
