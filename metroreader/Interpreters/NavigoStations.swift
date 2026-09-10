//
//  NavigoStations.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import Foundation


public struct NavigoStationInfo: Codable {
    let name: String
    let provider_id: Int
    let line_id: Int?
    let location_id: Int
    let mode: String
    let lat: Double
    let lon: Double
    let lines: [NavigoLineInfo]
    let found: Bool
    
    enum CodingKeys: String, CodingKey {
        case name, provider_id, line_id, location_id, mode, lat, lon, lines
        // omit 'found' if it's not in the JSON file
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.provider_id = try container.decode(Int.self, forKey: .provider_id)
        self.line_id = try container.decodeIfPresent(Int.self, forKey: .line_id)
        self.location_id = try container.decode(Int.self, forKey: .location_id)
        self.mode = try container.decode(String.self, forKey: .mode)
        self.lat = try container.decode(Double.self, forKey: .lat)
        self.lon = try container.decode(Double.self, forKey: .lon)
        self.lines = try container.decode([NavigoLineInfo].self, forKey: .lines)
        
        // Default to true when decoding from JSON
        self.found = true
    }
    
    init(name: String, provider_id: Int, line_id: Int?, location_id: Int, mode: String, lat: Double, lon: Double) {
        self.name = name
        self.provider_id = provider_id
        self.line_id = line_id
        self.location_id = location_id
        self.mode = mode
        self.lat = lat
        self.lon = lon
        self.lines = []
        self.found = true
    }
    
    init(name: String, provider_id: Int, line_id: Int?, location_id: Int, mode: String, lat: Double, lon: Double, lines: [NavigoLineInfo], found: Bool) {
        self.name = name
        self.provider_id = provider_id
        self.line_id = line_id
        self.location_id = location_id
        self.mode = mode
        self.lat = lat
        self.lon = lon
        self.lines = lines
        self.found = found
    }

    /// Un arrêt identifié à la main peut n'avoir aucune coordonnée : on connaît
    /// son nom mais rien à placer sur une carte.
    var isLocatable: Bool { found && (lat != 0 || lon != 0) }

    init(name: String, provider_id: Int, line_id: Int?, location_id: Int, mode: String, lat: Double, lon: Double, found: Bool) {
        self.name = name
        self.provider_id = provider_id
        self.line_id = line_id
        self.location_id = location_id
        self.mode = mode
        self.lat = lat
        self.lon = lon
        self.lines = []
        self.found = found
    }
}

public class NavigoStations {
    public static let allStations: [NavigoStationInfo] = {
        guard let url = Bundle.main.url(forResource: "NavigoStations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([NavigoStationInfo].self, from: data)
        } catch {
            print("Error loading Navigo data: \(error)")
            return []
        }
    }()
    
    public class func find(_ provider_id: Int, _ line_id: Int?, _ location_id: Int, _ mode: String) -> NavigoStationInfo? {
        var modeToUse = mode
        if (mode == "RER") {
            modeToUse = "Train"
        }
        if (provider_id == 2) { // Map SNCF Provider
            if let station = allStations.first(where: { $0.provider_id == 1 && $0.line_id == line_id && $0.location_id == location_id && $0.mode == modeToUse }) {
                return station
            }
            else {
                return allStations.first(where: { $0.provider_id == 1 && $0.location_id == location_id && $0.mode == modeToUse })
            }
        }
        else if (provider_id == 3) { // Map RATP Provider
            if let station = allStations.first(where: { $0.provider_id == 59 && $0.line_id == line_id && $0.location_id == location_id && $0.mode == modeToUse }) {
                return station
            }
            else if line_id == 17, let station = allStations.first(where: { $0.provider_id == 59 && $0.line_id == 17 && $0.location_id == (location_id ^ 0x8000) && $0.mode == modeToUse }) {
                return station
            }
            else if let station = allStations.first(where: { $0.provider_id == 59 && $0.location_id == location_id && $0.mode == modeToUse }) {
                return station
            }
            // Le référentiel range la RATP sous deux exploitants : 59 pour le
            // métro, le tram et le train, 3 pour ses lignes de bus. La
            // recherche ne consultait que le premier, si bien que les neuf
            // mille arrêts de bus n'étaient jamais atteints — une validation
            // sur un bus RATP n'affichait qu'un nombre.
            return allStations.first { $0.provider_id == 3 && $0.location_id == location_id && $0.mode == modeToUse }
        }
        if let station = allStations.first(where: { $0.provider_id == provider_id && $0.line_id == line_id && $0.location_id == location_id && $0.mode == modeToUse }) {
            return station
        }
        // Pas de repli sans l'exploitant. Les identifiants d'arrêt sont locaux à
        // chaque réseau et massivement recyclés — le 161 est déclaré par vingt
        // exploitants — donc chercher sans lui renvoie le premier venu dans
        // l'ordre du fichier, soit un arrêt à l'autre bout de la région annoncé
        // comme une certitude. Mieux vaut rendre l'identifiant brut.
        return allStations.first(where: { $0.provider_id == provider_id && $0.location_id == location_id && $0.mode == modeToUse })
    }
}
