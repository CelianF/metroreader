//
//  ScanView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//

import SwiftUI

struct ScanView: View {
    let cardID: UInt64
    let tagIcc: String
    let tagEnvHolder: [String: Any]
    let tagContracts: [[String: Any]]
    let tagEvents: [[String: Any]]
    let tagSpecialEvents: [[String: Any]]
    var exportDataAsJSON: Data?

    /// Vrai quand la fiche vient de l'historique. Le contrôle se juge à
    /// l'instant où l'on est devant l'agent : sur un scan d'il y a trois jours,
    /// il ne dit plus rien de vrai. Les deux autres timers, eux, décrivent
    /// l'état du pass et gardent leur sens.
    var depuisHistorique: Bool = false
    
    @ObservedObject var historyManager: HistoryManager
    
    @State private var showAllContracts = false
    @State private var showAllEvents = false
    @State private var showingRenameAlert = false
    @State private var newNickname = ""
    @State private var showingImagePicker = false

    /// Le contour dit la validité à l'instant où la carte s'affiche — c'est là
    /// qu'on la regarde. Passé quelques secondes il n'apprend plus rien et ne
    /// fait que masquer le visuel, alors il s'efface. Il n'apparaît qu'une fois
    /// la carte posée : dessiné sur une carte encore en vol, il n'aurait rien
    /// à cerner.
    @State private var outlineShown = false

    /// Faux tant que la carte n'a pas rejoint sa place et sa taille.
    @State private var carteEnPlace = false

    private static let outlineLifetime: Duration = .seconds(10)
    private static let outlineFade: Double = 1.5

    /// La carte entre à la taille qu'elle avait dans l'animation de l'écran
    /// vide, pour prendre sa suite sans rupture : là-bas 0,55 × 0,72 du côté de
    /// la cible, soit 134 pt, ici 370 pt de large. Le rapport tient d'un modèle
    /// à l'autre, les deux largeurs dérivant de celle de l'écran.
    private static let echelleArrivee: CGFloat = 0.36

    /// De combien elle redescend en arrivant, depuis le haut où l'animation
    /// l'avait emmenée.
    private static let monteeArrivee: CGFloat = 150

    @AppStorage(TimerSettings.control) private var controlTimerEnabled = true
    @AppStorage(TimerSettings.controlOutline) private var controlOutlineEnabled = true
    @AppStorage(TimerSettings.controlMode) private var controlMode = ControlMode.automatique.rawValue
    @AppStorage(TimerSettings.controlTolerance) private var toleranceEnabled = true
    @AppStorage(TimerSettings.controlToleranceMinutes) private var toleranceMinutes = TimerSettings.defaultToleranceMinutes

    // La carte des événements et les libellés d'arrêt suivent le journal des
    // saisies : ce qui vient d'être identifié apparaît sans changer d'écran.
    @ObservedObject private var entries = ManualEntries.shared

    /// Dort, et dit si la tâche a survécu — faux quand elle a été annulée.
    private func patiente(_ duree: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duree)
            return true
        } catch {
            return false
        }
    }

    private var timers: PassTimers {
        PassTimers(contracts: tagContracts, events: tagEvents)
    }

    // Contour du visuel : la couleur de l'encart Contrôle, portée sur la carte
    // pour qu'un coup d'œil suffise.
    private var validityOutline: (color: Color, glow: CGFloat)? {
        // Le contour dit la même chose que l'encart Contrôle, en plus criant :
        // le taire dans l'historique et garder son halo rouge reviendrait à
        // juger quand même un scan d'il y a trois jours.
        guard !depuisHistorique, controlTimerEnabled, controlOutlineEnabled else { return nil }
        let validity = timers.validity(
            mode: ControlMode(rawValue: controlMode) ?? .automatique,
            tolerance: toleranceEnabled ? TimeInterval(toleranceMinutes) * 60 : nil
        )
        return (validity.color, validity.glow)
    }

    /// Renommer le pass et changer son image n'existent que dans l'historique :
    /// sans fiche enregistrée, la saisie n'aurait nulle part où être écrite et
    /// serait perdue à la fermeture. Historique éteint, il n'y a pas de fiche.
    private var canPersonalize: Bool {
        cardID != 0 && historyManager.history.contains { $0.cardID == cardID }
    }
    
    private var preferredContractIndex: Int? {
        Array(0..<tagContracts.count).first { isContractBest(tagContracts[$0], tagContracts) }
    }

    private var displayedContractsIndices: [Int] {
        let allIndices = Array(0..<tagContracts.count)

        // Sans contrat préféré, on affiche tout d'emblée
        guard let bestIndex = preferredContractIndex else { return allIndices }

        // Le contrat retenu garde sa place en tête : déplier ajoute les autres
        // en dessous de lui, au lieu de le faire glisser dans la liste.
        guard showAllContracts else { return [bestIndex] }
        return [bestIndex] + allIndices.filter { $0 != bestIndex }
    }

    /// Ce que le dépliage ferait apparaître, et non le nombre total de contrats
    private var hiddenContractsCount: Int {
        preferredContractIndex == nil ? 0 : tagContracts.count - 1
    }
    
    private var displayedEventsIndices: [Int] {
        let allIndices = Array(0..<tagEvents.count)
        if showAllEvents {
            return allIndices
        } else {
            return Array(allIndices.prefix(3))
        }
    }
    
    private var stationsToDisplay: [NavigoStationInfo] {
        // 1. On récupère les événements concernés
        let relevantEvents = showAllEvents ? tagEvents : Array(tagEvents.prefix(3))
        
        // 2. On mappe vers les infos de station
        return relevantEvents.compactMap { event -> NavigoStationInfo? in
            let locId = getKey(event, "EventLocationId") ?? ""
            let code = getKey(event, "EventCode") ?? ""
            let provider = getKey(event, "EventServiceProvider") ?? ""
            let route = getKey(event, "EventRouteNumber")
            
            let location = interpretLocationId(locId, code, provider, route)
            return location.isLocatable ? location : nil
        }
    }
    
    var body: some View {
        List {
            Section(header:
                ZStack(alignment: .bottomLeading) {
                    if let holderCardStatus = getKey(tagEnvHolder, "HolderDataCardStatus"), let holderCommercialId = getKey(tagEnvHolder, "HolderDataCommercialID") {
                        NavigoImage(imageName: historyManager.history.first(where: { $0.cardID == cardID })?.image ?? interpretNavigoImage(holderCardStatus, getKey(tagEnvHolder, "EnvApplicationIssuerId") ?? "", holderCommercialId, tagContracts))
                            .shadow(radius: 2)
                            .overlay {
                                if let outline = validityOutline {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(outline.color, lineWidth: 3)
                                        .shadow(color: outline.color, radius: outline.glow)
                                        .shadow(color: outline.color.opacity(0.6), radius: outline.glow)
                                        .opacity(outlineShown ? 1 : 0)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onTapGesture(count: 2) {
                                if canPersonalize { showingImagePicker = true }
                            }
                        VStack(alignment: .leading) {
                            switch interpretNavigoPersonalizationStatusCode(holderCardStatus) {
                            case "Navigo Annuel":
                                Text("A")
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.black)
                                    .allowsHitTesting(false)
                            case "Navigo Imagine R":
                                Text("I")
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.black)
                                    .allowsHitTesting(false)
                            default:
                                Spacer(minLength: 0.0)
                                    .allowsHitTesting(false)
                            }
                            if cardID != 0 {
                                Text("\(cardID)")
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.black)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding()
                    }
                }
                // La carte reprend la course là où l'écran vide l'a laissée :
                // elle redescend du haut en grandissant jusqu'à sa taille.
                .scaleEffect(carteEnPlace ? 1 : Self.echelleArrivee)
                .offset(y: carteEnPlace ? 0 : -Self.monteeArrivee)
            ) {}
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            
            // Sans contrat ni événement non plus : un pass neuf n'ouvre aucun
            // droit, et le dire est le seul renseignement qu'on ait à donner.
            TimersView(timers: timers, sansControle: depuisHistorique)
            
            if tagContracts.count > 0 {
                Section(header: Text("Contrats")) {
                    ForEach(displayedContractsIndices, id: \.self) { i in
                        NavigationLink {
                            ContractView(contractInfo: tagContracts[i])
                        } label: {
                            ContractPreview(
                                contractInfo: tagContracts[i],
                                isPreferred: isContractBest(tagContracts[i], tagContracts),
                                isDisabled: isContractDisabled(tagContracts[i])
                            )
                        }
                    }
                    
                    if !showAllContracts && hiddenContractsCount > 0 {
                        Button(action: {
                            withAnimation { showAllContracts = true }
                        }) {
                            HStack {
                                Text("Voir tout...")
                                Spacer()
                                Text("\(hiddenContractsCount)")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            
            if tagEvents.count > 0 {
                Section(header: Text("Derniers évènements")) {
                    ForEach(displayedEventsIndices, id: \.self) { i in
                        // La carte range ses événements du plus récent au plus
                        // ancien : ceux qui précèdent dans la liste ont suivi,
                        // ceux qui viennent après ont précédé.
                        NavigationLink {
                            EventView(eventInfo: tagEvents[i], suivants: Array(tagEvents[..<i]), precedents: Array(tagEvents[(i + 1)...]), contractsInfos: tagContracts)
                        } label: {
                            EventPreview(eventInfo: tagEvents[i], suivants: Array(tagEvents[..<i]), precedents: Array(tagEvents[(i + 1)...]))
                        }
                    }
                    
                    if !showAllEvents && tagEvents.count > displayedEventsIndices.count {
                        Button(action: {
                            withAnimation { showAllEvents = true }
                        }) {
                            HStack {
                                Text("Voir tout...")
                                Spacer()
                                Text("\(tagEvents.count - displayedEventsIndices.count)")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                if !stationsToDisplay.isEmpty {
                    Section {
                        EventsMapView(events: tagEvents, affiches: showAllEvents ? tagEvents.count : 3)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
            }
            
            if tagSpecialEvents.count > 0 {
                Section(header: Text("Evènements spéciaux")) {
                    ForEach(tagSpecialEvents.indices, id: \.self) { i in
                        NavigationLink {
                            EventView(eventInfo: tagSpecialEvents[i], contractsInfos: tagContracts)
                        } label: {
                            EventPreview(eventInfo: tagSpecialEvents[i])
                        }
                    }
                }
            }

            if !tagEnvHolder.isEmpty {
                Section(header: Text("Environnement")) {
                    EnvHolderView(envHolderInfo: tagEnvHolder)
                }
            }
        }
        .task {
            withAnimation(.spring(duration: 0.65, bounce: 0.22)) { carteEnPlace = true }
            // Le contour n'entre qu'une fois la carte immobile et à sa taille.
            guard await patiente(.seconds(0.7)) else { return }
            withAnimation(.easeIn(duration: 0.45)) { outlineShown = true }
            guard await patiente(Self.outlineLifetime) else { return }
            withAnimation(.easeOut(duration: Self.outlineFade)) { outlineShown = false }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if cardID != 0 {
                    let record = historyManager.history.first(where: { $0.cardID == Int(cardID) })
                    
                    Text(record?.displayTitle ?? "")
                        .font(.headline)
                        // Détection du double-clic sur le titre
                        .onTapGesture(count: 2) {
                            guard canPersonalize else { return }
                            #if os(iOS)
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            #endif
                            
                            newNickname = record?.nickname ?? ""
                            showingRenameAlert = true
                        }
                        .help(canPersonalize ? "Double-cliquez pour renommer" : "")
                }
            }
            
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canPersonalize {
                    Menu {
                        Button(action: {
                            newNickname = historyManager.history.first(where: { $0.cardID == cardID })?.nickname ?? ""
                            showingRenameAlert = true
                        }) {
                            Label("Renommer le pass", systemImage: "pencil")
                        }

                        Button(action: { showingImagePicker = true }) {
                            Label("Changer l'image", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label("Modifier le pass", systemImage: "square.and.pencil")
                    }
                }
                
                if !tagEnvHolder.isEmpty, let jsonData = exportDataAsJSON {
                    let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
                    let fileName = "\(cardID)_\(dateStr).metropass"
                    
                    ShareLink(
                        item: ExportFile(data: jsonData, fileName: fileName),
                        preview: SharePreview("Données Navigo \(cardID)")
                    )
                } else {
                    // Optional: Disabled placeholder so the UI doesn't "jump"
                    Label("Exporter", systemImage: "square.and.arrow.up")
                        .opacity(0.5)
                }
            }
            #else
            ToolbarItemGroup {
                if canPersonalize {
                    Menu {
                        Button(action: {
                            newNickname = historyManager.history.first(where: { $0.cardID == cardID })?.nickname ?? ""
                            showingRenameAlert = true
                        }) {
                            Label("Renommer le pass", systemImage: "pencil")
                        }

                        Button(action: { showingImagePicker = true }) {
                            Label("Changer l'image", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label("Modifier le pass", systemImage: "square.and.pencil")
                    }
                }
                
                if !tagEnvHolder.isEmpty, let jsonData = exportDataAsJSON {
                    let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
                    let fileName = "\(cardID)_\(dateStr).metropass"
                    
                    ShareLink(
                        item: ExportFile(data: jsonData, fileName: fileName),
                        preview: SharePreview("Données Navigo \(cardID)")
                    )
                } else {
                    // Optional: Disabled placeholder so the UI doesn't "jump"
                    Label("Exporter", systemImage: "square.and.arrow.up")
                        .opacity(0.5)
                }
            }
            #endif
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerSheet(cardID: cardID, historyManager: historyManager)
                .presentationDetents([.medium, .large]) // Permet une ouverture partielle ou totale
        }
        .alert("Renommer la carte", isPresented: $showingRenameAlert) {
            TextField("Nom", text: $newNickname)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") {
                historyManager.setNickname(for: cardID, to: newNickname)
                newNickname = ""
            }
        }
    }
}

#Preview {
    ScanView(cardID: 0, tagIcc: "", tagEnvHolder: [:], tagContracts: [], tagEvents: [], tagSpecialEvents: [], historyManager: HistoryManager())
}
