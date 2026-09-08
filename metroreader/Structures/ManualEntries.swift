//
//  ManualEntries.swift
//  metroreader
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers


// MARK: - Ce que la carte annonce sans que le référentiel sache le nommer

/// Un exploitant que la carte désigne par un numéro auquel aucun libellé ne
/// répond. Les champs reprennent ceux de `ServiceProviderInfo` pour que la
/// saisie se verse telle quelle dans `Data/Providers.json`.
struct ProviderEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    let providerId: Int

    var network: String?      // Nom du réseau, tel qu'IDFM le publie
    var operatorName: String? // Société exploitante
    var dsp: Int?             // Numéro de lot de la délégation de service public
    var name: String?         // Libellé libre, pour les exploitants hors DSP

    enum CodingKeys: String, CodingKey {
        case id, date, providerId, network, dsp, name
        case operatorName = "operator"
    }

    /// Même règle d'affichage que le catalogue, pour qu'une saisie se lise
    /// comme une entrée du référentiel.
    var displayName: String {
        guard let network, !network.isEmpty else {
            if let name, !name.isEmpty { return name }
            return "Exploitant \(providerId)"
        }
        let exploitant = (operatorName?.isEmpty == false) ? operatorName! : "Exploitant inconnu"
        guard let dsp else { return "\(network) — \(exploitant)" }
        return "\(network) — \(exploitant) (DSP \(dsp))"
    }
}


/// Une ligne que la carte désigne par un numéro de course dont aucune ligne du
/// référentiel ne porte le nom, pour cet exploitant et ce mode.
struct LineEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date

    // Ce que la carte annonce
    let providerId: Int
    let routeNumber: Int
    let mode: String

    // Ce que l'utilisateur a identifié
    var name: String
    var publicId: String?      // identifiant IDFM, si la ligne a été prise dans la liste
    var backgroundColor: String
    var textColor: String

    static let defaultBackground = "c5c5c5"
    static let defaultText = "000000"

    var lineInfo: NavigoLineInfo {
        NavigoLineInfo(name: name, mode: mode,
                       public_id: publicId ?? "UNK\(routeNumber)",
                       provider_id: providerId, line_id: routeNumber,
                       background_color: backgroundColor, text_color: textColor)
    }
}


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


// MARK: - Le journal

/// Ce que l'utilisateur a saisi faute de référentiel.
///
/// Trois objets manquent aux jeux de données publics, et pour la même raison :
/// des exploitants n'ont pas déclaré leur codification. Il leur manque un
/// libellé d'exploitant, un nom de ligne, ou la correspondance entre un code
/// d'arrêt et un arrêt réel. Les trois se saisissent depuis l'écran d'un
/// événement, se relisent dans Réglages › Données, et s'exportent de là pour
/// être versés au jeu de données.
final class ManualEntries: ObservableObject {
    static let shared = ManualEntries()

    @Published private(set) var providers: [ProviderEntry] = []
    @Published private(set) var lines: [LineEntry] = []
    @Published private(set) var stops: [StopReport] = []

    private static func documents(_ name: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    // Le nom du fichier des arrêts est celui des versions précédentes : les
    // journaux déjà constitués se relisent sans migration.
    private let stopsURL = documents("stopreports.json")
    private let linesURL = documents("manual-lines.json")
    private let providersURL = documents("manual-providers.json")

    private var stopIndex: [String: StopReport] = [:]
    private var lineIndex: [String: LineEntry] = [:]
    private var providerIndex: [Int: ProviderEntry] = [:]

    private init() {
        stops = Self.read(stopsURL) ?? []
        lines = Self.read(linesURL) ?? []
        providers = Self.read(providersURL) ?? []
        rebuild()
    }

    // MARK: Consultation

    private static func stopKey(_ provider: Int, _ location: Int, _ mode: String) -> String {
        "\(provider)|\(location)|\(mode)"
    }

    private static func lineKey(_ provider: Int, _ route: Int, _ mode: String) -> String {
        "\(provider)|\(route)|\(mode)"
    }

    /// L'arrêt identifié pour ce couple. Dix des treize réseaux concernés n'ont
    /// aucun arrêt en base : leur nom ne peut être que saisi au clavier, sans
    /// coordonnées. Il s'affiche quand même — c'est isLocatable, et non found,
    /// qui décide de la mise en carte.
    func station(provider: Int, location: Int, mode: String, lines: [NavigoLineInfo] = []) -> NavigoStationInfo? {
        guard let r = stopIndex[Self.stopKey(provider, location, mode)] else { return nil }
        return NavigoStationInfo(name: r.stationName, provider_id: provider, line_id: nil,
                                 location_id: location, mode: mode,
                                 lat: r.lat ?? 0, lon: r.lon ?? 0,
                                 lines: lines, found: true)
    }

    func lineEntry(provider: Int, route: Int, mode: String) -> LineEntry? {
        lineIndex[Self.lineKey(provider, route, mode)]
    }

    func line(provider: Int, route: Int, mode: String) -> NavigoLineInfo? {
        lineEntry(provider: provider, route: route, mode: mode)?.lineInfo
    }

    func provider(_ id: Int) -> ProviderEntry? { providerIndex[id] }

    func providerName(_ id: Int) -> String? { providerIndex[id]?.displayName }

    // MARK: L'arborescence

    /// Le journal se lit comme le réseau se parcourt : un exploitant, ses
    /// lignes, et les arrêts de chaque ligne. Les trois journaux sont cousus
    /// ensemble ici — une ligne peut n'exister que par les arrêts qui la citent,
    /// un réseau que par une ligne qu'on lui a nommée.
    var networks: [ManualNetwork] {
        var ordre: [Int] = []
        var vus = Set<Int>()
        for id in providers.map(\.providerId) + lines.map(\.providerId) + stops.map(\.providerId)
        where vus.insert(id).inserted {
            ordre.append(id)
        }
        return ordre.map { id in
            ManualNetwork(providerId: id, entry: providerIndex[id], lines: lignes(de: id))
        }
    }

    private func lignes(de providerId: Int) -> [ManualLine] {
        let sesLignes = lines.filter { $0.providerId == providerId }
        let sesArrets = stops.filter { $0.providerId == providerId }

        var ordre: [String?] = []
        var vus = Set<String>()
        for nom in sesLignes.map({ Optional($0.name) }) + sesArrets.map(\.lineName)
        where vus.insert(nom ?? "").inserted {
            ordre.append(nom)
        }

        return ordre.map { nom in
            let arretsDeLaLigne = sesArrets.filter { $0.lineName == nom }
            return ManualLine(providerId: providerId,
                              name: nom,
                              entry: sesLignes.first { $0.name == nom },
                              reference: Self.reference(nom, parmi: arretsDeLaLigne, chez: providerId),
                              stops: Self.parArret(arretsDeLaLigne))
        }
    }

    /// La ligne du référentiel, quand elle y figure.
    ///
    /// Une ligne peut n'exister ici que par les arrêts qui la citent, sans
    /// qu'on ait eu à la nommer — mais ces arrêts gardent le numéro de course,
    /// ce qui suffit à la retrouver, et à lui rendre ses couleurs.
    private static func reference(_ nom: String?, parmi reports: [StopReport], chez providerId: Int) -> NavigoLineInfo? {
        guard let nom else { return nil }
        for report in reports {
            guard let route = report.routeNumber,
                  let ligne = NavigoLines.find(providerId, route, report.mode) else { continue }
            // Le repli sur `line_id >> 8` peut rendre une autre ligne du même
            // exploitant : on ne garde que celle qui porte bien ce nom.
            if ligne.name == nom { return ligne }
        }
        return nil
    }

    /// Un même arrêt physique porte souvent plusieurs codes — un par quai, par
    /// sens, ou par exploitant qui le dessert — et ces codes n'ont aucune raison
    /// de se ressembler. Ils se rangent sous le nom qu'on leur a donné.
    private static func parArret(_ reports: [StopReport]) -> [ManualStop] {
        var ordre: [String] = []
        var groupes: [String: [StopReport]] = [:]
        for report in reports {
            if groupes[report.stationName] == nil { ordre.append(report.stationName) }
            groupes[report.stationName, default: []].append(report)
        }
        return ordre.map { ManualStop(name: $0, reports: groupes[$0] ?? []) }
    }

    // MARK: Écriture

    /// Un même arrêt ne se signale qu'une fois : le dernier avis remplace.
    func save(_ report: StopReport) {
        stops.removeAll { $0.providerId == report.providerId
                       && $0.locationId == report.locationId
                       && $0.mode == report.mode }
        stops.insert(report, at: 0)
        rebuild()
        persistStops()
    }

    func save(_ entry: LineEntry) {
        lines.removeAll { $0.providerId == entry.providerId
                       && $0.routeNumber == entry.routeNumber
                       && $0.mode == entry.mode }
        lines.insert(entry, at: 0)
        rebuild()
        persistLines()
    }

    func save(_ entry: ProviderEntry) {
        providers.removeAll { $0.providerId == entry.providerId }
        providers.insert(entry, at: 0)
        rebuild()
        persistProviders()
    }

    func rename(stop id: UUID, to name: String) {
        guard let i = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[i].stationName = name
        rebuild()
        persistStops()
    }

    func rename(line id: UUID, to name: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[i].name = name
        rebuild()
        persistLines()
    }

    func delete(stop id: UUID) {
        stops.removeAll { $0.id == id }
        rebuild()
        persistStops()
    }

    func delete(line id: UUID) {
        lines.removeAll { $0.id == id }
        rebuild()
        persistLines()
    }

    func delete(provider id: UUID) {
        providers.removeAll { $0.id == id }
        rebuild()
        persistProviders()
    }

    func clearStops() {
        stops = []
        rebuild()
        try? FileManager.default.removeItem(at: stopsURL)
    }

    func clearLines() {
        lines = []
        rebuild()
        try? FileManager.default.removeItem(at: linesURL)
    }

    func clearProviders() {
        providers = []
        rebuild()
        try? FileManager.default.removeItem(at: providersURL)
    }

    func clearAll() {
        clearStops()
        clearLines()
        clearProviders()
    }

    // MARK: Export

    var isEmpty: Bool { providers.isEmpty && lines.isEmpty && stops.isEmpty }

    /// Le journal complet. Chaque tableau garde la forme à plat que le script
    /// de génération attend ; ils sont seulement réunis sous leur nature, pour
    /// que tout parte en un seul fichier.
    var export: Data? {
        try? JSONEncoder.iso.encode(ManualExport(reseaux: providers, lignes: lines, arrets: stops))
    }

    private struct ManualExport: Encodable {
        let reseaux: [ProviderEntry]
        let lignes: [LineEntry]
        let arrets: [StopReport]
    }

    // MARK: Persistance

    private func rebuild() {
        stopIndex = Dictionary(stops.map { (Self.stopKey($0.providerId, $0.locationId, $0.mode), $0) },
                               uniquingKeysWith: { first, _ in first })
        lineIndex = Dictionary(lines.map { (Self.lineKey($0.providerId, $0.routeNumber, $0.mode), $0) },
                               uniquingKeysWith: { first, _ in first })
        providerIndex = Dictionary(providers.map { ($0.providerId, $0) },
                                   uniquingKeysWith: { first, _ in first })
    }

    private static func read<T: Decodable>(_ url: URL) -> [T]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso.decode([T].self, from: data)
    }

    private static func write<T: Encodable>(_ values: [T], to url: URL) {
        guard let data = try? JSONEncoder.iso.encode(values) else { return }
        try? data.write(to: url)
    }

    private func persistStops() { Self.write(stops, to: stopsURL) }
    private func persistLines() { Self.write(lines, to: linesURL) }
    private func persistProviders() { Self.write(providers, to: providersURL) }
}


// MARK: - L'arborescence

struct ManualNetwork: Identifiable {
    let providerId: Int
    /// La saisie qui a nommé ce réseau, s'il en a fallu une.
    let entry: ProviderEntry?
    let lines: [ManualLine]

    var id: Int { providerId }
    var stopCount: Int { lines.reduce(0) { $0 + $1.stopCount } }
}

struct ManualLine: Identifiable {
    let providerId: Int
    /// Nil quand les arrêts ont été relevés sans ligne connue.
    let name: String?
    /// La saisie qui a nommé cette ligne, s'il en a fallu une.
    let entry: LineEntry?
    /// La ligne du référentiel, quand elle y figure.
    let reference: NavigoLineInfo?
    let stops: [ManualStop]

    var id: String { "\(providerId)|\(name ?? "")" }
    var stopCount: Int { stops.count }
    var codeCount: Int { stops.reduce(0) { $0 + $1.reports.count } }

    // Les couleurs de la saisie d'abord — elle n'existe que là où le
    // référentiel n'a rien —, puis celles du référentiel, puis le gris qui dit
    // qu'on ne sait pas.
    var backgroundColor: String {
        entry?.backgroundColor ?? reference?.background_color ?? LineEntry.defaultBackground
    }

    var textColor: String {
        entry?.textColor ?? reference?.text_color ?? LineEntry.defaultText
    }
}

struct ManualStop: Identifiable {
    let name: String
    /// Tous les codes qui désignent cet arrêt.
    let reports: [StopReport]

    var id: String { name }
}


// MARK: - Codage

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


extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}


/// Le journal partagé depuis Réglages › Données.
struct ManualEntriesFile: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}
