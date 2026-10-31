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

    /// Vrai quand la fiche vient de l'historique. La validité se juge à
    /// l'instant où l'on est devant l'agent : sur un scan d'il y a trois jours,
    /// il ne dit plus rien de vrai. Les deux autres timers, eux, décrivent
    /// l'état du pass et gardent leur sens.
    var depuisHistorique: Bool = false
    /// Ce que la fiche montre. Sur le Duo déplié, elle se partage entre deux
    /// panneaux : la carte et ses contrats sous l'antenne, les validations en
    /// face.
    var partie: PartieDeFiche = .tout
    /// Dans la fiche en deux colonnes, un évènement touché s'ouvre dans la
    /// colonne de la carte plutôt que par-dessus toute la page.
    var ouvrir: ((OuvertureDansLaFiche) -> Void)? = nil
    /// La ligne sur laquelle se caler en apparaissant : celle qu'on vient de
    /// toucher, quand la fiche entière remplace les évènements.
    var ancre: String? = nil
    
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
    #if os(iOS)
    @ObservedObject private var actionsDuDuo = ActionsDuDuo.shared
    #endif

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

    @AppStorage(TimerSettings.validite) private var validiteTimerEnabled = true
    @AppStorage(TimerSettings.contourValidite) private var contourValiditeEnabled = true
    @AppStorage(TimerSettings.modeDeValidite) private var modeDeValidite = ModeDeValidite.automatique.rawValue
    @AppStorage(TimerSettings.validiteTolerance) private var toleranceEnabled = true
    @AppStorage(TimerSettings.validiteToleranceMinutes) private var toleranceMinutes = TimerSettings.defaultToleranceMinutes
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

    // Contour du visuel : la couleur de l'encart Validité, portée sur la carte
    // pour qu'un coup d'œil suffise.
    private var validityOutline: (color: Color, glow: CGFloat)? {
        // Le contour dit la même chose que l'encart Validité, en plus criant :
        // le taire dans l'historique et garder son halo rouge reviendrait à
        // juger quand même un scan d'il y a trois jours.
        guard !depuisHistorique, validiteTimerEnabled, contourValiditeEnabled else { return nil }
        let validity = timers.validity(
            mode: ModeDeValidite(rawValue: modeDeValidite) ?? .automatique,
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
        // Dans le cadre tourné, la page des voyages est plus large que la carte
        // de la colonne : photographiée à cette largeur, la carte laissait des
        // bandes blanches.
        let apercu = mesure.largeur > 0 && !paysagePlie
            ? CGSize(width: mesure.largeur, height: ApercuDeCarte.hauteur) : nil
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
    
    
    /// Sur le Duo, les boutons de la fiche passent dans sa barre.
    private var surLeDuo: Bool {
        #if os(iOS)
        Duo.estUnDuo
        #else
        false
        #endif
    }

    #if os(iOS)
    private func annoncerALaBarre() {
        actionsDuDuo.carteAffichee = true
        actionsDuDuo.peutPersonnaliser = canPersonalize
        if !tagEnvHolder.isEmpty, let export {
            actionsDuDuo.export = ExportFile(
                fileName: "\(cardID)_\(Self.jourDExport.string(from: Date())).metropass", contenu: export)
            actionsDuDuo.titreExport = "Données Navigo \(cardID)"
        } else {
            actionsDuDuo.export = nil
        }
    }
    #endif

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

    /// Plié couché, la fiche entière se présente en deux colonnes, qu'on
    /// l'ouvre en scannant ou depuis l'historique.
    @Environment(\.paysagePlie) private var paysagePlie
    @Environment(\.ecranDeplie) private var ecranDeplie

    var body: some View {
        // Sur le Duo, plié en paysage comme déplié, la fiche se présente en
        // deux colonnes.
        if (paysagePlie || ecranDeplie) && partie == .tout {
            FicheEnDeuxColonnes(cardID: cardID, tagIcc: tagIcc, tagEnvHolder: tagEnvHolder,
                                tagContracts: tagContracts, tagEvents: tagEvents,
                                tagSpecialEvents: tagSpecialEvents, export: export,
                                depuisHistorique: depuisHistorique, historyManager: historyManager)
        } else {
            liste
        }
    }

    @ViewBuilder
    private var liste: some View {
        // Une lecture des validations pour toute la fiche : chaque ligne y puise
        // sa transition sans relire les autres.
        let validations = Validations(tagEvents, contrats: tagContracts, brutes: transitionsBrutes)
        ScrollViewReader { defilement in
        List {
            Group {
            if partie.montreLaCarte {
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
            TimersDeLaCarte(contracts: tagContracts, events: tagEvents, sansValidite: depuisHistorique)

            // Dans l'historique seulement : sur une carte qu'on vient de lire,
            // on regarde son titre, pas ses voyages. La vignette ne montre pas
            // ces voyages, seulement qu'une carte attend derrière : une image
            // fixe, rien à calculer.
            if depuisHistorique, !tagEvents.isEmpty {
                Section {
                    // Un bouton plutôt qu'un lien : la page ne s'ouvre qu'une
                    // fois prête, et le sablier prend la place de la flèche en
                    // attendant.
                    // Une page, partout : dans le cadre tourné, elle prend la place
                    // du panneau de gauche, d'où l'on revient en glissant.
                    Button(action: { if let ouvrir { ouvrir(.voyages) } else { reconstituerLesVoyages() } }) {
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
                Section(header: Text("Contrats").frame(maxWidth: .infinity, alignment: .leading)) {
                    ForEach(displayedContractsIndices, id: \.self) { i in
                        if let ouvrir {
                            Button { ouvrir(.contrat(i)) } label: {
                                ContractPreview(
                                    contractInfo: tagContracts[i],
                                    isPreferred: isContractBest(tagContracts[i], tagContracts),
                                    isDisabled: isContractDisabled(tagContracts[i])
                                )
                            }
                            .tint(.primary)
                            .separateurPleineLargeur()
                            .id(OuvertureDansLaFiche.contrat(i).ancre)
                        } else {
                            NavigationLink {
                                ContractView(contractInfo: tagContracts[i])
                                    .pleinCadreSurLeDuo()
                            } label: {
                                ContractPreview(
                                    contractInfo: tagContracts[i],
                                    isPreferred: isContractBest(tagContracts[i], tagContracts),
                                    isDisabled: isContractDisabled(tagContracts[i])
                                )
                            }
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
            

            // Le calculateur de cette carte-ci, sous ses contrats : ses mois,
            // ses trajets chiffrés. Depuis l'historique seulement, où la carte
            // a ses validations d'avant ; une carte qu'on vient de lire, on
            // regarde son titre.
            if depuisHistorique, !tagEvents.isEmpty {
                Section {
                    if let ouvrir {
                        Button { ouvrir(.calculateur) } label: {
                            Label("Calculateur de prix", systemImage: "eurosign.circle")
                                // Calé à gauche dans la colonne lue de droite à gauche.
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(.primary)
                    } else {
                        NavigationLink {
                            CalculateurPrixView(events: tagEvents, contracts: tagContracts)
                                .pleinCadreSurLeDuo()
                        } label: {
                            Label("Calculateur de prix", systemImage: "eurosign.circle")
                        }
                    }
                }
            }
            }

            if partie.montreLesValidations {
            if tagEvents.count > 0 {
                // Calé à gauche même dans la colonne lue de droite à gauche.
                Section(header: Text("Derniers évènements").frame(maxWidth: .infinity, alignment: .leading)) {
                    ForEach(displayedEventsIndices, id: \.self) { i in
                        if let ouvrir {
                            Button { ouvrir(.evenement(i)) } label: {
                                EventPreview(eventInfo: tagEvents[i], transition: validations.transition(de: i))
                            }
                            .tint(.primary)
                            .separateurPleineLargeur()
                            .id(OuvertureDansLaFiche.evenement(i).ancre)
                        } else {
                            NavigationLink {
                                EventView(eventInfo: tagEvents[i], transition: validations.transition(de: i),
                                          regle: validations.regle(de: i), contractsInfos: tagContracts)
                            } label: {
                                EventPreview(eventInfo: tagEvents[i], transition: validations.transition(de: i))
                            }
                        }
                    }
                }
                
            }
            
            if tagSpecialEvents.count > 0 {
                Section(header: Text("Evènements spéciaux").frame(maxWidth: .infinity, alignment: .leading)) {
                    ForEach(displayedSpecialEventsIndices, id: \.self) { i in
                        if let ouvrir {
                            Button { ouvrir(.special(i)) } label: {
                                EventPreview(eventInfo: tagSpecialEvents[i])
                            }
                            .tint(.primary)
                            .separateurPleineLargeur()
                            .id(OuvertureDansLaFiche.special(i).ancre)
                        } else {
                            NavigationLink {
                                EventView(eventInfo: tagSpecialEvents[i], contractsInfos: tagContracts)
                            } label: {
                                EventPreview(eventInfo: tagSpecialEvents[i])
                            }
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
            }
            // Dans la colonne des évènements, lue de droite à gauche pour que
            // son indicateur de défilement tienne au bord de l'écran, les
            // lignes gardent le sens de lecture.
            .environment(\.layoutDirection, .leftToRight)
        }
        .onAppear {
            if let ancre { defilement.scrollTo(ancre, anchor: .center) }
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
                .pleinCadreSurLeDuo()
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
            // Sur le Duo, ces boutons vivent dans sa barre, sous la caméra.
            if !surLeDuo {
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
                        Label { Text("Modifier le pass") } icon: {
                            Image(systemName: "square.and.pencil").droitSurLeDuo()
                        }
                    }
                }

                if !tagEnvHolder.isEmpty, let export {
                    ShareLink(
                        item: ExportFile(fileName: "\(cardID)_\(Self.jourDExport.string(from: Date())).metropass", contenu: export),
                        preview: SharePreview("Données Navigo \(cardID)")
                    ) {
                        Label { Text("Exporter") } icon: {
                            Image(systemName: "square.and.arrow.up").droitSurLeDuo()
                        }
                    }
                } else {
                    // Optional: Disabled placeholder so the UI doesn't "jump"
                    Label("Exporter", systemImage: "square.and.arrow.up")
                        .opacity(0.5)
                }
            }
            }
        }
        #if os(iOS)
        // La fiche principale dit à la barre du Duo ce qu'elle propose, et
        // répond à ses demandes. Celle des validations, en face, ne s'en mêle
        // pas.
        .onAppear { if partie.montreLaCarte { annoncerALaBarre() } }
        .onChange(of: canPersonalize) { if partie.montreLaCarte { annoncerALaBarre() } }
        .onDisappear {
            guard partie.montreLaCarte else { return }
            actionsDuDuo.carteAffichee = false
            actionsDuDuo.export = nil
        }
        .onChange(of: actionsDuDuo.renommer) { _, demande in
            guard demande, partie.montreLaCarte else { return }
            actionsDuDuo.renommer = false
            newNickname = historyManager.history.first(where: { $0.cardID == cardID })?.nickname ?? ""
            showingRenameAlert = true
        }
        .onChange(of: actionsDuDuo.changerImage) { _, demande in
            guard demande, partie.montreLaCarte else { return }
            actionsDuDuo.changerImage = false
            showingImagePicker = true
        }
        #endif
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
    let sansValidite: Bool

    var body: some View {
        TimersView(timers: PassTimers(contracts: contracts, events: events), sansValidite: sansValidite)
    }
}

/// Une mesure gardée d'un rendu à l'autre sans en provoquer.
private final class Mesure {
    var largeur: CGFloat = 0
}

#Preview {
    ScanView(cardID: 0, tagIcc: "", tagEnvHolder: [:], tagContracts: [], tagEvents: [], tagSpecialEvents: [], historyManager: HistoryManager())
}


/// Ce qu'une fiche montre.
enum PartieDeFiche {
    /// Tout, de la carte à l'environnement.
    case tout
    /// La carte, sa validité, ses voyages et ses contrats.
    case carte
    /// Les validations, les évènements spéciaux et l'environnement.
    case validations
    /// Tout, d'un seul tenant, même dans le cadre tourné : la colonne qui
    /// reprend la fiche quand un évènement s'ouvre en face.
    case ensemble

    var montreLaCarte: Bool { self != .validations }
    var montreLesValidations: Bool { self != .carte }
}


/// Ce qu'on ouvre dans la colonne de la carte : une validation, un évènement
/// spécial ou un contrat, par son rang.
enum OuvertureDansLaFiche: Equatable {
    case evenement(Int)
    case special(Int)
    case contrat(Int)
    case calculateur
    /// La reconstitution des voyages, qui prend le panneau de gauche.
    case voyages

    /// L'identifiant de sa ligne dans la fiche, pour s'y caler.
    var ancre: String {
        switch self {
        case .evenement(let i): return "evenement-\(i)"
        case .special(let i):   return "special-\(i)"
        case .contrat(let i):   return "contrat-\(i)"
        case .calculateur:      return "calculateur"
        case .voyages:          return "voyages"
        }
    }
}


/// La fiche du Duo plié tenu en paysage : à gauche, la fiche entière — la
/// carte, sa validité et ses contrats, puis les évènements — ; à droite, le
/// détail de ce qu'on y touche, le forfait actif tant qu'on n'a rien touché.
/// Un espace au milieu, sans trait, et pas de barre : le titre redit la carte
/// qu'on voit.
struct FicheEnDeuxColonnes: View {
    let cardID: UInt64
    let tagIcc: String
    let tagEnvHolder: [String: Any]
    let tagContracts: [[String: Any]]
    let tagEvents: [[String: Any]]
    let tagSpecialEvents: [[String: Any]]
    var export: (() -> Data?)?
    var depuisHistorique: Bool
    @ObservedObject var historyManager: HistoryManager

    @State private var ouverte: OuvertureDansLaFiche?
    /// La reconstitution des voyages tient le panneau de gauche.
    @State private var voyages = false
    #if os(iOS)
    @ObservedObject private var actionsDuDuo = ActionsDuDuo.shared
    #endif

    private static let ecartDesColonnes: CGFloat = 24
    /// La carte veut de l'air au-dessus d'elle ; le détail, un peu moins.
    @Environment(\.paysagePlie) private var paysagePlie

    /// Les marges ne valent que dans le cadre tourné du Duo plié, où rien ne
    /// réserve plus le haut ni le bas. Déplié, l'écran garde ses zones sûres.
    /// La carte remonte un peu au-delà de sa section : sans barre au-dessus, il
    /// lui faut de l'air pour ne pas sortir par le haut, plié comme déplié.
    private var margeCarte: CGFloat { paysagePlie ? 72 : 80 }
    private var margeDetail: CGFloat { paysagePlie ? 36 : 40 }
    private var margeBasse: CGFloat { paysagePlie ? 96 : 16 }

    /// Le forfait actif : le contrat que la carte retient, sinon le premier.
    private var forfaitActif: OuvertureDansLaFiche? {
        let ordre = ordreDesContrats(tagContracts)
        let actif = ordre.first { isContractBest(tagContracts[$0], tagContracts) } ?? ordre.first
        return actif.map { .contrat($0) }
    }

    var body: some View {
        HStack(spacing: Self.ecartDesColonnes) {
            colonneFiche
            colonneDetail
        }
        .padding(.horizontal, Self.ecartDesColonnes / 2)
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        // Ouverte depuis une colonne lue de droite à gauche, la fiche en
        // héritait : on la remet dans le sens de lecture.
        .environment(\.layoutDirection, .leftToRight)
        #if os(iOS)
        .onChange(of: voyages) { _, ouverts in actionsDuDuo.retourPossible = ouverts }
        .onChange(of: actionsDuDuo.retour) { _, demande in
            guard demande else { return }
            actionsDuDuo.retour = false
            fermerLesVoyages()
        }
        .onDisappear { actionsDuDuo.retourPossible = false }
        #endif
        // Dans le cadre tourné, la pile de navigation calcule ses marges avant
        // la rotation, et les retirait aux colonnes : 84 pt côté caméra
        // restaient vides. Déplié, rien ne tourne, mais la marge des capteurs,
        // d'un côté seulement, décalait la séparation hors de la charnière :
        // les colonnes prennent toute la largeur, et chacune sa moitié.
        .ignoresSafeArea(edges: paysagePlie ? .all : .horizontal)
    }

    private func fiche(_ partie: PartieDeFiche, ouvrir: ((OuvertureDansLaFiche) -> Void)? = nil) -> ScanView {
        ScanView(cardID: cardID, tagIcc: tagIcc, tagEnvHolder: tagEnvHolder, tagContracts: tagContracts,
                 tagEvents: tagEvents, tagSpecialEvents: tagSpecialEvents, export: export,
                 depuisHistorique: depuisHistorique, partie: partie, ouvrir: ouvrir,
                 historyManager: historyManager)
    }

    /// Ouvre un détail à droite ; le même, touché de nouveau, rend la place au
    /// forfait actif. Les voyages, eux, prennent le panneau de gauche, et la
    /// validation la plus récente s'ouvre en face.
    private func ouvrir(_ ouverture: OuvertureDansLaFiche) {
        withAnimation(.snappy(duration: 0.3)) {
            if ouverture == .voyages {
                voyages = true
                ouverte = tagEvents.isEmpty ? nil : .evenement(0)
            } else {
                ouverte = ouverte == ouverture ? nil : ouverture
            }
        }
    }

    private func fermerLesVoyages() {
        withAnimation(.snappy(duration: 0.3)) {
            voyages = false
            ouverte = nil
        }
    }

    /// À gauche : la fiche entière, ou la reconstitution des voyages. On en
    /// revient par la barre du Duo, ou en glissant depuis le bord.
    @ViewBuilder
    private var colonneFiche: some View {
        if voyages {
            ValidationHistoryView(events: tagEvents, contracts: tagContracts) { i in
                withAnimation(.snappy(duration: 0.3)) { ouverte = .evenement(i) }
            }
            // La marge du haut, c'est la liste qui la fixe : la sienne
            // l'emporterait sur celle qu'on poserait ici.
            .contentMargins(.bottom, margeBasse, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                // Le bord qu'on tire pour revenir, comme une page qu'on quitte.
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 20).onEnded { geste in
                        if geste.translation.width > 80 { fermerLesVoyages() }
                    })
            }
        } else {
            colonneDeLaFiche
        }
    }

    private var colonneDeLaFiche: some View {
        fiche(.ensemble, ouvrir: ouvrir)
            // Le halo de validité déborde sur l'espace du milieu, au lieu
            // d'être tranché au bord de la colonne.
            .scrollClipDisabled()
            // Sans barre au-dessus, la carte, qui remonte un peu au-delà de sa
            // section, sortait de l'écran : la marge la rattrape.
            .contentMargins(.top, margeCarte, for: .scrollContent)
            .contentMargins(.bottom, margeBasse, for: .scrollContent)
            // L'indicateur de défilement au bord de l'écran plutôt qu'au milieu :
            // la colonne se lit de droite à gauche, ses lignes de gauche à droite.
            .environment(\.layoutDirection, .rightToLeft)
            .frame(maxWidth: .infinity)
    }

    @Environment(\.retraitDeLaBarre) private var retraitDeLaBarre

    /// À droite : ce qu'on a touché, ou le forfait actif. Elle s'écarte de la
    /// barre du Duo par l'intérieur, pour que les colonnes se partagent
    /// l'écran à la charnière.
    private var colonneDetail: some View {
        Group {
            if let detail = ouverte ?? forfaitActif {
                evenementOuvert(detail)
            }
        }
        .contentMargins(.top, margeDetail, for: .scrollContent)
        .contentMargins(.bottom, margeBasse, for: .scrollContent)
        .contentMargins(.trailing, retraitDeLaBarre, for: .scrollContent)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func evenementOuvert(_ ouverture: OuvertureDansLaFiche) -> some View {
        switch ouverture {
        case .evenement(let i) where tagEvents.indices.contains(i):
            let validations = Validations(tagEvents, contrats: tagContracts)
            EventView(eventInfo: tagEvents[i], transition: validations.transition(de: i),
                      regle: validations.regle(de: i), contractsInfos: tagContracts)
        case .special(let i) where tagSpecialEvents.indices.contains(i):
            EventView(eventInfo: tagSpecialEvents[i], contractsInfos: tagContracts)
        case .contrat(let i) where tagContracts.indices.contains(i):
            ContractView(contractInfo: tagContracts[i])
        case .calculateur:
            CalculateurPrixView(events: tagEvents, contracts: tagContracts)
        case .voyages:
            EmptyView()
        default:
            EmptyView()
        }
    }
}


extension View {
    /// Le séparateur d'une ligne d'un bord à l'autre de la section : dans la
    /// colonne lue de droite à gauche, il s'arrêtait avant le bord.
    func separateurPleineLargeur() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
    }
}
