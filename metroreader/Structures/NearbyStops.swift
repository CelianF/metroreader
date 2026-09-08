//
//  NearbyStops.swift
//  metroreader
//

import Foundation
import CoreLocation


/// Nom et position de tous les arrêts d'Île-de-France, sans code billettique.
///
/// Sert uniquement à suggérer un nom quand la carte annonce un identifiant que
/// le référentiel ne sait pas résoudre. Comme elle ne dépend pas du code
/// billettique, cette table couvre aussi les réseaux qui n'en ont pas déclaré —
/// ceux, précisément, où l'on en a besoin.
struct NearbyStop: Decodable {
    let name: String
    let mode: String
    let lat: Double
    let lon: Double
}

public class NearbyStops {
    static let all: [NearbyStop] = {
        guard let url = Bundle.main.url(forResource: "NearbyStops", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([NearbyStop].self, from: data)
        } catch {
            print("Error loading nearby stops: \(error)")
            return []
        }
    }()

    /// Les arrêts d'un mode autour d'une position, du plus proche au plus
    /// éloigné et dédoublonnés par nom : un même arrêt physique porte autant
    /// d'entrées que d'exploitants qui le desservent.
    static func around(_ position: CLLocationCoordinate2D,
                       mode: String,
                       within radius: CLLocationDistance = 400,
                       limit: Int = 8) -> [(stop: NearbyStop, distance: CLLocationDistance)] {
        var vus = Set<String>()
        return all
            .filter { $0.mode == mode }
            .map { (stop: $0, distance: position.distance(toLatitude: $0.lat, longitude: $0.lon)) }
            .filter { $0.distance < radius }
            .sorted { $0.distance < $1.distance }
            .filter { vus.insert($0.stop.name).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// Le plus proche, tout simplement.
    static func nearest(_ position: CLLocationCoordinate2D,
                        mode: String,
                        within radius: CLLocationDistance = 400) -> (stop: NearbyStop, distance: CLLocationDistance)? {
        around(position, mode: mode, within: radius, limit: 1).first
    }
}
