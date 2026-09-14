//
//  DonneesBrutes.swift
//  metroreader
//

import SwiftUI

/// Le mode debug : sept touches rapprochées sur la version, en bas des
/// Réglages, le débloquent, et sa section apparaît au-dessus d'« À propos ».
enum ModeDebug {
    static let deverrouille = "debugDeverrouille"
    /// Les champs de la carte à côté des textes qui les traduisent — dans les
    /// fiches et l'environnement, pas sur les lignes qu'on touche pour les
    /// ouvrir.
    static let donneesBrutes = "debugDonneesBrutes"
    /// La base où les écrire, gardée quand on les masque.
    static let base = "debugBaseBrute"
    /// Vrai quand « Désactiver les correspondances » est allumé : chaque
    /// validation garde la transition que son valideur a écrite.
    static let transitionsBrutes = "debugTransitionsBrutes"
}

enum BaseBrute: String {
    case hexadecimal, decimal
}

/// Vrai quand le mode debug a éteint les correspondances déduites : chaque
/// validation garde la transition que son valideur a écrite, et les trajets ne
/// se rangent que sur elle. Lu aussi hors du fil principal, par la préparation
/// des voyages.
var transitionsBrutes: Bool {
    UserDefaults.standard.bool(forKey: ModeDebug.transitionsBrutes)
}

private func estBinaire(_ bits: String) -> Bool {
    !bits.isEmpty && bits.allSatisfy { $0 == "0" || $0 == "1" }
}

/// Les bits d'un champ, tels que la carte les écrit, en hexadécimal : complétés
/// à gauche jusqu'au quartet, puis lus quatre par quatre. `Int(_:radix:)` ne
/// passerait pas 63 bits, et un authentifiant ou des données de contrat peuvent
/// les dépasser.
func hexadecimal(_ bits: String) -> String? {
    guard estBinaire(bits) else { return nil }
    let complets = String(repeating: "0", count: (4 - bits.count % 4) % 4) + bits
    var chiffres = ""
    var quartet = 0
    for (i, bit) in complets.enumerated() {
        quartet = quartet << 1 | (bit == "1" ? 1 : 0)
        if i % 4 == 3 {
            chiffres.append(String(quartet, radix: 16, uppercase: true))
            quartet = 0
        }
    }
    return "0x" + chiffres
}

/// Les bits d'un champ en décimal. Au-delà de 64 bits, qu'aucun champ affiché
/// n'approche, l'hexadécimal prend le relais : lui ne déborde pas.
func decimal(_ bits: String) -> String? {
    guard estBinaire(bits) else { return nil }
    guard let valeur = UInt64(bits, radix: 2) else { return hexadecimal(bits) }
    return String(valeur)
}

/// Les champs dans la base demandée, en petit ; rien quand aucun n'est sur la
/// carte.
func texteBrut(_ champs: [String?], en base: BaseBrute) -> Text? {
    let valeurs = champs.compactMap { champ in
        champ.flatMap { base == .hexadecimal ? hexadecimal($0) : decimal($0) }
    }
    guard !valeurs.isEmpty else { return nil }
    return Text(valeurs.joined(separator: " "))
        .font(.caption.monospaced())
        .foregroundColor(.secondary)
}

extension Text {
    /// Ce texte, suivi en petit des champs qu'il traduit quand le mode debug le
    /// demande : `base` dit alors en quelle base, et vaut nil sinon. À poser
    /// juste après le `Text` : la police et la couleur données ensuite habillent
    /// la traduction, le brut garde les siennes.
    func brut(_ champs: String?..., si base: BaseBrute?) -> Text {
        guard let base, let brut = texteBrut(champs, en: base) else { return self }
        return Text("\(self) \(brut)")
    }
}
