//
//  PassCatalog.swift
//  metroreader
//

import Foundation


struct PassCategory: Decodable, Identifiable {
    let folder: String // Nom du dossier dans Assets.xcassets/Pass
    let name: String? // Libellé affiché, le nom du dossier si absent
    let images: [String] // Noms d'assets, dans l'ordre d'affichage

    var id: String { folder }
    var displayName: String { name ?? folder }
}

private struct PassCategoriesFile: Decodable {
    let categories: [PassCategory]
}

public class PassCatalog {
    // L'ordre des catégories et des images vient de PassCategories.json
    static let categories: [PassCategory] = {
        guard let url = Bundle.main.url(forResource: "PassCategories", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode(PassCategoriesFile.self, from: data)
                .categories.filter { !$0.images.isEmpty }
        } catch {
            print("Error loading pass categories: \(error)")
            return []
        }
    }()
}
