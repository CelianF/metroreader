//
//  ProviderCatalog.swift
//  metroreader
//

import Foundation


struct ServiceProviderInfo: Decodable {
    let id: Int
    let name: String? // Libellé libre, pour les exploitants hors DSP
    let dsp: Int? // Numéro de lot de la délégation de service public
    let network: String? // Nom du réseau, tel qu'IDFM le publie
    let operatorName: String? // Société exploitante, saisie à la main

    enum CodingKeys: String, CodingKey {
        case id, name, dsp, network
        case operatorName = "operator"
    }

    /// SNCF et la RATP ne sont pas des DSP : elles gardent leur libellé simple.
    var displayName: String {
        guard let network, !network.isEmpty else {
            return name ?? "Unknown (\(id))"
        }
        let exploitant = (operatorName?.isEmpty == false) ? operatorName! : "Exploitant inconnu"
        guard let dsp else { return "\(network) — \(exploitant)" }
        return "\(network) — \(exploitant) (DSP \(dsp))"
    }
}

private struct ProvidersFile: Decodable {
    let serviceProviders: [ServiceProviderInfo]
    let networks: [NetworkInfo]
}

public class ProviderCatalog {
    // Exploitants (EnvApplicationIssuerId, EventServiceProvider, ContractSaleAgent)
    static func findProvider(_ id: Int) -> ServiceProviderInfo? { providersById[id] }

    // Réseaux, identifiés par le couple pays / réseau en hexadécimal
    static func findNetwork(countryId: String, networkId: String) -> NetworkInfo? {
        networks.first { $0.countryId == countryId && $0.networkId == networkId }
    }

    static var networks: [NetworkInfo] { file?.networks ?? [] }

    private static let file: ProvidersFile? = {
        guard let url = Bundle.main.url(forResource: "Providers", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(ProvidersFile.self, from: data)
        } catch {
            print("Error loading providers: \(error)")
            return nil
        }
    }()

    private static let providersById: [Int: ServiceProviderInfo] = {
        guard let providers = file?.serviceProviders else { return [:] }
        return Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()
}
