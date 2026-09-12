//
//  Navigo.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import Foundation


func interpretNavigoCommercialId(_ bitstring: String) -> String {
    // À trouver : Navigo Découverte, eSE Android (ou eq)
    switch Int(bitstring, radix: 2) ?? 0 {
    case 0:
        return "Unknown"
    case 1:
        return "Navigo" // Ou Navigo Découverte
    case 2:
        return "Navigo Annuel"
    case 5:
        return "Navigo Imagine R"
    case 10:
        return "eSE Apple"
    case 16:
        return "Navigo Easy Carte"
    case 17:
        return "Navigo Easy SOCS"
    case 32:
        return "Carte Interne"
    default:
        return "Unknown (\(Int(bitstring, radix: 2) ?? 0))"
    }
}

func interpretNavigoImage(_ personalizationStatusBitstring: String, _ issuerIdBitstring: String, _ commercialIdBitString: String, _ contracts: [[String: Any]]) -> String {
    let (perso, _, _) = interpretPersonalizationStatusCode(personalizationStatusBitstring)
    let commercialName = interpretNavigoCommercialId(commercialIdBitString)
    let issuer = interpretServiceProvider(issuerIdBitstring)
    
    for contractInfo in contracts {
        if let tariffBitstring = getKey(contractInfo, "ContractTariff") {
            let tariff = Int(tariffBitstring, radix: 2)
            if tariff == 0x000E {
                if let endDateBitstring = getKey(contractInfo, "ContractValidityEndDate") {
                    let endDate = interpretDate(endDateBitstring)
                    switch endDate {
                    case "14/08/2024":
                        return "PhrygeJO"
                    case "11/09/2024":
                        return "PhrygeJOP"
                    default:
                        return "PhrygeJO"
                    }
                }
            } else if tariff == 0x8010 {
                return "Pass Local"
            }
        }
    }
    
    switch commercialName {
    case "Navigo", "Navigo Annuel", "Navigo Imagine R":
        return "Nominatif"
    case "eSE Apple":
        return "Pass iOS"
    case "Carte Interne":
        switch issuer {
        case "SNCF":
            return "Carmillon"
        case "Optile":
            return "Optile"
        default:
            return "Nominatif"
        }
    case "Navigo Easy Carte":
        return "Easy"
    case "Navigo Easy SOCS": // Support Occasionnel Carton Sans Contact
        return "EasyCarton"
    default:
        switch perso {
        case "Anonymous":
            return "Easy"
        case "Declarative":
            return "Découverte"
        case "Nominative":
            return "Nominatif"
        default:
            return "Nominatif"
        }
    }
}

func interpretNavigoPersonalizationStatusCode(_ bitstring: String) -> String {
    let (perso, integral, imaginer) = interpretPersonalizationStatusCode(bitstring)
    
    switch perso {
    case "Anonymous":
        return "Navigo Easy"
    case "Declarative":
        return "Navigo Découverte"
    case "Nominative":
        if integral {
            if imaginer {
                return "Navigo Imagine R"
            }
            return "Navigo Annuel"
        }
        return "Navigo"
    default:
        return "Navigo Unknown"
    }
}

func interpretTariff(_ bitstring: String, _ contractEndDateBitstring: String) -> String {
    let code = Int(bitstring, radix: 2) ?? 0
    guard let tariff = TariffCatalog.find(code) else {
        return "Unknown (\(code))"
    }
    return tariff.name(endDate: interpretDate(contractEndDateBitstring))
}

func interpretTariffDuration(_ bitstring: String) -> TimeInterval {
    let code = Int(bitstring, radix: 2) ?? 0
    return TariffCatalog.find(code)?.duration ?? TariffCatalog.defaultDuration
}

/// Les zones couvertes par un titre, telles que le bitstring les porte : un bit
/// par zone, la première à droite.
func interpretZoneSet(_ bitstring: String) -> Set<Int> {
    var zones: Set<Int> = []
    for (i, char) in bitstring.reversed().enumerated() where char == "1" {
        zones.insert(i + 1)
    }
    return zones
}

func interpretZones(_ bitstring: String) -> String {
    /**
     Interprets the zone information from a binary string.
     - Parameter bitstring: The binary string representing zones.
     - Returns: A string describing the interpreted zones.
     */
    
    let zones = interpretZoneSet(bitstring)
    
    guard let minZone = zones.min(), let maxZone = zones.max() else {
        return "No zones"
    }
    
    if minZone == maxZone {
        return "Zone \(minZone)"
    }
    
    if minZone == 1 && maxZone == 5 {
        return "Toutes zones (1-5)"
    }
    
    return "Zones \(minZone)-\(maxZone)"
}

func interpretZonesShort(_ bitstring: String) -> String {
    /**
     Interprets the zone information from a binary string.
     - Parameter bitstring: The binary string representing zones.
     - Returns: A string describing the interpreted zones.
     */
    
    let zones = interpretZoneSet(bitstring)
    
    guard let minZone = zones.min(), let maxZone = zones.max() else {
        return "-"
    }
    
    if minZone == maxZone {
        return "\(minZone)"
    }
    
    return "\(minZone)-\(maxZone)"
}

func interpretRouteNumber(_ routeNumberBitstring: String, _ eventCodeBitstring: String, _ eventServiceProviderBitstring: String) -> String {
    let routeNumber = Int(routeNumberBitstring, radix: 2)!
    
    let serviceProviderCode = Int(eventServiceProviderBitstring, radix: 2)!

    let eventTransport = interpretEventCode(eventCodeBitstring, isRouteNumberPresent: true, routeNumber: routeNumber, serviceProvider: serviceProviderCode).0
    
    // Une ligne ne se saisit que si le référentiel n'a pas su la nommer : la
    // saisie passe donc devant, elle ne peut rien recouvrir.
    if let saisie = ManualEntries.shared.lineEntry(provider: serviceProviderCode, route: routeNumber, mode: eventTransport) {
        return saisie.name
    }
    
    if (eventTransport == "RER") {
        if (routeNumber == 16) || (routeNumber == 17) || (routeNumber == 26) {
            return "A"
        }
        else if routeNumber == 18 {
            return "B"
        }
    }
    if (eventTransport == "Métro") {
        // Chez la RATP le numéro de course vaut le numéro de ligne, ce que les
        // cas ci-dessous supposent. Ce n'est pas vrai des autres exploitants :
        // la desserte de l'aéroport d'Orly porte la course 12, qui entrerait en
        // collision avec la ligne 12. On interroge donc la table pour eux.
        if serviceProviderCode != 3,
           let route = NavigoLines.find(serviceProviderCode, routeNumber, eventTransport) {
            return route.name
        }
        switch routeNumber {
        case 29:
            return "Orlyval"
        case 103:
            return "3 bis"
        case 107:
            return "7 bis"
        case 920:
            return "10"
        case 924:
            return "6"
        default:
            return "\(routeNumber)"
        }
    }
    else if let routeName = NavigoLines.find(serviceProviderCode, routeNumber, eventTransport) {
        return routeName.name
    }
    else if (eventTransport == "Tramway") {
        switch routeNumber {
        case 11:
            return "T1"
        case 12:
            return "T2"
        case 13:
            return "T3a"
        case 3:
            return "T3b"
        case 2:
            return "T4"
        case 15:
            return "T5"
        case 16:
            return "T6"
        case 17:
            return "T7"
        case 18:
            return "T8"
        case 9:
            return "T9"
        case 10:
            return "T10"
        case 43:
            return "T13"
        default:
            return "\(routeNumber)"
        }
    }
    
    return "\(routeNumber)"
}

func interpretRoute(_ routeNumberBitstring: String, _ eventCodeBitstring: String, _ eventServiceProviderBitstring: String) -> NavigoLineInfo? {
    interpretRouteCandidates(routeNumberBitstring, eventCodeBitstring, eventServiceProviderBitstring).first
}

/// Les lignes que ce numéro de course peut désigner, la retenue en tête.
///
/// Presque toujours une seule. Mais le référentiel partage parfois un
/// `privatecode` entre plusieurs lignes, et rien sur la carte ne les
/// départage : on rend alors tout le paquet plutôt que d'en élire une.
func interpretRouteCandidates(_ routeNumberBitstring: String, _ eventCodeBitstring: String, _ eventServiceProviderBitstring: String) -> [NavigoLineInfo] {
    guard let routeNumber = Int(routeNumberBitstring, radix: 2) else {
        return []
    }
    
    let serviceProviderCode = Int(eventServiceProviderBitstring, radix: 2)!

    let eventTransport = interpretEventCode(eventCodeBitstring, isRouteNumberPresent: true, routeNumber: routeNumber, serviceProvider: serviceProviderCode).0
    
    if let saisie = ManualEntries.shared.line(provider: serviceProviderCode, route: routeNumber, mode: eventTransport) {
        return [saisie]
    }
    
    if (eventTransport == "RER") {
        if (routeNumber == 16) || (routeNumber == 17) || (routeNumber == 26) {
            return [NavigoLineInfo(name: "A", mode: "RER", public_id: "C01742", provider_id: 3, line_id: 16, background_color: "eb2132", text_color: "ffffff", is_noctilien: false)]
        }
        else if routeNumber == 18 {
            return [NavigoLineInfo(name: "B", mode: "RER", public_id: "C01743", provider_id: 3, line_id: 18, background_color: "5091cb", text_color: "ffffff", is_noctilien: false)]
        }
    }
    else if (eventTransport == "Métro" && routeNumber == 29) {
        return [NavigoLineInfo(name: "Orlyval", mode: "Métro", public_id: "C01388", provider_id: 4, line_id: 29, background_color: "5ec5ed", text_color: "ffffff", is_noctilien: false)]
    }
    else {
        let trouvees = NavigoLines.candidates(serviceProviderCode, routeNumber, eventTransport)
        if !trouvees.isEmpty {
            return trouvees.map { ligne in
                var route = ligne
                if route.is_noctilien {
                    route.mode = "Noctilien"
                }
                return route
            }
        }
    }
    
    // Ni référentiel ni saisie : on rend le numéro de course brut, et on le dit.
    return [NavigoLineInfo(name: "\(routeNumber)", mode: eventTransport, public_id: "UNK\(routeNumber)", provider_id: serviceProviderCode, line_id: routeNumber, background_color: LineEntry.defaultBackground, text_color: LineEntry.defaultText, is_noctilien: false, found: false)]
}

func interpretServiceProvider(_ bitstring: String) -> String {
    interpretServiceProviderName(Int(bitstring, radix: 2) ?? 0)
}

/// Le libellé d'exploitant, sans passer par le bitstring. Le référentiel
/// d'abord, puis ce que l'utilisateur a saisi pour les exploitants qui n'y
/// figurent pas.
func interpretServiceProviderName(_ id: Int) -> String {
    ProviderCatalog.findProvider(id)?.displayName
        ?? ManualEntries.shared.providerName(id)
        ?? "Unknown (\(id))"
}

/// Le nom court d'un exploitant : celui de son réseau, ou son libellé s'il n'en
/// a pas. Le libellé complet — réseau, exploitant et numéro de lot — ne tient
/// pas sur la ligne d'une liste.
func interpretServiceProviderShortName(_ id: Int) -> String {
    if let catalogue = ProviderCatalog.findProvider(id) {
        if let reseau = catalogue.network, !reseau.isEmpty { return reseau }
        if let nom = catalogue.name, !nom.isEmpty { return nom }
    }
    if let saisie = ManualEntries.shared.provider(id) {
        if let reseau = saisie.network, !reseau.isEmpty { return reseau }
        if let nom = saisie.name, !nom.isEmpty { return nom }
    }
    return "Exploitant \(id)"
}

/// Ce que le nom court laisse de côté : l'exploitant et son numéro de lot.
/// Nil pour ce qui n'est pas une délégation — SNCF, RATP.
func interpretServiceProviderDetail(_ id: Int) -> String? {
    let exploitant: String?
    let dsp: Int?
    if let catalogue = ProviderCatalog.findProvider(id), catalogue.network?.isEmpty == false {
        exploitant = catalogue.operatorName
        dsp = catalogue.dsp
    } else if let saisie = ManualEntries.shared.provider(id), saisie.network?.isEmpty == false {
        exploitant = saisie.operatorName
        dsp = saisie.dsp
    } else {
        return nil
    }
    let societe = (exploitant?.isEmpty == false) ? exploitant! : "Exploitant inconnu"
    return dsp.map { "\(societe) (DSP \($0))" } ?? societe
}

/// Vrai quand le nom affiché vient du journal et non du référentiel. Une
/// saisie que le référentiel a fini par rattraper est masquée par lui : la
/// signaler comme saisie ferait mentir la pastille.
func isServiceProviderNamedByHand(_ id: Int) -> Bool {
    ProviderCatalog.findProvider(id) == nil && ManualEntries.shared.provider(id) != nil
}

/// Vrai quand ni le référentiel ni le journal ne savent nommer cet exploitant.
func isServiceProviderUnknown(_ id: Int) -> Bool {
    ProviderCatalog.findProvider(id) == nil && ManualEntries.shared.provider(id) == nil
}

func interpretLocationId(_ locationIdBitString: String, _ eventCodeBitstring: String, _ eventServiceProviderBitstring: String, _ routeNumberBitstring: String?) -> NavigoStationInfo {
    guard let value = Int(locationIdBitString, radix: 2) else {
        return NavigoStationInfo.init(name: "Unknown (\(locationIdBitString))", provider_id: 0, line_id: nil, location_id: 0, mode: "Unknown", lat: 0, lon: 0, found: false)
    }
    
    let eventRouteNumberPresent = (routeNumberBitstring != nil)
    
    let eventTransport = interpretEventCode(eventCodeBitstring, isRouteNumberPresent: eventRouteNumberPresent, routeNumber: eventRouteNumberPresent ? Int(routeNumberBitstring ?? "0", radix: 2) : nil, serviceProvider: Int(eventServiceProviderBitstring, radix: 2)).0
    
    let eventServiceProviderId = Int(eventServiceProviderBitstring, radix: 2) ?? 0

    guard let station = NavigoStations.find(eventServiceProviderId, eventRouteNumberPresent ? Int(routeNumberBitstring ?? "", radix: 2) : nil, value, eventTransport) else {
        // Faute de référentiel, l'arrêt a pu être identifié à la main
        if let signale = ManualEntries.shared.station(provider: eventServiceProviderId, location: value, mode: eventTransport) {
            return signale
        }
        // Ou venir de l'exploitant lui-même, quand il nous a transmis ce qu'il
        // n'a jamais déclaré au référentiel. La saisie de l'utilisateur passe
        // devant : c'est lui qui corrige ce qu'on livre, pas l'inverse.
        if let livre = StopCorrections.find(eventServiceProviderId, value, eventTransport) {
            return livre
        }
        return NavigoStationInfo.init(name: "\(value)", provider_id: eventServiceProviderId, line_id: nil, location_id: value, mode: eventTransport, lat: 0, lon: 0, found: false)
    }
    return station
}

