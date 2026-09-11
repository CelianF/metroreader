//
//  EN1545.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 06/02/2025.
//

import Foundation
import IsoCountryCodes

func interpretAppVersionNumber(_ bitstring: String) -> String {
    if bitstring.prefix(3) == "000" {
        return String(format: "Intercode v1.%d", Int(bitstring.dropFirst(3), radix: 2) ?? 0)
    }
    else if bitstring.prefix(3) == "001" {
        return String(format: "Intercode v2.%d", Int(bitstring.dropFirst(3), radix: 2) ?? 0)
    }
    else {
        return String(format: "Invalid version number (%d)", Int(bitstring, radix: 2) ?? 0)
    }
}

func interpretNetworkId(_ bitstring: String) -> (String, String) {
    let countryBitstring = String(bitstring.prefix(12))
    let networkBitstring = String(bitstring.dropFirst(12))
    // now convert to hex
    let countryHex = String(format: "%03X", Int(countryBitstring, radix: 2) ?? 0)
    let networkHex = String(format: "%03X", Int(networkBitstring, radix: 2) ?? 0)
    let countryString = IsoCountryCodes.find(key: countryHex)?.name ?? "Unknown"
    let networkString = Networks.find(countryId: countryHex, networkId: networkHex)?.name ?? "Unknown (\(networkHex))"
    return (countryString, networkString)
}

/// La carte date en heure locale : des jours depuis le 1er janvier 1997, des
/// minutes depuis minuit. Les résoudre en heure de Paris, et non au décalage
/// fixe de +1 h, est ce qui évite de décaler tout l'été d'une heure.
let intercodeTimeZone = TimeZone(identifier: "Europe/Paris") ?? TimeZone(secondsFromGMT: 3600)!

private let intercodeCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = intercodeTimeZone
    return calendar
}()

private let intercodeEpoch: Date = intercodeCalendar.date(from: DateComponents(year: 1997, month: 1, day: 1))
    ?? Date(timeIntervalSince1970: 852073200)

/// Minuit, heure de Paris, du jour annoncé par la carte.
private func intercodeDay(_ daysSince1997: Int) -> Date {
    intercodeCalendar.date(byAdding: .day, value: daysSince1997, to: intercodeEpoch)
        ?? intercodeEpoch.addingTimeInterval(TimeInterval(daysSince1997 * 86400))
}

func interpretDate(_ bitstring: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "dd/MM/yyyy"
    dateFormatter.timeZone = intercodeTimeZone
    return dateFormatter.string(from: interpretDateAsDate(bitstring))
}

func interpretDateAsDate(_ bitstring: String) -> Date {
    intercodeDay(Int(bitstring, radix: 2) ?? 0)
}

func interpretTime(_ bitstring: String) -> String {
    let minutesSinceMidnight = Int(bitstring, radix: 2) ?? 0
    let date = Date(timeIntervalSince1970: TimeInterval(minutesSinceMidnight * 60))
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    return dateFormatter.string(from: date)
}

/// Instant exact d'un événement, du couple date + heure de la carte. Ajouter
/// les minutes à minuit donnerait une heure de trop dès le passage à l'heure
/// d'été : c'est bien une heure murale que la carte enregistre.
func interpretEventInstant(_ dateBitstring: String, _ timeBitstring: String) -> Date {
    let jour = interpretDateAsDate(dateBitstring)
    let minutesSinceMidnight = Int(timeBitstring, radix: 2) ?? 0
    var composantes = intercodeCalendar.dateComponents([.year, .month, .day], from: jour)
    composantes.hour = minutesSinceMidnight / 60
    composantes.minute = minutesSinceMidnight % 60
    return intercodeCalendar.date(from: composantes)
        ?? jour.addingTimeInterval(TimeInterval(minutesSinceMidnight * 60))
}

func interpretPersonalizationStatusCode(_ bitstring: String) -> (String, Bool, Bool) {
    if bitstring.isEmpty { return ("Unknown", false, false) }
    let rufBit = String(bitstring.first!) == "1"
    let org = String(bitstring.dropFirst(1).first!) == "1"
    switch Int(String(bitstring.dropFirst(2)), radix: 2) ?? 0 {
    case 0:
        return ("Anonymous", org, rufBit)
    case 1:
        return ("Declarative", org, rufBit)
    case 2:
        return ("Nominative", org, rufBit)
    case 3:
        return ("Network Specific", org, rufBit)
    default:
        return ("Unknown (\(bitstring))", org, rufBit)
    }
}

func interpretEventCode(_ bitstring: String, isRouteNumberPresent: Bool = false, routeNumber: Int? = nil, serviceProvider: Int? = nil) -> (String, String) {
    /**
     Interprets the event code from a binary string
     - Parameter bitstring: The binary string of the event code to interpret
     - Returns: A string representing the interpreted event code
     */
    
    let transportMode = Int(String(bitstring.prefix(4)), radix: 2) ?? 0      // First 4 bits
    let transitionType = Int(String(bitstring.dropFirst(4)), radix: 2) ?? 0  // Last 4 bits
    
    let transportModes = [
        "Non spécifié",
        "Bus urbain",
        "Bus interurbain",
        "Métro",
        "Tramway",
        "Train",
        "RUF",
        "RUF",
        "Parking",
        "RUF",
        "RUF",
        "Consigne à vélo",
        "RUF",
        "RUF",
        "Voiture libre-service",
        "RUF"
    ]
    
    let transitionModes = [
        "Non spécifié",
        "Entrée",
        "Sortie",
        "Validation",
        "Contrôle",
        "Validation de test",
        "Entrée (correspondance)",
        "Sortie (correspondance)",
        "RUF",
        "Annulation de validation",
        "Entrée (voie publique)",
        "Sortie (voie publique)",
        "RUF",
        "Distribution",
        "RUF",
        "Invalidation"
    ]
    
    var transportModeStr = transportModes[transportMode]
    if isRouteNumberPresent && transportModeStr == "Métro" {
        // La RATP encode le RER A en mode métro sur la course 16. Chez un autre
        // exploitant, la course 16 est bien un métro : c'est la ligne du Grand
        // Paris Express qui dessert Saint-Denis Pleyel. À exploitant inconnu on
        // garde l'ancien comportement.
        if routeNumber == 16 && (serviceProvider ?? 3) == 3 {
            transportModeStr = "RER"
        }
    }
    if isRouteNumberPresent && transportModeStr == "Train" {
        if routeNumber == 29 {
            transportModeStr = "Métro"
        } else if serviceProvider == 3, let route = routeNumber, (1...14).contains(route) {
            // La RATP ne numérote ses RER qu'en 16, 17 et 26 pour le A, 18 pour
            // le B : une course de 1 à 14 est une ligne de métro. À La Chapelle,
            // la porte qui mène du RER de Gare du Nord à la ligne 2 écrit le mode
            // train avec la course 2 — lue comme un RER, la validation annonçait
            // un « RER 2 » introuvable, à Gare du Nord.
            transportModeStr = "Métro"
        } else {
            transportModeStr = "RER"
        }
    }
    if isRouteNumberPresent && routeNumber == 101 && transportModeStr == "Bus urbain" {
        transportModeStr = "Câble"
    }
    
    return (transportModeStr, transitionModes[transitionType])
}

func interpretEventResult(_ bitstring: String) -> String {
    /**
     Interprets the event result from a binary string.
     - Parameter bitstring: The binary string to interpret.
     - Returns: A string representing the event result.
     */
    switch Int(bitstring, radix: 2) ?? 0 {
    case 0x0:
        return "OK"
    case 0x7:
            return "Transfert / Dysfonctionnement"
    case 0x8:
        return "Invalidation - fraude transport"
    case 0x9:
        return "Invalidation - fraude monétique transport"
    case 0xA:
        return "Invalidation impossible"
    case 0x14:
        // Refus d'entrée : le titre ne couvre pas le service (OrlyVal exige
        // un titre aéroport, un Imagine R n'y donne pas accès)
        return "Titre non valable"
    case 0x30:
        return "Double validation (Entrée)"
    case 0x31:
        return "Zone invalide"
    case 0x32:
        return "Contrat invalide / expiré"
    case 0x33:
        // Refus d'entrée : le titre ne couvre pas le service (l'aéroport d'Orly
        // exige un titre aéroport). Ce code n'apparaît que sur des événements
        // d'entrée, jamais de sortie, contrairement à ce que laissait croire
        // son ancien libellé « Double validation (Sortie) ».
        return "Titre non valable"
    default:
        // Tout code non répertorié, dont 0x34 et 0x35, rencontrés sur des passes
        // réelles sans qu'on sache encore ce qu'ils signifient.
        return "Événement inconnu (\(String(format: "0x%02X", Int(bitstring, radix: 2) ?? 0))) — à signaler"
    }
}

/// Un refus sans titre désigné : résultat 0 — « OK » partout ailleurs — et
/// pointeur de contrat à 0. C'est la carte vide qu'on présente à la borne.
func isRefusSansTitre(_ eventInfo: [String: Any]) -> Bool {
    guard let resultat = getKey(eventInfo, "EventResult"),
          let pointeur = getKey(eventInfo, "EventContractPointer") else { return false }
    return Int(resultat, radix: 2) == 0 && Int(pointeur, radix: 2) == 0
}

/// Le résultat à afficher, lu avec le titre que l'événement désigne.
func interpretEventResult(of eventInfo: [String: Any]) -> String? {
    guard let resultat = getKey(eventInfo, "EventResult") else { return nil }
    return isRefusSansTitre(eventInfo) ? "Refusé : aucun titre chargé" : interpretEventResult(resultat)
}

func interpretStatus(_ bitstring: String) -> String {
    switch Int(bitstring, radix: 2) ?? 0 {
    case 0x0:
        return "Valide (jamais utilisé)"
    case 0x1:
        return "Valide (utilisé)"
    case 0x3:
        return "Renouvellement à effectuer"
    case 0xD:
        return "Non validable"
    case 0x13:
        return "Bloqué"
    case 0x3F:
        return "Suspendu"
    case 0x58:
        return "Invalide"
    case 0x7F:
        return "Remboursé"
    case 0xFF:
        return "Effaçable"
    default:
        return "Unknown (\(Int(bitstring, radix: 2) ?? 0))"
    }
}

func interpretPayMethod(_ bitstring: String) -> String {
    switch Int(bitstring, radix: 2) ?? 0 {
    case 0x30:
        return "Apple Pay / Google Pay"
    case 0x80:
        return "Débit PME"
    case 0x90:
        return "Liquide"
    case 0xA0:
        return "Chèque mobilité"
    case 0xB3:
        return "Carte de paiement"
    case 0xA4:
        return "Chèque"
    case 0xA5:
        return "Chèque vacance"
    case 0xB7:
        return "Télépaiement"
    case 0xD0:
        return "Paiement à distance"
    case 0xD7:
        return "Voucher, Prepayment, Exchange Voucher, Travel Voucher"
    case 0xD9:
        return "Coupon de réduction"
    default:
        return "Unknown (\(Int(bitstring, radix: 2) ?? 0))"
    }
}

func interpretAmount(_ bitstring: String) -> Double {
    return Double(Int(bitstring, radix: 2) ?? 0) / 100
}

func interpretInt(_ bitstring: String) -> Int {
    return Int(bitstring, radix: 2) ?? 0
}
