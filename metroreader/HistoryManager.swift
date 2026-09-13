//
//  HistoryManager.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//  Edited by Célian Faucille on 10/01/2026.

import Foundation


class HistoryManager: ObservableObject {
    @Published var history: [ScanRecord] = []

    /// Clé du réglage qui autorise l'enregistrement des scans
    static let settingKey = "isHistoryEnabled"

    private let fileURL: URL

    /// Faux quand le fichier existant n'a pu être ni relu ni mis de côté :
    /// l'écraser détruirait ce qu'il est seul à contenir.
    private var ecrasable: Bool

    /// Le fichier n'est un paramètre que pour les essais : l'app n'en a qu'un.
    init(fileURL: URL = Persistance.documents.appendingPathComponent("history.json")) {
        self.fileURL = fileURL
        let lu: Persistance.Lecture<ScanRecord> = Persistance.lire(fileURL)
        ecrasable = lu.ecrasable
        history = lu.valeurs
    }

    func saveScan(cardID: UInt64, icc: String, env: [String: Any], contracts: [[String: Any]], events: [[String: Any]], specialEvents: [[String: Any]]) {
        guard UserDefaults.standard.bool(forKey: Self.settingKey) else { return }

        // 1. Vérifier si la carte existe déjà (si cardID est présent)
        if let index = history.firstIndex(where: { $0.cardID == cardID }) {

            // --- LOGIQUE DE FUSION ---
            var existingRecord = history[index]

            // Mise à jour des infos de base
            existingRecord.date = Date()
            existingRecord.iccData = icc
            existingRecord.envData = try? JSONSerialization.data(withJSONObject: env)
            existingRecord.contractsData = try? JSONSerialization.data(withJSONObject: contracts)
            existingRecord.eventsData = try? JSONSerialization.data(withJSONObject: Self.fusionner(events, dans: existingRecord.events))
            existingRecord.specialEventsData = try? JSONSerialization.data(withJSONObject: Self.fusionner(specialEvents, dans: existingRecord.specialEvents))

            // Remplacer l'ancien record et le remonter en haut de liste
            history.remove(at: index)
            history.insert(existingRecord, at: 0)

        } else {
            // --- NOUVEAU RECORD ---
            let newRecord = ScanRecord(
                id: UUID(),
                date: Date(),
                nickname: nil,
                imageName: nil,
                cardID: cardID,
                iccData: icc,
                envData: try? JSONSerialization.data(withJSONObject: env),
                contractsData: try? JSONSerialization.data(withJSONObject: contracts),
                eventsData: try? JSONSerialization.data(withJSONObject: events),
                specialEventsData: try? JSONSerialization.data(withJSONObject: specialEvents)
            )
            history.insert(newRecord, at: 0)
        }

        persistToDisk()
    }

    /// Les validations d'un nouveau scan, fondues dans celles qu'on avait. La
    /// carte n'en garde que trois : ce qu'elle a oublié ne vit plus qu'ici. Une
    /// validation relue remplace sa copie, la lecture récente étant au moins
    /// aussi complète.
    private static func fusionner(_ nouveaux: [[String: Any]], dans anciens: [[String: Any]]) -> [[String: Any]] {
        nouveaux + anciens.filter { ancien in !nouveaux.contains { memeValidation($0, ancien) } }
    }

    /// Deux copies d'une même validation : même jour, même minute, même code et
    /// même valideur. Sans le valideur, deux validations de même code passées
    /// dans la même minute à deux bornes n'en faisaient qu'une.
    private static func memeValidation(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        ["EventDateStamp", "EventTimeStamp", "EventCode", "EventDevice"].allSatisfy { getKey(a, $0) == getKey(b, $0) }
    }

    func setNickname(for cardID: UInt64, to name: String) {
        if let index = history.firstIndex(where: { $0.cardID == cardID }) {
            history[index].nickname = name.trimmingCharacters(in: .whitespacesAndNewlines)
            persistToDisk()
        }
    }

    func setImageName(for cardID: UInt64, to imageName: String) {
        if let index = history.firstIndex(where: { $0.cardID == cardID }) {
            history[index].imageName = imageName
            persistToDisk()
        }
    }

    private func persistToDisk() {
        guard ecrasable else { return }
        Persistance.ecrire(history, vers: fileURL)
    }

    /// Retire les fiches désignées, en une seule écriture.
    func supprimer(_ ids: Set<UUID>) {
        history.removeAll { ids.contains($0.id) }
        persistToDisk()
    }

    func clearAll() {
        history = []
        Persistance.effacer(fileURL)
        // Le fichier parti, plus rien à protéger.
        ecrasable = true
    }

    func togglePin(for record: ScanRecord) {
        guard let index = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[index].isPinned.toggle()
        persistToDisk()
    }

    var sortedHistory: [ScanRecord] {
        history.sorted { record1, record2 in
            if record1.isPinned == record2.isPinned {
                return record1.date > record2.date
            }
            return record1.isPinned && !record2.isPinned
        }
    }

    var pinnedRecords: [ScanRecord] {
        history.filter { $0.isPinned }.sorted { $0.date > $1.date }
    }

    var unpinnedRecords: [ScanRecord] {
        history.filter { !$0.isPinned }.sorted { $0.date > $1.date }
    }
}
