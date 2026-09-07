//
//  ProviderCatalog.swift
//  metroreader
//

import Foundation


struct ServiceProviderInfo: Decodable {
    let id: Int
    let name: String
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
