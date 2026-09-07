//
//  Intercode.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 08/02/2025.
//

import Foundation

func isContractBest(_ contractInfo: [String: Any], _ allContracts: [[String: Any]]) -> Bool {
    var minPriority = 0x10
    if isContractDisabled(contractInfo) {
        return false
    }
    for contract in allContracts {
        if !isContractDisabled(contract) && interpretInt(getKey(contract, "ContractListTariffPriority") ?? "0") < minPriority {
            minPriority = interpretInt(getKey(contract, "ContractListTariffPriority") ?? "0")
        }
    }
    return interpretInt(getKey(contractInfo, "ContractListTariffPriority") ?? "0") == minPriority
}

// Statuts qui rendent un contrat inutilisable. Les statuts inconnus sont
// volontairement absents : mieux vaut montrer un contrat qu'on ne sait pas
// interpréter que d'en masquer un valable.
private let disabledContractStatuses: Set<Int> = [
    0x0D, // Non validable
    0x13, // Bloqué
    0x3F, // Suspendu
    0x58, // Invalide
    0x7F, // Remboursé
    0xFF, // Effaçable
]

func isContractDisabled(_ contractInfo: [String: Any]) -> Bool {
    // Check if priority is a disabled one
    if let priority = getKey(contractInfo, "ContractListTariffPriority") {
        if interpretInt(priority) >= 0xC {
            return true
        }
    }

    // Le statut porté par le contrat lui-même. C'est le seul critère fiable
    // pour les abonnements à tacite reconduction, dont la date de fin n'est
    // qu'une échéance technique lointaine : dix ans pour un Navigo Annuel.
    if let status = getKey(contractInfo, "ContractStatus") {
        if disabledContractStatuses.contains(interpretInt(status)) {
            return true
        }
    }

    // Check validity end date, if there's one
    if let contractValidityEndDate = getKey(contractInfo, "ContractValidityEndDate") {
        // La date de fin Intercode est inclusive : le contrat reste valable
        // toute cette journée. On la compare donc au début du jour courant et
        // non à l'instant présent, sans quoi il expirait dès sa première heure.
        if interpretDateAsDate(contractValidityEndDate) < Calendar.current.startOfDay(for: Date()) {
            return true
        }
    }
    
    // Check if counter value is 0, if there's a counter
    if let counterValue = getKey(contractInfo, "CounterContractCount") {
        if interpretInt(counterValue) == 0 {
            return true
        }
    }
    
    return false
}
