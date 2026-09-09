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
    private static let table: [String: [LineStop]] = {
        guard let url = Bundle.main.url(forResource: "LineStops", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: [LineStop]].self, from: data)
        } catch {
            print("Error loading line stops: \(error)")
            return [:]
        }
    }()

    static func stops(forLine publicId: String?) -> [LineStop] {
        guard let publicId, !publicId.isEmpty else { return [] }
        return table[publicId] ?? []
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
