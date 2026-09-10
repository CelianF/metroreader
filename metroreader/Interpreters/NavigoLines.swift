//
//  NavigoStations.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import Foundation

public struct NavigoLineInfo: Codable {
    let name: String
    var mode: String
    let direction: String?
    let public_id: String
    let provider_id: Int?
    let line_id: Int?
    let background_color: String
    let text_color: String
    let is_noctilien: Bool
    /// Faux quand la ligne n'a pas été trouvée et qu'on affiche le numéro de
    /// course brut. Absent du JSON : ce qui vient du référentiel est trouvé.
    let found: Bool
    
    enum CodingKeys: String, CodingKey {
        case name, mode, direction, public_id, provider_id, line_id, background_color, text_color, is_noctilien
        // omit 'found' if it's not in the JSON file
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.mode = try container.decode(String.self, forKey: .mode)
        self.direction = try container.decodeIfPresent(String.self, forKey: .direction)
        self.public_id = try container.decode(String.self, forKey: .public_id)
        self.provider_id = try container.decodeIfPresent(Int.self, forKey: .provider_id)
        self.line_id = try container.decodeIfPresent(Int.self, forKey: .line_id)
        self.background_color = try container.decode(String.self, forKey: .background_color)
        self.text_color = try container.decode(String.self, forKey: .text_color)
        self.is_noctilien = try container.decodeIfPresent(Bool.self, forKey: .is_noctilien) ?? false
        self.found = true
    }
    
    init(name: String, mode: String, direction: String? = nil, public_id: String, provider_id: Int?, line_id: Int?, background_color: String, text_color: String, is_noctilien: Bool = false, found: Bool = true) {
        self.name = name
        self.mode = mode
        self.direction = direction
        self.public_id = public_id
        self.provider_id = provider_id
        self.line_id = line_id
        self.background_color = background_color
        self.text_color = text_color
        self.is_noctilien = is_noctilien
        self.found = found
    }
}

public class NavigoLines {
    public static let allLines: [NavigoLineInfo] = {
        guard let url = Bundle.main.url(forResource: "NavigoLines", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([NavigoLineInfo].self, from: data)
        } catch {
            print("Error loading Navigo data: \(error)")
            return []
        }
    }()

    public class func find(_ provider: Int, _ line_id: Int, _ mode: String) -> NavigoLineInfo? {
        candidates(provider, line_id, mode).first
    }

    /// Toutes les lignes qui répondent à ce numéro de course, dédoublonnées.
    ///
    /// Une seule, presque toujours. Mais le référentiel donne parfois le même
    /// `privatecode` à plusieurs lignes — cinquante codes pour cent dix-neuf
    /// lignes, dont « 5412 » et « 5413 » sur le Mantois, ou « 7820 », « 7823 »
    /// et « 7825 » — et ce code est le seul pont entre la carte et le
    /// référentiel. Rien n'y départage les prétendantes : rendre la première
    /// venue, c'était présenter un tirage au sort comme une certitude.
    public class func candidates(_ provider: Int, _ line_id: Int, _ mode: String) -> [NavigoLineInfo] {
        let siennes = chez(provider, line_id, mode)
        if !siennes.isEmpty { return siennes }
        // Les délégations « RATP Cap » n'ont pas redéclaré leurs lignes : le
        // référentiel les garde sous la RATP, avec le même numéro.
        guard ProviderCatalog.isRATPDelegation(provider) else { return [] }
        return chez(ProviderCatalog.ratpId, line_id, mode)
    }

    /// La course est annoncée brute chez les uns, logée dans l'octet haut chez
    /// les autres. À chacun des deux niveaux, une correction livrée tranche
    /// avant le référentiel : c'est précisément lui qu'elle redresse.
    private class func chez(_ provider: Int, _ line_id: Int, _ mode: String) -> [NavigoLineInfo] {
        for course in [line_id, line_id >> 8] {
            if let corrigee = LineCorrections.corrected(provider, course, mode, parmi: allLines) {
                return [corrigee]
            }
            let trouvees = distinctes { $0.provider_id == provider && $0.line_id == course && $0.mode == mode }
            if !trouvees.isEmpty { return trouvees }
        }
        return []
    }

    /// Une même ligne figure sous plusieurs numéros de course : on ne la compte
    /// qu'une fois, sans quoi la moindre recherche paraîtrait ambiguë.
    private class func distinctes(_ retenir: (NavigoLineInfo) -> Bool) -> [NavigoLineInfo] {
        var vues = Set<String>()
        return allLines.filter { retenir($0) && vues.insert($0.public_id).inserted }
    }
}
