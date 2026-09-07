//
//  TariffCatalog.swift
//  metroreader
//

import Foundation


struct TariffVariant: Decodable {
    let endDate: String // Date de fin de validité, au format jj/mm/aaaa
    let name: String
}

struct TariffInfo: Decodable {
    let code: String // "0x5000" ou une valeur décimale
    let name: String
    let icon: String? // L'icône par défaut si absent
    let duration: TimeInterval? // La durée par défaut si absent
    let variants: [TariffVariant]? // Libellés dépendant de la date de fin

    // Le libellé du titre, en tenant compte des variantes datées
    func name(endDate: String) -> String {
        variants?.first { $0.endDate == endDate }?.name ?? name
    }
}

private struct TariffsFile: Decodable {
    let defaultIcon: String
    let defaultDuration: TimeInterval
    let tariffs: [TariffInfo]
}

public class TariffCatalog {
    // Table unique des titres : libellé, icône et durée pour un même code
    static func find(_ code: Int) -> TariffInfo? { byCode[code] }

    static var defaultIcon: String { file?.defaultIcon ?? "ic_ticketing_default" }
    static var defaultDuration: TimeInterval { file?.defaultDuration ?? 7200 }

    static func parseCode(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") {
            return Int(trimmed.dropFirst(2), radix: 16)
        }
        return Int(trimmed)
    }

    private static let file: TariffsFile? = {
        guard let url = Bundle.main.url(forResource: "Tariffs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(TariffsFile.self, from: data)
        } catch {
            print("Error loading tariffs: \(error)")
            return nil
        }
    }()

    private static let byCode: [Int: TariffInfo] = {
        guard let tariffs = file?.tariffs else { return [:] }
        return Dictionary(
            tariffs.compactMap { tariff in parseCode(tariff.code).map { ($0, tariff) } },
            uniquingKeysWith: { first, _ in first }
        )
    }()
}
