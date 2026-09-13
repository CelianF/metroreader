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
    static let categories: [PassCategory] =
        (DonneesLivrees.charger("PassCategories", comme: PassCategoriesFile.self)?.categories ?? [])
            .filter { !$0.images.isEmpty }
}
