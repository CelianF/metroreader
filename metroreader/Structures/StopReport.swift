//
//  StopReport.swift
//  metroreader
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers


/// Un arrêt que l'app n'a pas su nommer, et que l'utilisateur a identifié.
///
/// Treize délégations n'ont pas déclaré leurs codes billettiques au référentiel
/// IDFM : leurs arrêts existent avec nom et coordonnées, mais sont indexés sur
/// un identifiant que les cartes ne portent pas. Le journal recueille les
/// correspondances constatées sur le terrain, en attendant que la source soit
/// corrigée en amont.
struct StopReport: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date

    // Ce que la carte annonce
    let providerId: Int
    let locationId: Int
    let mode: String
    var routeNumber: Int?
    var lineName: String?

    // Ce que l'utilisateur a identifié
    var stationName: String
    var referenceId: Int? // identifiant IDFM de l'arrêt choisi, si pris dans la liste
    var lat: Double?
    var lon: Double?

    var hasCoordinates: Bool { lat != nil && lon != nil }
}


final class StopReports: ObservableObject {
    static let shared = StopReports()

    @Published private(set) var reports: [StopReport] = []

    private let fileURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("stopreports.json")

    private var index: [String: StopReport] = [:]

    private init() {
        load()
    }

    private static func key(_ provider: Int, _ location: Int, _ mode: String) -> String {
        "\(provider)|\(location)|\(mode)"
    }

    /// L'arrêt identifié pour ce couple. Dix des treize réseaux concernés n'ont
    /// aucun arrêt en base : leur nom ne peut être que saisi au clavier, sans
    /// coordonnées. Il s'affiche quand même — c'est isLocatable, et non found,
    /// qui décide de la mise en carte.
    func station(provider: Int, location: Int, mode: String, lines: [NavigoLineInfo] = []) -> NavigoStationInfo? {
        guard let r = index[Self.key(provider, location, mode)] else { return nil }
        return NavigoStationInfo(name: r.stationName, provider_id: provider, line_id: nil,
                                 location_id: location, mode: mode,
                                 lat: r.lat ?? 0, lon: r.lon ?? 0,
                                 lines: lines, found: true)
    }

    func report(provider: Int, location: Int, mode: String) -> StopReport? {
        index[Self.key(provider, location, mode)]
    }

    func save(_ report: StopReport) {
        // Un même arrêt ne se signale qu'une fois : le dernier avis remplace
        reports.removeAll { $0.providerId == report.providerId
                         && $0.locationId == report.locationId
                         && $0.mode == report.mode }
        reports.insert(report, at: 0)
        rebuild()
        persist()
    }

    func delete(at offsets: IndexSet) {
        reports.remove(atOffsets: offsets)
        rebuild()
        persist()
    }

    func clearAll() {
        reports = []
        rebuild()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Le journal, dans un format directement exploitable par le script de
    /// génération : un tableau d'objets à plat.
    var exportData: Data? {
        try? JSONEncoder.iso.encode(reports)
    }

    private func rebuild() {
        index = Dictionary(reports.map { (Self.key($0.providerId, $0.locationId, $0.mode), $0) },
                           uniquingKeysWith: { first, _ in first })
    }

    private func persist() {
        if let data = try? JSONEncoder.iso.encode(reports) {
            try? data.write(to: fileURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.iso.decode([StopReport].self, from: data) else { return }
        reports = decoded
        rebuild()
    }
}


extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}


extension UTType {
    static var stopJournal: UTType { .json }
}

struct StopJournalFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { _ in "arrets-a-identifier.json" }
    }
}
