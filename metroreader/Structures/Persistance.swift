//
//  Persistance.swift
//  metroreader
//

import Foundation


/// Les fichiers que l'app tient dans Documents : l'historique et les saisies.
///
/// Deux règles, apprises à leurs dépens. Un fichier qu'on ne sait pas relire
/// n'est jamais écrasé : il est copié à côté avant que la prochaine écriture le
/// remplace — au Build 36, un champ ajouté à `ScanRecord` rendait l'ancien
/// historique illisible, et le scan suivant l'effaçait. Et une écriture se fait
/// d'un seul tenant : l'app tuée en pleine écriture laissait un fichier tronqué,
/// donc illisible, donc perdu au scan d'après.
///
/// Les écritures partent sur une file à part, dans l'ordre où on les demande :
/// encoder tout l'historique sur le fil principal saccadait les listes.
enum Persistance {

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static let file = DispatchQueue(label: "Persistance", qos: .utility)

    /// Ce qu'un fichier a rendu, et s'il est permis de l'écraser.
    struct Lecture<T> {
        let valeurs: [T]
        /// Faux quand le fichier existe mais n'a pu être ni lu en entier ni mis
        /// de côté : l'écraser détruirait ce qu'il est seul à contenir.
        let ecrasable: Bool
    }

    /// Lit un tableau enregistré, élément par élément : un élément illisible
    /// n'emporte pas les autres, mais fait mettre le fichier de côté.
    static func lire<T: Decodable>(_ url: URL, decodeur: JSONDecoder = JSONDecoder()) -> Lecture<T> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Lecture(valeurs: [], ecrasable: true)
        }
        guard let data = try? Data(contentsOf: url),
              let lus = try? decodeur.decode([Tolerant<T>].self, from: data) else {
            return Lecture(valeurs: [], ecrasable: mettreDeCote(url))
        }
        let valeurs = lus.compactMap(\.valeur)
        guard valeurs.count < lus.count else {
            return Lecture(valeurs: valeurs, ecrasable: true)
        }
        return Lecture(valeurs: valeurs, ecrasable: mettreDeCote(url))
    }

    /// Écrit un tableau, hors du fil principal et d'un seul tenant.
    static func ecrire<T: Encodable>(_ valeurs: [T], vers url: URL, encodeur: JSONEncoder = JSONEncoder()) {
        file.async {
            guard let data = try? encodeur.encode(valeurs) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func effacer(_ url: URL) {
        file.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Attend que les écritures demandées soient faites : avant que l'app passe
    /// en arrière-plan, où elle peut être suspendue sans préavis.
    static func attendre() {
        file.sync {}
    }

    /// Copie le fichier à côté de lui, horodaté. Vrai si la copie existe.
    private static func mettreDeCote(_ url: URL) -> Bool {
        let horodatage = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let copie = url.deletingPathExtension()
            .appendingPathExtension("illisible-\(horodatage)")
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: copie)
            return true
        } catch {
            print("Impossible de mettre \(url.lastPathComponent) de côté : \(error.localizedDescription)")
            return false
        }
    }
}


/// Un élément qu'on tente de décoder sans faire échouer le tableau qui le porte.
private struct Tolerant<T: Decodable>: Decodable {
    let valeur: T?

    init(from decoder: Decoder) throws {
        valeur = try? T(from: decoder)
    }
}
