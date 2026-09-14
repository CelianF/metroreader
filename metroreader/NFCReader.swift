//
//  NFCReader.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import Foundation
#if os(iOS)
import CoreNFC
import UIKit
#endif

/// Les octets d'une réponse, un caractère par bit : la forme que lit le parseur
/// EN1545, et celle que gardent les exports.
private func bits(_ octets: Data) -> String {
    octets.map { octet in
        let binaire = String(octet, radix: 2)
        return String(repeating: "0", count: 8 - binaire.count) + binaire
    }.joined()
}

#if os(iOS)
/// Un mot d'état autre que 90 00 : la carte a répondu, mais refuse la commande
/// — application absente, enregistrement inexistant.
private struct RefusDeLaCarte: Error {
    let mot: UInt16

    static let applicationAbsente: UInt16 = 0x6A82
}

/// Envoie une commande et rend la réponse en bits, ou lève le refus que la
/// carte a opposé.
private func envoyer(_ tag: NFCISO7816Tag, _ apdu: NFCISO7816APDU) async throws -> String {
    JournalNFC.shared.noter(.commande, commandeEnHexadecimal(apdu))
    let reponse: (Data, UInt8, UInt8)
    do {
        reponse = try await tag.sendCommand(apdu: apdu)
    } catch {
        JournalNFC.shared.noter(.erreur, "Échange interrompu : \(error.localizedDescription)")
        throw error
    }
    let (response, sw1, sw2) = reponse
    JournalNFC.shared.noter(.reponse, reponseEnHexadecimal(response, sw1, sw2))
    guard sw1 == 0x90 && sw2 == 0x00 else {
        throw RefusDeLaCarte(mot: UInt16(sw1) << 8 | UInt16(sw2))
    }
    return bits(response)
}

/// La commande telle qu'elle part : classe, instruction, paramètres, puis les
/// données et la longueur attendue.
private func commandeEnHexadecimal(_ apdu: NFCISO7816APDU) -> String {
    var octets = [apdu.instructionClass, apdu.instructionCode, apdu.p1Parameter, apdu.p2Parameter]
    if let donnees = apdu.data, !donnees.isEmpty {
        octets.append(UInt8(truncatingIfNeeded: donnees.count))
        octets.append(contentsOf: donnees)
    }
    if apdu.expectedResponseLength >= 0 {
        octets.append(UInt8(truncatingIfNeeded: apdu.expectedResponseLength))
    }
    return hexadecimalDesOctets(Data(octets))
}

/// La réponse et son mot d'état.
private func reponseEnHexadecimal(_ octets: Data, _ sw1: UInt8, _ sw2: UInt8) -> String {
    let mot = String(format: "%02X %02X", sw1, sw2)
    return octets.isEmpty ? mot : "\(hexadecimalDesOctets(octets)) · \(mot)"
}

private func selectAID(_ tag: NFCISO7816Tag, _ aidData: Data) async throws -> String {
    try await envoyer(tag, NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xA4, p1Parameter: 0x04, p2Parameter: 0x00, data: aidData, expectedResponseLength: -1))
}

private func readRecord(_ tag: NFCISO7816Tag, _ recordId: UInt8, _ sfi: UInt8) async throws -> String {
    try await envoyer(tag, NFCISO7816APDU(data: Data([0x00, 0xB2, recordId, sfi << 3 | 4, 0x00]))!)
}

/// Lit un enregistrement que la carte peut ne pas porter. Un refus laisse
/// l'emplacement vide et la lecture continue ; une connexion perdue, elle,
/// interrompt tout : poursuivre donnerait une carte tronquée, présentée comme
/// complète.
private func lireSiPresent(_ tag: NFCISO7816Tag, _ recordId: UInt8, _ sfi: UInt8) async throws -> String? {
    do {
        return try await readRecord(tag, recordId, sfi)
    } catch is RefusDeLaCarte {
        return nil
    }
}

/// Ce que la feuille NFC dit quand la lecture échoue. Elle se fermait jusque-là
/// comme après un succès, sur un écran resté vide.
private func messageDEchec(_ erreur: Error) -> String {
    if let refus = erreur as? RefusDeLaCarte, refus.mot == RefusDeLaCarte.applicationAbsente {
        return "Cette carte n'est pas un passe Navigo."
    }
    if let nfc = erreur as? NFCReaderError, nfc.code == .readerTransceiveErrorTagConnectionLost {
        return "Passe retiré trop tôt. Réessayez en le laissant sur la cible."
    }
    return "Lecture impossible. Réessayez."
}
#endif

private func interpretCardID(_ iccBitstring: String) -> UInt64 {
    var bytes = [UInt8]()
    let bitLength = 8

    for i in stride(from: 0, to: iccBitstring.count, by: bitLength) {
        let start = iccBitstring.index(iccBitstring.startIndex, offsetBy: i)
        let end = iccBitstring.index(start, offsetBy: bitLength, limitedBy: iccBitstring.endIndex) ?? iccBitstring.endIndex
        let chunk = String(iccBitstring[start..<end])

        if let byte = UInt8(chunk, radix: 2) {
            bytes.append(byte)
        }
    }

    // 2. Locate Tag C7 (0xC7)
    // Tag C7 is followed by Length 08 (0x08)
    guard let c7Index = bytes.firstIndex(of: 0xC7),
          c7Index + 1 < bytes.count,
          bytes[c7Index + 1] == 0x08 else {
        return 0
    }

    // 3. Define the segment offset
    // Data starts at c7Index + 2
    // We want the last 4 bytes of the 8-byte value
    let serialStart = c7Index + 2 + 4
    let serialEnd = serialStart + 4

    guard bytes.count >= serialEnd else { return 0 }

    let targetBytes = bytes[serialStart..<serialEnd]

    // 4. Convert 4 bytes to UInt64
    var result: UInt64 = 0
    for byte in targetBytes {
        result = (result << 8) | UInt64(byte)
    }

    return result
}

class NFCReader: NSObject, ObservableObject {
    @Published var isScanning: Bool = false

    /// Vrai dès qu'une carte est sous l'antenne et que la lecture commence.
    /// L'écran vide s'en sert pour ne pas relancer son animation : à partir de
    /// là le fil principal est accaparé, et elle saccaderait.
    @Published var isTagDetected: Bool = false

    /// Vrai seulement quand une carte a été lue jusqu'au bout, ou importée.
    /// Les contrats et les événements arrivent par vagues : sans ce drapeau,
    /// le passe s'afficherait à moitié rempli dès l'en-tête lu, et un abandon
    /// en cours de route laisserait une carte tronquée à l'écran.
    @Published var isReadComplete: Bool = false
    @Published var cardID: UInt64 = 0
    @Published var tagIcc: String = ""
    @Published var tagEnvHolder: [String: Any] = [:]
    @Published var tagContracts: [[String: Any]] = []
    @Published var tagEvents: [[String: Any]] = []
    @Published var tagSpecialEvents: [[String: Any]] = []
    var historyManager: HistoryManager?
    #if os(iOS)
    private var session: NFCTagReaderSession?
    #endif

    /// Le fichier .metropass de la carte lue, sérialisé seulement au moment du
    /// partage. Rien tant qu'aucune carte n'est lue.
    var export: (() -> Data?)? {
        if tagContracts.isEmpty && tagEvents.isEmpty && tagSpecialEvents.isEmpty && cardID == 0 {
            return nil
        }
        let dict: [String: Any] = [
            "cardID": cardID,
            "icc": tagIcc,
            "envHolder": tagEnvHolder,
            "contracts": tagContracts,
            "events": tagEvents,
            "specialEvents": tagSpecialEvents
        ]
        return {
            guard JSONSerialization.isValidJSONObject(dict) else { return nil }
            return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        }
    }

    /// Ouvre un fichier .metropass, qu'il vienne du sélecteur ou d'une autre app.
    ///
    /// L'accès sécurisé ne vaut que pour un fichier hors du bac à sable : un
    /// refus ne dit pas que le fichier est illisible, la lecture est donc tentée
    /// dans tous les cas. Le sélecteur y renonçait, l'ouverture depuis une autre
    /// app non.
    func importFile(at url: URL, historyManager: HistoryManager) {
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        do {
            importJSON(from: try Data(contentsOf: url), historyManager: historyManager)
        } catch {
            print("Lecture du fichier impossible : \(error.localizedDescription)")
        }
    }

    func importJSON(from data: Data, historyManager: HistoryManager) {
        self.historyManager = historyManager

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    self.cardID = json["cardID"] as? UInt64 ?? 0
                    self.tagIcc = json["icc"] as? String ?? ""
                    self.tagEnvHolder = json["envHolder"] as? [String: Any] ?? [:]
                    self.tagContracts = json["contracts"] as? [[String: Any]] ?? []
                    self.tagEvents = json["events"] as? [[String: Any]] ?? []
                    self.tagSpecialEvents = json["specialEvents"] as? [[String: Any]] ?? []
                    self.isReadComplete = true

                    self.historyManager?.saveScan(
                        cardID: self.cardID,
                        icc: self.tagIcc,
                        env: self.tagEnvHolder,
                        contracts: self.tagContracts,
                        events: self.tagEvents,
                        specialEvents: self.tagSpecialEvents
                    )
                }
            }
        } catch {
            print("Failed to parse imported JSON: \(error)")
        }
    }

    func beginScanning(historyManager: HistoryManager) {
        // Pas de NFC hors iOS : les cartes y arrivent par import.
        #if os(iOS)
        guard NFCTagReaderSession.readingAvailable else { return }

        JournalNFC.shared.commencer()
        self.historyManager = historyManager

        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: DispatchQueue.main)
        session?.alertMessage = "Placez votre passe sur la cible pendant quelques secondes."
        session?.begin()
        isScanning = true

        // La position n'a de sens que prise maintenant : c'est l'instant le plus
        // proche de la validation qu'on puisse atteindre.
        LocationProvider.shared.captureForScan()

        clearData()
        #endif
    }

    func clearData() {
        DispatchQueue.main.async {
            self.cardID = 0
            self.tagIcc = ""
            self.tagEnvHolder = [:]
            self.tagContracts = []
            self.tagEvents = []
            self.tagSpecialEvents = []
            self.isReadComplete = false
            self.isTagDetected = false
        }
    }
}

#if os(iOS)
extension NFCReader: NFCTagReaderSessionDelegate {
    /// Le type d'un tag détecté, pour le journal.
    private static func sorteDeTag(_ tag: NFCTag) -> String {
        switch tag {
        case .iso7816(let carte): return "ISO 7816 (\(hexadecimalDesOctets(carte.identifier)))"
        case .miFare:             return "MIFARE"
        case .feliCa:             return "FeliCa"
        case .iso15693:           return "ISO 15693"
        @unknown default:         return "inconnu"
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        JournalNFC.shared.noter(.etape, "Session active : en attente d'une carte")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        JournalNFC.shared.noter(.etape, "Session fermée (\((error as NSError).code)) : \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        // Seule une carte ISO 7816 porte une application Calypso : un ticket
        // carton ou une carte Mifare n'a rien à lire ici. La feuille l'annonçait
        // en anglais, description de débogage comprise.
        JournalNFC.shared.noter(.etape, "Carte détectée : \(tags.map(Self.sorteDeTag).joined(separator: ", "))")
        guard let tag = tags.first(where: { if case .iso7816 = $0 { return true } else { return false } }),
              case let .iso7816(carte) = tag else {
            JournalNFC.shared.noter(.erreur, "Pas de carte ISO 7816 : rien à lire")
            session.invalidate(errorMessage: "Cette carte n'est pas un passe Navigo.")
            return
        }

        session.connect(to: tag) { error in
            if let error {
                JournalNFC.shared.noter(.erreur, "Connexion perdue : \(error.localizedDescription) — nouvelle recherche")
                // La carte a bougé pendant la connexion. Sans relance, la feuille
                // restait ouverte sans plus rien chercher jusqu'à expirer.
                session.alertMessage = "Passe perdu. Replacez-le sur la cible."
                session.restartPolling()
                return
            }

            session.alertMessage = "Lecture en cours..."
            // La file de la session est la principale : on est déjà au bon
            // endroit pour toucher à l'état publié.
            self.isTagDetected = true

            Task { @MainActor in
                do {
                    session.alertMessage = "⚪️⚪️⚪️⚪️⚪️⚪️⚪️"
                    JournalNFC.shared.noter(.etape, "Sélection de l'application Navigo")
                    self.tagIcc = try await selectAID(carte, Data([0xA0, 0x00, 0x00, 0x04, 0x04, 0x01, 0x25, 0x09, 0x01, 0x01]))
                    self.cardID = interpretCardID(self.tagIcc)
                    // La carte a répondu en passe Navigo : une légère vibration
                    // dit qu'elle est bien lue, et qu'il faut la laisser en place.
                    // Pas avant — une carte bancaire vibrerait, puis serait
                    // refusée.
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    session.alertMessage = "🔵⚪️⚪️⚪️⚪️⚪️⚪️"
                    JournalNFC.shared.noter(.etape, "Environnement et porteur (SFI 07)")
                    self.tagEnvHolder = parseStructure(bitstring: try await readRecord(carte, 1, 0x07), element: IntercodeEnvHolder).0 as! [String: Any]

                    // Counters
                    session.alertMessage = "🔵🔵⚪️⚪️⚪️⚪️⚪️"
                    JournalNFC.shared.noter(.etape, "Compteurs (SFI 19)")
                    let countersBitstring = try await readRecord(carte, 1, 0x19)
                    var countersBitstrings: [String] = []
                    for i in 0...3 {
                        countersBitstrings.append(String(countersBitstring.dropFirst(i * 24).prefix(24)))
                    }

                    // Contract List
                    session.alertMessage = "🔵🔵🔵⚪️⚪️⚪️⚪️"
                    JournalNFC.shared.noter(.etape, "Liste des contrats (SFI 1E)")
                    let contractListContainer = parseStructure(bitstring: try await readRecord(carte, 1, 0x1E), element: IntercodeContractList).0 as! [String: Any]
                    let contractList = contractListContainer["ContractList"] as? [[String: Any]] ?? []

                    // Contracts
                    session.alertMessage = "🔵🔵🔵🔵⚪️⚪️⚪️"
                    JournalNFC.shared.noter(.etape, "Contrats (SFI 09)")
                    for i in 1...4 {
                        guard let contractBitstring = try await lireSiPresent(carte, UInt8(i), 0x09) else { continue }
                        var parsedContract = parseStructure(bitstring: contractBitstring, element: IntercodeContract).0 as! [String: Any]
                        guard (getBitmapCount(parsedContract, "ContractBitmap") ?? 0) > 0 else { continue }

                        if let validityJourneysBitstring = getKey(parsedContract, "ContractValidityJourneys") {
                            let isProprietary = validityJourneysBitstring.first == "0"
                            if !isProprietary {
                                let CounterStructureNumber = String(validityJourneysBitstring.dropFirst(1).prefix(5))
                                let CounterLastLoad = String(validityJourneysBitstring.suffix(8))

                                if let counterStructure = IntercodeCounters[Int(CounterStructureNumber, radix: 2) ?? 0] {
                                    let parsedCounter = parseStructure(bitstring: countersBitstrings[i - 1], element: counterStructure).0 as! [String: Any]

                                    let counterDict: [String: Any] = [
                                        "CounterStructureNumber": CounterStructureNumber,
                                        "CounterLastLoad": CounterLastLoad
                                    ].merging(parsedCounter) { (_, new) in new }

                                    parsedContract["Counter"] = counterDict
                                }
                            }
                        }
                        parsedContract[cleEmplacementContrat] = String(i, radix: 2)
                        // L'entrée de la liste qui désigne cet emplacement porte la
                        // priorité du titre. Son pointeur est rangé sous
                        // ContractListBitmap : lu à plat, il ne répondait jamais, et
                        // plus aucun contrat n'avait de priorité.
                        if let entree = contractList.first(where: { Int(getKey($0, "ContractListPointer") ?? "", radix: 2) == i }) {
                            parsedContract["BetterContract"] = entree
                        }
                        self.tagContracts.append(parsedContract)
                    }

                    // Events
                    session.alertMessage = "🔵🔵🔵🔵🔵⚪️⚪️"
                    JournalNFC.shared.noter(.etape, "Événements (SFI 08)")
                    for i in 1...3 {
                        guard let eventBitstring = try await lireSiPresent(carte, UInt8(i), 0x08) else { continue }
                        let parsedEvent = parseStructure(bitstring: eventBitstring, element: IntercodeEvent).0 as! [String: Any]
                        if ((getBitmapCount(parsedEvent, "EventBitmap") ?? 0) > 0) && (interpretInt(getKey(parsedEvent, "EventContractPointer") ?? "") > 0) {
                            self.tagEvents.append(parsedEvent)
                        }
                    }

                    // Special Events
                    session.alertMessage = "🔵🔵🔵🔵🔵🔵⚪️"
                    JournalNFC.shared.noter(.etape, "Événements spéciaux (SFI 1D)")
                    for i in 1...3 {
                        guard let eventBitstring = try await lireSiPresent(carte, UInt8(i), 0x1D) else { continue }
                        let parsedEvent = parseStructure(bitstring: eventBitstring, element: IntercodeEvent).0 as! [String: Any]
                        if ((getBitmapCount(parsedEvent, "EventBitmap") ?? 0) > 0) {
                            self.tagSpecialEvents.append(parsedEvent)
                        }
                    }
                    // Chaque validation garde une copie du titre qu'elle désigne, tel que
                    // la carte le porte maintenant : relue plus tard dans une fiche
                    // d'historique, elle ne dépendra plus des contrats d'un scan suivant.
                    self.tagEvents = self.tagEvents.map { figerContratPaye($0, parmi: self.tagContracts) }
                    self.tagSpecialEvents = self.tagSpecialEvents.map { figerContratPaye($0, parmi: self.tagContracts) }
                    session.alertMessage = "🔵🔵🔵🔵🔵🔵🔵"
                    // Seul endroit qui marque la lecture complète : le
                    // `catch` plus bas invalide aussi la session, mais sans
                    // passer par ici, et l'abandon par l'utilisateur non plus.
                    self.isReadComplete = true
                    JournalNFC.shared.noter(.etape, "Lecture complète : \(self.tagContracts.count) contrat(s), \(self.tagEvents.count) événement(s), \(self.tagSpecialEvents.count) spécial(aux)")
                    session.invalidate()

                    self.historyManager?.saveScan(
                        cardID: self.cardID,
                        icc: self.tagIcc,
                        env: self.tagEnvHolder,
                        contracts: self.tagContracts,
                        events: self.tagEvents,
                        specialEvents: self.tagSpecialEvents
                    )
                } catch {
                    JournalNFC.shared.noter(.erreur, "Échec : \(messageDEchec(error)) — \(error)")
                    session.invalidate(errorMessage: messageDEchec(error))
                }
            }
        }
    }
}
#endif
