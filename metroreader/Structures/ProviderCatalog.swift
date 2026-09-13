//
//  ProviderCatalog.swift
//  metroreader
//

import Foundation


/// Ce qui nomme un exploitant, qu'il vienne du référentiel ou d'une saisie.
///
/// Les deux portent les mêmes champs, et les mêmes règles d'affichage étaient
/// écrites deux fois pour eux — trois pour le nom court et le détail.
protocol LibelleExploitant {
    var network: String? { get }
    var operatorName: String? { get }
    var dsp: Int? { get }
    var name: String? { get }
}

extension LibelleExploitant {
    /// Le réseau, quand l'exploitant en exploite une délégation.
    private var reseau: String? { network?.nilIfEmpty }

    /// La société qui fait rouler la délégation, ou l'aveu qu'on l'ignore.
    private var societe: String { operatorName?.nilIfEmpty ?? "Exploitant inconnu" }

    /// Le libellé complet d'une délégation — réseau, société, numéro de lot —,
    /// rien hors délégation : SNCF et la RATP n'en sont pas.
    var libelleDeDelegation: String? {
        guard let reseau else { return nil }
        guard let dsp else { return "\(reseau) — \(societe)" }
        return "\(reseau) — \(societe) (DSP \(dsp))"
    }

    /// Le nom court : le réseau, ou le libellé libre.
    var nomCourt: String? { reseau ?? name?.nilIfEmpty }

    /// Ce que le nom court laisse de côté : la société et son lot. Rien hors
    /// délégation.
    var detail: String? {
        guard reseau != nil else { return nil }
        return dsp.map { "\(societe) (DSP \($0))" } ?? societe
    }
}


struct ServiceProviderInfo: Decodable, LibelleExploitant {
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
        libelleDeDelegation ?? name ?? "Unknown (\(id))"
    }
}

/// Un réseau billettique, identifié par le couple pays / réseau que la carte
/// écrit en hexadécimal.
public struct NetworkInfo: Decodable {
    let name: String
    let countryId: String
    let networkId: String
}

private struct ProvidersFile: Decodable {
    let serviceProviders: [ServiceProviderInfo]
    let networks: [NetworkInfo]
}

public class ProviderCatalog {
    /// La RATP au référentiel, sous qui restent classées les lignes que ses
    /// délégations exploitent désormais.
    static let ratpId = 3

    // Exploitants (EnvApplicationIssuerId, EventServiceProvider, ContractSaleAgent)
    static func findProvider(_ id: Int) -> ServiceProviderInfo? { providersById[id] }

    /// Les délégations que la RATP exploite sous la marque « RATP Cap ».
    ///
    /// Elles ont repris des lignes RATP en gardant leurs numéros, mais le
    /// référentiel ne les a pas redéclarées sous le nouvel exploitant : Massy –
    /// Juvisy n'y annonce aucune ligne, Pompadour une seule. La carte, elle,
    /// annonce la délégation — d'où des lignes à nommer à la main alors que le
    /// référentiel les contient. Le renvoi vers la RATP s'arrête à cette
    /// marque : un numéro de bus se recycle d'un réseau à l'autre, et les
    /// autres délégations, elles, ont bien déclaré leurs lignes.
    static func isRATPDelegation(_ id: Int) -> Bool {
        guard let exploitant = findProvider(id) else { return false }
        return (exploitant.operatorName ?? exploitant.name ?? "").hasPrefix("RATP Cap")
    }

    // Réseaux, identifiés par le couple pays / réseau en hexadécimal
    static func findNetwork(countryId: String, networkId: String) -> NetworkInfo? {
        networks.first { $0.countryId == countryId && $0.networkId == networkId }
    }

    static var networks: [NetworkInfo] { file?.networks ?? [] }

    /// Les libellés déjà employés, pour que ce qui se saisit à la main
    /// s'écrive comme ce qui vient du référentiel.
    static let knownNetworkNames: [String] = distinct { $0.network }
    static let knownOperatorNames: [String] = distinct { $0.operatorName }

    private static func distinct(_ champ: (ServiceProviderInfo) -> String?) -> [String] {
        var vus = Set<String>()
        return (file?.serviceProviders ?? [])
            .compactMap(champ)
            .filter { !$0.isEmpty && vus.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static let file: ProvidersFile? = DonneesLivrees.charger("Providers", comme: ProvidersFile.self)

    private static let providersById: [Int: ServiceProviderInfo] = {
        guard let providers = file?.serviceProviders else { return [:] }
        return Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()
}
