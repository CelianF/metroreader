//
//  LineStops.swift
//  metroreader
//

import Foundation


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
}
