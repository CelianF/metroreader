//
//  GateCorrections.swift
//  metroreader
//

import Foundation


/// Les lignes de contrôle SNCF qui donnent directement sur le métro.
///
/// Dans les gares de la liste IDFM des correspondances par la voie publique,
/// la SNCF écrit « Entrée » ou « Sortie (voie publique) » à toutes ses portes,
/// qu'elles rendent à la rue ou au quai du métro. Derrière une porte qui mène
/// au métro, rien ne s'écrit : on y entre sans revalider, et la sortie se lit
/// comme une vraie faute de validation qui la suive.
///
/// Seul le numéro de porte les distingue. Il vaut pour toute la ligne de
/// valideurs — un valideur hors service le jour du relevé est couvert — et ne
/// se publie nulle part : il se relève sur le terrain. À ces portes, entrer et
/// sortir sont une correspondance, comme aux portes RATP qui écrivent 6 et 7.
struct ShippedGate: Decodable, Identifiable {
    /// Ce que la carte annonce
    let provider_id: Int
    let location_id: Int
    let gate: Int

    /// Quand la porte a été relevée, et sur quelle foi
    let constate: String?
    let raison: String?
    let fonde_sur: String?

    var id: String { "\(provider_id)|\(location_id)|\(gate)" }
}


public class GateCorrections {
    static let all: [ShippedGate] = {
        guard let url = Bundle.main.url(forResource: "GateCorrections", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ShippedGate].self, from: data)
        } catch {
            print("Error loading gate corrections: \(error)")
            return []
        }
    }()

    private static let index: Set<String> = Set(all.map(\.id))

    /// Vrai quand la validation a franchi une de ces portes.
    static func contains(_ eventInfo: [String: Any]) -> Bool {
        guard let provider = entier(eventInfo, "EventServiceProvider"),
              let location = entier(eventInfo, "EventLocationId"),
              let gate = entier(eventInfo, "EventLocationGate") else { return false }
        return index.contains("\(provider)|\(location)|\(gate)")
    }

    /// La porte d'un refus sans titre, quand elle est relevée.
    ///
    /// Faute de titre, la borne SNCF écrit un enregistrement abrégé : exploitant
    /// 5, pas de champ porte, et l'octet bas du code de lieu porte le numéro de
    /// porte au lieu de la gare — 0x6412 pour la porte 18 de Gare du Nord
    /// (0x6411), 0x641E pour la porte 30 de Magenta (0x6416). Les quatre refus
    /// d'une carte Easy vide, relevés le 11/09/2026, le montrent : l'octet bas
    /// de leur numéro de valideur est celui d'un valideur SNCF de la même porte.
    static func porteDuRefus(_ eventInfo: [String: Any]) -> ShippedGate? {
        guard isRefusSansTitre(eventInfo),
              entier(eventInfo, "EventServiceProvider") == 5,
              let location = entier(eventInfo, "EventLocationId") else { return nil }
        return all.first {
            $0.provider_id == 2 && $0.location_id >> 8 == location >> 8 && $0.gate == location & 0xFF
        }
    }

    /// La gare de la porte, telle que le référentiel la nomme.
    static func station(_ porte: ShippedGate) -> NavigoStationInfo? {
        NavigoStations.find(porte.provider_id, nil, porte.location_id, "Train")
    }

    private static func entier(_ eventInfo: [String: Any], _ cle: String) -> Int? {
        getKey(eventInfo, cle).flatMap { Int($0, radix: 2) }
    }
}
