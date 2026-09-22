//
//  LineStops.swift
//  metroreader
//

import Foundation
import CoreLocation


/// Les arrêts desservis par chaque ligne, indexés par l'identifiant IDFM de la
/// ligne — celui que NavigoLines appelle public_id.
///
/// Ne dépend pas du code billettique, donc couvre aussi les réseaux qui n'ont
/// pas déclaré le leur. Sert à proposer un nom quand la carte annonce un arrêt
/// que le référentiel ne sait pas résoudre.
struct LineStop: Decodable {
    let name: String
    let lat: Double
    let lon: Double
}

public class LineStops {
    private static let table: [String: [LineStop]] =
        DonneesLivrees.charger("LineStops", comme: [String: [LineStop]].self) ?? [:]

    static func stops(forLine publicId: String?) -> [LineStop] {
        guard let publicId, !publicId.isEmpty else { return [] }
        return table[publicId] ?? []
    }

    /// Décode la table et bâtit l'index des noms comparables.
    static func prechauffer() {
        _ = comparables
    }

    /// La ligne dessert-elle un arrêt de ce nom ?
    ///
    /// Le code qu'écrit un valideur de bus ou de tram est un numéro de séquence
    /// le long de sa ligne : l'arrêt qu'il désigne est forcément dans cette
    /// liste. C'est ce qui permet d'écarter un arrêt que la liste d'un
    /// exploitant, toutes lignes confondues, aurait donné pour ce code.
    static func dessert(_ publicId: String, arret nom: String) -> Bool {
        comparables[publicId]?.contains(comparable(nom)) ?? false
    }

    /// Les noms de chaque ligne, réduits à ce qui permet de les reconnaître.
    /// Normaliser à la volée, c'était replier quatre-vingt mille chaînes à
    /// chaque validation affichée.
    private static let comparables: [String: Set<String>] =
        table.mapValues { Set($0.map { comparable($0.name) }) }

    /// Le nom d'un arrêt réduit à ce qui permet de le reconnaître d'une table du
    /// référentiel à l'autre : la casse, les accents et la ponctuation y varient
    /// — « Route d'Ève » s'y écrit aussi « Route d'Eve », et « Trésor public »
    /// « Trésor Public ».
    private static func comparable(_ nom: String) -> String {
        nom.folding(options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "fr_FR"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Les arrêts de la ligne autour d'une position, du plus proche au plus
    /// éloigné et dédoublonnés par nom.
    ///
    /// Le code lu vient d'un valideur de cette ligne : son arrêt est forcément
    /// dans cette liste. Les arrêts du voisinage, eux, appartiennent à
    /// n'importe quelle ligne passant là — proposer les deux à égalité, c'est
    /// inviter à nommer la validation d'après une ligne qu'on n'a pas prise.
    static func around(_ position: CLLocationCoordinate2D,
                       forLine publicId: String?,
                       within radius: CLLocationDistance = 400,
                       limit: Int = 8) -> [(stop: LineStop, distance: CLLocationDistance)] {
        var vus = Set<String>()
        return stops(forLine: publicId)
            .map { (stop: $0, distance: position.distance(toLatitude: $0.lat, longitude: $0.lon)) }
            .filter { $0.distance < radius }
            .sorted { $0.distance < $1.distance }
            .filter { vus.insert($0.stop.name).inserted }
            .prefix(limit)
            .map { $0 }
    }
}
