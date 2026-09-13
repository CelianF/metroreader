//
//  ScanRecord.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//  Edited by Célian Faucille on 10/01/2026.


import Foundation
import SwiftUI


struct ScanRecord: Identifiable, Codable {
    let id: UUID // Gardé pour la compatibilité SwiftUI
    var date: Date // Date du dernier scan
    var nickname: String? // Nom personnalisé
    var imageName: String? // Image de pass personnalisée
    var isPinned: Bool = false
    let cardID: UInt64
    var iccData: String?
    var envData: Data? { didSet { decodes = Decodes() } }
    var contractsData: Data? { didSet { decodes = Decodes() } }
    var eventsData: Data? { didSet { decodes = Decodes() } }
    var specialEventsData: Data? { didSet { decodes = Decodes() } }

    /// Les blobs déjà décodés.
    ///
    /// envHolder, contracts et events repassaient par JSONSerialization à chaque
    /// lecture, et une ligne de l'historique les lisait une dizaine de fois par
    /// rendu : pour son titre, son image, et la fiche qu'elle prépare. Une
    /// classe, pour qu'une lecture remplisse le cache sans muter la fiche ; un
    /// cache neuf dès qu'un blob change, pour qu'une copie modifiée ne relise
    /// pas l'ancien.
    private var decodes = Decodes()

    enum CodingKeys: String, CodingKey {
        case id, date, nickname, imageName, isPinned, cardID
        case iccData, envData, contractsData, eventsData, specialEventsData
    }

    init(id: UUID, date: Date, nickname: String?, imageName: String?, isPinned: Bool = false,
         cardID: UInt64, iccData: String?, envData: Data?, contractsData: Data?,
         eventsData: Data?, specialEventsData: Data?) {
        self.id = id
        self.date = date
        self.nickname = nickname
        self.imageName = imageName
        self.isPinned = isPinned
        self.cardID = cardID
        self.iccData = iccData
        self.envData = envData
        self.contractsData = contractsData
        self.eventsData = eventsData
        self.specialEventsData = specialEventsData
    }

    var icc: String { iccData ?? "" }

    var envHolder: [String: Any] {
        if let deja = decodes.env { return deja }
        let lu = Self.objet(envData)
        decodes.env = lu
        return lu
    }

    var contracts: [[String: Any]] {
        if let deja = decodes.contracts { return deja }
        let lus = Self.tableau(contractsData)
        decodes.contracts = lus
        return lus
    }

    var events: [[String: Any]] {
        if let deja = decodes.events { return deja }
        let lus = Self.tableau(eventsData)
        decodes.events = lus
        return lus
    }

    var specialEvents: [[String: Any]] {
        if let deja = decodes.specialEvents { return deja }
        let lus = Self.tableau(specialEventsData)
        decodes.specialEvents = lus
        return lus
    }

    // Titre d'affichage intelligent
    var displayTitle: String {
        if let name = nickname, !name.isEmpty {
            return name
        }
        return getKey(envHolder, "HolderDataCommercialID") != nil ? "\(interpretNavigoCommercialId(getKey(envHolder, "HolderDataCommercialID") ?? ""))" : "Pass inconnu (\(cardID))"
    }

    var image: String {
        if let imageName = imageName, !imageName.isEmpty {
            return imageName
        }
        return interpretNavigoImage(getKey(envHolder, "HolderDataCardStatus") ?? "", getKey(envHolder, "EnvApplicationIssuerId") ?? "", getKey(envHolder, "HolderDataCommercialID") ?? "", contracts)
    }

    private static func objet(_ data: Data?) -> [String: Any] {
        guard let data = data else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func tableau(_ data: Data?) -> [[String: Any]] {
        guard let data = data else { return [] }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    var exportDataAsJSON: Data? {
        let dict: [String: Any] = [
            "cardID": cardID,
            "nickname": nickname ?? "",
            "imageName": imageName ?? "",
            "icc": icc,
            "envHolder": envHolder,
            "contracts": contracts,
            "events": events,
            "specialEvents": specialEvents
        ]
        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
    }

    /// Le contenu du fichier .metropass de cette fiche, sérialisé seulement au
    /// moment du partage.
    var export: () -> Data? {
        { [self] in exportDataAsJSON }
    }
}


extension ScanRecord {
    /// Un champ ajouté après coup manque aux fiches déjà enregistrées, et le
    /// décodage synthétisé, qui ignore la valeur par défaut, rejette alors la
    /// fiche entière : c'est ainsi qu'`isPinned` a vidé les historiques au
    /// Build 36. Tout champ nouveau se décode donc ici, avec sa valeur de repli.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        imageName = try c.decodeIfPresent(String.self, forKey: .imageName)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        cardID = try c.decode(UInt64.self, forKey: .cardID)
        iccData = try c.decodeIfPresent(String.self, forKey: .iccData)
        envData = try c.decodeIfPresent(Data.self, forKey: .envData)
        contractsData = try c.decodeIfPresent(Data.self, forKey: .contractsData)
        eventsData = try c.decodeIfPresent(Data.self, forKey: .eventsData)
        specialEventsData = try c.decodeIfPresent(Data.self, forKey: .specialEventsData)
    }
}


/// Ce qu'une fiche a déjà décodé de ses blobs.
private final class Decodes {
    var env: [String: Any]?
    var contracts: [[String: Any]]?
    var events: [[String: Any]]?
    var specialEvents: [[String: Any]]?
}
