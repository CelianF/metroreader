//
//  JournalNFC.swift
//  metroreader
//

import Foundation

/// Ce qui s'est dit avec la carte à la dernière lecture : les commandes, les
/// réponses et leur mot d'état, les étapes et la fin de la session. Gardé en
/// mémoire jusqu'à la lecture suivante, jamais écrit ni exporté ; le mode debug
/// le montre, pour comprendre une lecture ratée.
///
/// Les lignes arrivent de la file de la session comme de la tâche de lecture :
/// chacune est datée à l'appel, puis rangée sur le fil principal, dans l'ordre.
final class JournalNFC: ObservableObject {
    static let shared = JournalNFC()

    enum Sorte {
        case etape, commande, reponse, erreur
    }

    struct Ligne: Identifiable {
        let id = UUID()
        let instant: Date
        let sorte: Sorte
        let texte: String
    }

    @Published private(set) var lignes: [Ligne] = []

    /// Une lecture commence : le journal de la précédente s'efface.
    func commencer() {
        let ouverture = Ligne(instant: Date(), sorte: .etape, texte: "Session ouverte")
        DispatchQueue.main.async { self.lignes = [ouverture] }
    }

    func noter(_ sorte: Sorte, _ texte: String) {
        let ligne = Ligne(instant: Date(), sorte: sorte, texte: texte)
        DispatchQueue.main.async { self.lignes.append(ligne) }
    }

    /// Le journal en texte, pour le copier.
    var texte: String {
        guard let debut = lignes.first?.instant else { return "" }
        return lignes
            .map { "+\(Self.millisecondes($0.instant, depuis: debut)) ms \(Self.marque($0.sorte)) \($0.texte)" }
            .joined(separator: "\n")
    }

    static func millisecondes(_ instant: Date, depuis debut: Date) -> Int {
        Int((instant.timeIntervalSince(debut) * 1000).rounded())
    }

    static func marque(_ sorte: Sorte) -> String {
        switch sorte {
        case .etape:    return "·"
        case .commande: return "→"
        case .reponse:  return "←"
        case .erreur:   return "✕"
        }
    }
}

/// Des octets en hexadécimal, deux chiffres chacun, séparés d'une espace.
func hexadecimalDesOctets(_ octets: Data) -> String {
    octets.map { String(format: "%02X", $0) }.joined(separator: " ")
}
