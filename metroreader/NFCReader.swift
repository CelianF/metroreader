//
//  NFCReader.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import Foundation
#if os(iOS)
import CoreNFC
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
/// Envoie une commande et rend la réponse en bits, ou lève le mot d'état que la
/// carte a opposé.
private func envoyer(_ tag: NFCISO7816Tag, _ apdu: NFCISO7816APDU) async throws -> String {
    let (response, sw1, sw2) = try await tag.sendCommand(apdu: apdu)
    switch (sw1, sw2) {
    case (0x90, 0x00):
        return bits(response)
    case (0x6A, 0x82):
        throw NSError(domain: "Application not found", code: 0x6A82, userInfo: nil)
    case (0x6A, 0x83):
        throw NSError(domain: "Record not found", code: 0x6A83, userInfo: nil)
    default:
        throw NSError(domain: "Unexpected status word", code: Int(sw1) << 8 | Int(sw2), userInfo: ["sw1": sw1, "sw2": sw2])
    }
}

private func selectAID(_ tag: NFCISO7816Tag, _ aidData: Data) async throws -> String {
    try await envoyer(tag, NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xA4, p1Parameter: 0x04, p2Parameter: 0x00, data: aidData, expectedResponseLength: -1))
}

private func readRecord(_ tag: NFCISO7816Tag, _ recordId: UInt8, _ sfi: UInt8) async throws -> String {
    try await envoyer(tag, NFCISO7816APDU(data: Data([0x00, 0xB2, recordId, sfi << 3 | 4, 0x00]))!)
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

    var exportDataAsJSON: Data? {
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

        // Safety check to ensure the dictionary can actually be made into JSON
        guard JSONSerialization.isValidJSONObject(dict) else {
            print("Error: Dictionary contains types that are not JSON compatible.")
            return nil
        }

        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
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
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        var nfcIso7816Tag: NFCISO7816Tag? = nil
        var nfcTag: NFCTag? = nil

        for tag in tags {
            if nfcTag == nil {
                nfcTag = tag
            }
            if case let .iso7816(cTag) = tag {
                nfcIso7816Tag = cTag
                nfcTag = tag
            }
        }

        if nfcIso7816Tag == nil {
            session.invalidate(errorMessage: "Card not supported: \(nfcTag.debugDescription)")
            return
        }

        session.connect(to: nfcTag!) { (error) in
            if error != nil {
                return
            }

            guard let nfcIso7816Tag = nfcIso7816Tag else {
                return
            }

            session.alertMessage = "Lecture en cours..."
            // La file de la session est la principale : on est déjà au bon
            // endroit pour toucher à l'état publié.
            self.isTagDetected = true

            DispatchQueue.main.async {
                Task {
                    do {
                        session.alertMessage = "⚪️⚪️⚪️⚪️⚪️⚪️⚪️"
                        self.tagIcc = try await selectAID(nfcIso7816Tag, Data([0xA0, 0x00, 0x00, 0x04, 0x04, 0x01, 0x25, 0x09, 0x01, 0x01]))
                        self.cardID = interpretCardID(self.tagIcc)

                        session.alertMessage = "🔵⚪️⚪️⚪️⚪️⚪️⚪️"
                        self.tagEnvHolder = parseStructure(bitstring: try await readRecord(nfcIso7816Tag, 1, 0x07), element: IntercodeEnvHolder).0 as! [String: Any]

                        // Counters
                        session.alertMessage = "🔵🔵⚪️⚪️⚪️⚪️⚪️"
                        let countersBitstring = try await readRecord(nfcIso7816Tag, 1, 0x19)
                        var countersBitstrings: [String] = []
                        for i in 0...3 {
                            countersBitstrings.append(String(countersBitstring.dropFirst(i * 24).prefix(24)))
                        }

                        // Contract List
                        session.alertMessage = "🔵🔵🔵⚪️⚪️⚪️⚪️"
                        let contractListContainer = parseStructure(bitstring: try await readRecord(nfcIso7816Tag, 1, 0x1E), element: IntercodeContractList).0 as! [String: Any]
                        let contractList = contractListContainer["ContractList"] as! [[String: Any]]

                        // Contracts
                        session.alertMessage = "🔵🔵🔵🔵⚪️⚪️⚪️"
                        for i in 1...4 {
                            do {
                                var parsedContract = parseStructure(bitstring: try await readRecord(nfcIso7816Tag, UInt8(i), 0x09), element: IntercodeContract).0 as! [String: Any]
                                if ((getBitmapCount(parsedContract, "ContractBitmap") ?? 0) > 0) {
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
                                    // L'entrée de la liste qui désigne cet emplacement porte la
                                    // priorité du titre. Son pointeur est rangé sous
                                    // ContractListBitmap : lu à plat, il ne répondait jamais, et
                                    // plus aucun contrat n'avait de priorité.
                                    if let entree = contractList.first(where: { Int(getKey($0, "ContractListPointer") ?? "", radix: 2) == i }) {
                                        parsedContract["BetterContract"] = entree
                                    }

                                    self.tagContracts.append(parsedContract)
                                }
                            } catch {
                                // Emplacement absent de la carte
                            }
                        }

                        // Events
                        session.alertMessage = "🔵🔵🔵🔵🔵⚪️⚪️"
                        for i in 1...3 {
                            let parsedEvent = parseStructure(bitstring: try await readRecord(nfcIso7816Tag, UInt8(i), 0x08), element: IntercodeEvent).0 as! [String: Any]
                            if ((getBitmapCount(parsedEvent, "EventBitmap") ?? 0) > 0) && (interpretInt(getKey(parsedEvent, "EventContractPointer") ?? "") > 0) {
                                self.tagEvents.append(parsedEvent)
                            }
                        }

                        // Special Events
                        session.alertMessage = "🔵🔵🔵🔵🔵🔵⚪️"
                        for i in 1...3 {
                            do {
                                let parsedEvent = parseStructure(bitstring: try await readRecord(nfcIso7816Tag, UInt8(i), 0x1D), element: IntercodeEvent).0 as! [String: Any]
                                if ((getBitmapCount(parsedEvent, "EventBitmap") ?? 0) > 0) {
                                    self.tagSpecialEvents.append(parsedEvent)
                                }
                            } catch {
                                // Emplacement absent de la carte
                            }
                        }
                        session.alertMessage = "🔵🔵🔵🔵🔵🔵🔵"
                        // Seul endroit qui marque la lecture complète : le
                        // `catch` plus bas invalide aussi la session, mais sans
                        // passer par ici, et l'abandon par l'utilisateur non plus.
                        self.isReadComplete = true
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
                        print("Lecture interrompue : \(error)")
                        session.invalidate()
                    }
                }
            }
        }
    }
}
#endif
