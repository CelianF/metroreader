//
//  IndicesLignes.swift
//  metroreader
//

import Foundation


/// Les indices de ligne qu'Île-de-France Mobilités publie, livrés dans
/// Assets.xcassets › Indices lignes avec leur variante pour fond sombre — sauf
/// Orlyval, d'un seul dessin.
///
/// Leurs noms sont tenus ici plutôt que demandés au catalogue d'images : la
/// liste se relit d'un coup d'œil, et une ligne sans indice se sait sans tenter
/// de charger une image qui n'existe pas.
enum IndicesLignes {
    private static let livres: Set<String> = [
        "indice_metro_1", "indice_metro_2", "indice_metro_3", "indice_metro_3bis",
        "indice_metro_4", "indice_metro_5", "indice_metro_6", "indice_metro_7",
        "indice_metro_7bis", "indice_metro_8", "indice_metro_9", "indice_metro_10",
        "indice_metro_11", "indice_metro_12", "indice_metro_13", "indice_metro_14",
        "indice_metro_15", "indice_metro_16", "indice_metro_17", "indice_metro_18",
        "indice_RER_A", "indice_RER_B", "indice_RER_C", "indice_RER_D", "indice_RER_E",
        "indice_train_H", "indice_train_J", "indice_train_K", "indice_train_L",
        "indice_train_N", "indice_train_P", "indice_train_R", "indice_train_U",
        "indice_train_V",
        "indice_tram_1", "indice_tram_2", "indice_tram_3a", "indice_tram_3b",
        "indice_tram_4", "indice_tram_5", "indice_tram_6", "indice_tram_7",
        "indice_tram_8", "indice_tram_9", "indice_tram_10", "indice_tram_11",
        "indice_tram_12", "indice_tram_13", "indice_tram_14",
        "indice_cable_1",
    ]

    /// Les indices d'une ligne, dans l'ordre où les montrer. Presque toujours un
    /// seul ; deux pour un tronc commun que le référentiel nomme d'un trait,
    /// comme « 16/17 ». Vide quand la ligne n'en a pas — bus, Noctilien, TER,
    /// funiculaire, ou nom saisi autrement qu'IDFM ne l'écrit.
    static func images(nom: String, mode: String?) -> [String] {
        guard let mode = mode.flatMap(ModeTransport.init(rawValue:)) else { return [] }
        // Orlyval n'a pas de numéro : on le reconnaît à son nom, en train au
        // référentiel mais en métro quand la course 29 le désigne. L'ORLYVAL en
        // bus, sans arrêt, reste une pastille.
        if nom.uppercased() == "ORLYVAL" && (mode == .train || mode == .metro) {
            return ["indice_orlyval"]
        }
        let famille: String
        switch mode {
        case .metro:      famille = "metro"
        case .rer:        famille = "RER"
        case .transilien: famille = "train"
        case .tramway:    famille = "tram"
        case .cable:      famille = "cable"
        default:          return []
        }
        let noms = nom.split(separator: "/").map { "indice_\(famille)_\(suffixe(String($0), mode: mode))" }
        return !noms.isEmpty && noms.allSatisfy(livres.contains) ? noms : []
    }

    /// La largeur d'un indice à cette hauteur. Tous sont carrés, sauf Orlyval,
    /// dont le logo s'étire en bandeau de 766 sur 190.
    static func largeur(_ indice: String, hauteur: CGFloat) -> CGFloat {
        indice == "indice_orlyval" ? hauteur * 766 / 190 : hauteur
    }

    /// Le nom de la ligne tel que le fichier l'écrit : « 3B » y est « 3bis »,
    /// « T3a » y est « 3a », « C1 » y est « 1 ».
    private static func suffixe(_ nom: String, mode: ModeTransport) -> String {
        switch mode {
        case .metro where nom.hasSuffix("B"):
            return nom.dropLast() + "bis"
        case .tramway, .cable:
            return String(nom.dropFirst())
        default:
            return nom
        }
    }
}
