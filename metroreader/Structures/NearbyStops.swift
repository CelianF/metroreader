//
//  NearbyStops.swift
//  metroreader
//

import Foundation


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
}
