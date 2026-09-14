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
    /// Le contenu du fichier .metropass, préparé seulement au partage.
    var export: (() -> Data?)?

    /// Vrai quand la fiche vient de l'historique. Le contrôle se juge à
    /// l'instant où l'on est devant l'agent : sur un scan d'il y a trois jours,
    /// il ne dit plus rien de vrai. Les deux autres timers, eux, décrivent
    /// l'état du pass et gardent leur sens.
    var depuisHistorique: Bool = false
    
    @ObservedObject var historyManager: HistoryManager
    
    @State private var showAllContracts = false
    @State private var showAllSpecialEvents = false
    /// Vrai quand la fiche du pass, telle que l'historique la garde, est
    /// ouverte par-dessus la carte lue.
    @State private var ficheOuverte = false
    /// La préparation des voyages quand elle court : la ligne montre alors un
    /// sablier à la place de sa flèche.
    @State private var preparationDesVoyages: Task<Void, Never>?
    /// Les voyages préparés, et la page qui les montre.
    @State private var voyages: ValidationHistoryView.Preparation?
    @State private var voyagesOuverts = false
    /// La largeur d'une section, où l'aperçu de carte des voyages se
    /// photographie d'avance. Retenue sans redessiner la fiche.
    @State private var mesure = Mesure()
    @Environment(\.colorScheme) private var apparence
    @Environment(\.displayScale) private var echelle
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

    /// De combien la carte remonte vers la barre du haut. La barre garde la
    /// place d'un grand titre qu'elle n'affiche pas, que `contentMargins` ne
    /// réduit pas : sans ça, 62 pt séparaient la carte des boutons.
    private static let remonteeCarte: CGFloat = 40

    /// De combien elle redescend en arrivant, depuis le haut où l'animation
    /// l'avait emmenée. La carte posée plus haut, le trajet raccourcit d'autant
    /// pour partir du même point.
    private static let monteeArrivee: CGFloat = 150 - remonteeCarte

    @AppStorage(TimerSettings.control) private var controlTimerEnabled = true
    @AppStorage(TimerSettings.controlOutline) private var controlOutlineEnabled = true
    @AppStorage(TimerSettings.controlMode) private var controlMode = ControlMode.automatique.rawValue
    @AppStorage(TimerSettings.controlTolerance) private var toleranceEnabled = true
    @AppStorage(TimerSettings.controlToleranceMinutes) private var toleranceMinutes = TimerSettings.defaultToleranceMinutes
    /// Lu ici pour que la fiche se redessine quand le mode debug le bascule.
    @AppStorage(ModeDebug.transitionsBrutes) private var transitionsBrutes = false
    @AppStorage(ModeDebug.deverrouille) private var modeDebug = false

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

    /// Le double toucher sur la carte. Sur la carte lue, il pousse sa fiche de
    /// l'historique par-dessus : le geste de retour ramène à la carte lue.
    /// Dans l'historique, où l'on est déjà, il change son image.
    private func doubleToucherLaCarte() {
        guard canPersonalize else { return }
        if depuisHistorique {
            showingImagePicker = true
        } else {
            ficheOuverte = true
        }
    }
    
    /// Range les voyages et photographie leur carte hors du fil principal,
    /// puis ouvre la page, remplie. Poussée d'un coup, elle figeait l'écran à
    /// sa première ouverture : le toucher ne s'animait pas, et rien ne disait
    /// qu'on attendait.
    private func reconstituerLesVoyages() {
        guard preparationDesVoyages == nil else { return }
        let events = tagEvents, contrats = tagContracts
        // Sans carte du pass mesurée, la page photographie sa carte elle-même.
        let apercu = mesure.largeur > 0 ? CGSize(width: mesure.largeur, height: ApercuDeCarte.hauteur) : nil
        let sombre = apparence == .dark, echelle = self.echelle
        preparationDesVoyages = Task {
            let preparation = await ValidationHistoryView.preparer(events: events, contrats: contrats,
                                                                   apercu: apercu, sombre: sombre, echelle: echelle)
            guard !Task.isCancelled else { return }
            voyages = preparation
            voyagesOuverts = true
        }
    }

    private var preferredContractIndex: Int? {
        ordreDesContrats(tagContracts).first { isContractBest(tagContracts[$0], tagContracts) }
    }

    private var displayedContractsIndices: [Int] {
        let ordre = ordreDesContrats(tagContracts)

        // Sans contrat préféré, on affiche tout d'emblée
        guard let bestIndex = preferredContractIndex else { return ordre }

        // Le contrat retenu garde sa place en tête : déplier ajoute les autres
        // en dessous de lui, au lieu de le faire glisser dans la liste.
        guard showAllContracts else { return [bestIndex] }
        return [bestIndex] + ordre.filter { $0 != bestIndex }
    }

    /// Ce que le dépliage ferait apparaître, et non le nombre total de contrats
    private var hiddenContractsCount: Int {
        preferredContractIndex == nil ? 0 : tagContracts.count - 1
    }
    
    private var displayedEventsIndices: [Int] {
        // Les trois dernières ; le reste se lit trajet par trajet, en
        // reconstituant les voyages depuis l'historique.
        Array(Array(0..<tagEvents.count).prefix(3))
    }

    /// Les trois premiers ; déplier ajoute les autres en dessous.
    private var displayedSpecialEventsIndices: [Int] {
        let allIndices = Array(tagSpecialEvents.indices)
        return showAllSpecialEvents ? allIndices : Array(allIndices.prefix(3))
    }
    
    
    /// Le coin droit sur iPhone ; ailleurs, le système place.
    private static var placementDesActions: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .automatic
        #endif
    }

    /// Le jour qui nomme le fichier exporté, formaté par un seul formateur plutôt
    /// que par un neuf à chaque rendu.
    private static let jourDExport: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    var body: some View {
        // Une lecture des validations pour toute la fiche : chaque ligne y puise
        // sa transition sans relire les autres.
        let validations = Validations(tagEvents, contrats: tagContracts, brutes: transitionsBrutes)
        List {
            Section(header:
                ZStack(alignment: .bottomLeading) {
                    if let holderCardStatus = getKey(tagEnvHolder, "HolderDataCardStatus"), let holderCommercialId = getKey(tagEnvHolder, "HolderDataCommercialID") {
                        NavigoImage(imageName: historyManager.history.first(where: { $0.cardID == cardID })?.image ?? interpretNavigoImage(holderCardStatus, getKey(tagEnvHolder, "EnvApplicationIssuerId") ?? "", holderCommercialId, tagContracts))
                            .shadow(radius: 2)
                            // La carte du pass tient toute la largeur d'une
                            // section : c'est celle de l'aperçu des voyages.
                            .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { mesure.largeur = $0 }
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
                            .onTapGesture(count: 2) { doubleToucherLaCarte() }
                    }
                }
                // La carte reprend la course là où l'écran vide l'a laissée :
                // elle redescend du haut en grandissant jusqu'à sa taille.
                // Depuis l'historique, pas d'écran vide, et la page glisse déjà
                // de la droite : la carte semblait tomber du coin. Elle y est
                // posée d'emblée.
                .scaleEffect(carteEnPlace || depuisHistorique ? 1 : Self.echelleArrivee)
                .offset(y: carteEnPlace || depuisHistorique ? 0 : -Self.monteeArrivee)
                .padding(.top, -Self.remonteeCarte)
            ) {}
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            
            // Sans contrat ni événement non plus : un pass neuf n'ouvre aucun
            // droit, et le dire est le seul renseignement qu'on ait à donner.
            TimersDeLaCarte(contracts: tagContracts, events: tagEvents, sansControle: depuisHistorique)

            // Dans l'historique seulement : sur une carte qu'on vient de lire,
            // on regarde son titre, pas ses voyages. La vignette ne montre pas
            // ces voyages, seulement qu'une carte attend derrière : une image
            // fixe, rien à calculer.
            if depuisHistorique, !tagEvents.isEmpty {
                Section {
                    // Un bouton plutôt qu'un lien : la page ne s'ouvre qu'une
                    // fois prête, et le sablier prend la place de la flèche en
                    // attendant.
                    Button(action: reconstituerLesVoyages) {
                        HStack {
                            Text("Reconstituer les voyages")
                            Spacer()
                            Image("CarteParis")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)
                            // La flèche d'un lien, qu'un bouton n'a pas, à la
                            // taille et à la place de celle des contrats. Le
                            // sablier se pose dessus sans rien décaler.
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.trailing, 1.5)
                                .opacity(preparationDesVoyages == nil ? 1 : 0)
                                .overlay {
                                    if preparationDesVoyages != nil {
                                        ProgressView()
                                    }
                                }
                        }
                    }
                    // Les couleurs d'une ligne, pas le bleu d'un bouton.
                    .tint(.primary)
                }
            }

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
                        NavigationLink {
                            EventView(eventInfo: tagEvents[i], transition: validations.transition(de: i),
                                      regle: validations.regle(de: i), contractsInfos: tagContracts)
                        } label: {
                            EventPreview(eventInfo: tagEvents[i], transition: validations.transition(de: i))
                        }
                    }
                }
                
            }
            
            if tagSpecialEvents.count > 0 {
                Section(header: Text("Evènements spéciaux")) {
                    ForEach(displayedSpecialEventsIndices, id: \.self) { i in
                        NavigationLink {
                            EventView(eventInfo: tagSpecialEvents[i], contractsInfos: tagContracts)
                        } label: {
                            EventPreview(eventInfo: tagSpecialEvents[i])
                        }
                    }

                    if tagSpecialEvents.count > displayedSpecialEventsIndices.count {
                        Button(action: {
                            withAnimation { showAllSpecialEvents = true }
                        }) {
                            HStack {
                                Text("Voir tout...")
                                Spacer()
                                Text("\(tagSpecialEvents.count - displayedSpecialEventsIndices.count)")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            if !tagEnvHolder.isEmpty {
                Section(header: Text("Environnement")) {
                    EnvHolderView(envHolderInfo: tagEnvHolder, cardID: cardID)
                }
            }

            if modeDebug {
                DebugDesTimers(contracts: tagContracts, events: tagEvents)
            }
        }
        #if os(iOS)
        // Grand titre, même vide : venue d'une page sans titre, la fiche
        // héritait d'une barre compacte, et la carte remontée passait sous les
        // boutons.
        .navigationBarTitleDisplayMode(.large)
        #endif
        .navigationDestination(isPresented: $ficheOuverte) {
            if let fiche = historyManager.history.first(where: { $0.cardID == cardID }) {
                ScanView(
                    cardID: fiche.cardID,
                    tagIcc: fiche.icc,
                    tagEnvHolder: fiche.envHolder,
                    tagContracts: fiche.contracts,
                    tagEvents: fiche.events,
                    tagSpecialEvents: fiche.specialEvents,
                    export: fiche.export,
                    depuisHistorique: true,
                    historyManager: historyManager
                )
            }
        }
        .navigationDestination(isPresented: $voyagesOuverts) {
            ValidationHistoryView(events: tagEvents, contracts: tagContracts, preparation: voyages)
        }
        // Couverte par la page des voyages, la fiche rend sa flèche à la ligne :
        // au retour, plus de sablier. Quittée en pleine préparation, elle
        // n'ouvre plus rien.
        .onDisappear {
            preparationDesVoyages?.cancel()
            preparationDesVoyages = nil
        }
        .task {
            // Depuis l'historique, la carte est posée d'emblée et sans contour :
            // rien à animer, et chaque changement d'état redessinait la fiche
            // pendant qu'elle glissait.
            guard !depuisHistorique else { return }
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
                    let record = historyManager.history.first(where: { $0.cardID == cardID })

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

            // Les mêmes actions sur iPhone et sur Mac, recopiées jusque-là pour
            // un seul emplacement qui change.
            ToolbarItemGroup(placement: Self.placementDesActions) {
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

                if !tagEnvHolder.isEmpty, let export {
                    ShareLink(
                        item: ExportFile(fileName: "\(cardID)_\(Self.jourDExport.string(from: Date())).metropass", contenu: export),
                        preview: SharePreview("Données Navigo \(cardID)")
                    )
                } else {
                    // Optional: Disabled placeholder so the UI doesn't "jump"
                    Label("Exporter", systemImage: "square.and.arrow.up")
                        .opacity(0.5)
                }
            }
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

/// Les timers de la carte, calculés ici plutôt que dans la fiche.
///
/// `PassTimers` relit toutes les validations, et la fiche se redessine à chaque
/// changement de son état — la préparation des voyages, la page qui s'ouvre.
/// Sur 325 validations, c'était l'essentiel de son rendu, au moment même où la
/// page glissait. Les entrées de cette vue-ci ne changent pas : SwiftUI ne
/// refait pas son corps.
private struct TimersDeLaCarte: View {
    let contracts: [[String: Any]]
    let events: [[String: Any]]
    let sansControle: Bool

    var body: some View {
        TimersView(timers: PassTimers(contracts: contracts, events: events), sansControle: sansControle)
    }
}

/// Une mesure gardée d'un rendu à l'autre sans en provoquer.
private final class Mesure {
    var largeur: CGFloat = 0
}

#Preview {
    ScanView(cardID: 0, tagIcc: "", tagEnvHolder: [:], tagContracts: [], tagEvents: [], tagSpecialEvents: [], historyManager: HistoryManager())
}
