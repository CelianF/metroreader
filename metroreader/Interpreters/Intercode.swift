//
//  Intercode.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 08/02/2025.
//

import Foundation

/// Le titre retenu : parmi ceux qui servent aujourd'hui, celui que la liste des
/// contrats met en tête par sa priorité. Les cartes relevées n'en écrivent
/// aucune, et tous se valent alors.
///
/// Un titre qui attend sa date de début, comme un Mois acheté pour le mois
/// prochain, ne sert pas encore : il n'est retenu que si rien d'autre ne sert.
///
/// Liberté+ passe derrière tout autre titre qui sert, priorité ou non. Sur un
/// Navigo qui porte aussi un Mois, les validations désignent le Mois, jamais
/// lui ; retenu parce qu'il venait le premier sur la carte, Liberté+
/// s'affichait seul et étoilé, le Mois caché derrière « Voir tout ».
func isContractBest(_ contractInfo: [String: Any], _ allContracts: [[String: Any]]) -> Bool {
    guard !isContractDisabled(contractInfo) else { return false }
    var candidats = allContracts.filter { !isContractDisabled($0) }
    if candidats.contains(where: { estUtilisable($0) && !estLibertePlus($0) }) {
        guard !estLibertePlus(contractInfo) else { return false }
        candidats.removeAll { estLibertePlus($0) }
    }
    if candidats.contains(where: estUtilisable) {
        guard estUtilisable(contractInfo) else { return false }
        candidats.removeAll { !estUtilisable($0) }
    }
    let minimum = candidats.map(prioriteDansLaListe).min() ?? 0x10
    return prioriteDansLaListe(contractInfo) == minimum
}

/// Un titre qui sert aujourd'hui. `isContractDisabled` couvre le statut,
/// l'échéance et le compteur ; reste la date de début, qu'un titre acheté pour
/// le mois prochain n'a pas encore atteinte.
func estUtilisable(_ contract: [String: Any]) -> Bool {
    guard !isContractDisabled(contract) else { return false }
    guard let debut = getKey(contract, "ContractValidityStartDate") else { return true }
    return interpretDateAsDate(debut) <= Date()
}

private func prioriteDansLaListe(_ contract: [String: Any]) -> Int {
    interpretInt(getKey(contract, "ContractListTariffPriority") ?? "0")
}

/// Navigo Liberté+, qui facture après coup les trajets effectués.
func estLibertePlus(_ contract: [String: Any]) -> Bool {
    guard let bits = getKey(contract, "ContractTariff"), let tarif = Int(bits, radix: 2) else { return false }
    return tarif == 0x1000 || tarif == 0x1001
}

/// L'ordre où les contrats s'affichent : les titres qui servent aujourd'hui,
/// Liberté+ derrière eux, ceux qui attendent leur date de début, puis ceux qui
/// ne servent plus. Dans chaque groupe, chacun garde sa place sur la carte.
func ordreDesContrats(_ contracts: [[String: Any]]) -> [Int] {
    let rangs = contracts.map { contrat -> Int in
        if isContractDisabled(contrat) { return 3 }
        if estLibertePlus(contrat) { return 1 }
        return estUtilisable(contrat) ? 0 : 2
    }
    return contracts.indices.sorted { (rangs[$0], $0) < (rangs[$1], $1) }
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
        // Le jour courant est celui de Paris, comme la date de fin : pris dans
        // le fuseau de l'iPhone, il éteignait un titre avant la fin de son
        // dernier jour dès qu'on lisait la carte ailleurs.
        if interpretDateAsDate(contractValidityEndDate) < intercodeCalendar.startOfDay(for: Date()) {
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
