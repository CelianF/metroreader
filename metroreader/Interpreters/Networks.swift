//
//  Networks.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 06/02/2025.
//

public struct NetworkInfo: Decodable {
    let name: String
    let countryId: String
    let networkId: String
}

public class Networks {
    // Les réseaux sont décrits dans Data/Providers.json
    public class func find(countryId: String, networkId: String) -> NetworkInfo? {
        return ProviderCatalog.findNetwork(countryId: countryId, networkId: networkId)
    }

    public static var allNetworks: [NetworkInfo] { ProviderCatalog.networks }
}
