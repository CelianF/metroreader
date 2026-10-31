import SwiftUI

struct ContentView: View {
    @StateObject private var nfcReader = NFCReader()
    @StateObject private var historyManager = HistoryManager()
    #if os(iOS)
    @ObservedObject private var actionsRapides = ActionsRapides.shared
    #endif
    @State private var selectedTab = 0
    @State private var lastScanTabTap: Date?
    @Environment(\.scenePhase) private var scenePhase
    /// Régulière sur le Duo déplié, et là seulement : l'app ne tourne qu'en
    /// portrait, et sur iPhone.
    @Environment(\.horizontalSizeClass) private var classeHorizontale
    /// La taille de la fenêtre : elle change quand le système tourne
    /// l'interface, et avec elle le bord où tombe l'antenne du Duo.
    @State private var tailleFenetre: CGSize = .zero
    /// Les Réglages, ouverts depuis la barre du Duo déplié, faute d'onglets.
    @State private var reglagesOuverts = false
    /// Déplié, la carte de l'historique ouverte en plein écran.
    @State private var ficheHistorique: UUID?
    #if os(iOS)
    @ObservedObject private var actionsDuDuo = ActionsDuDuo.shared
    #endif
    #if os(iOS)
    @ObservedObject private var orientation = OrientationDuDuo.shared
    #endif

    // Deux touches rapprochées sur l'onglet Scan lancent une lecture. La
    // sélection est passée par un Binding maison parce que SwiftUI rappelle
    // le setter même quand l'onglet touché est déjà celui qui est actif.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                #if os(iOS)
                if newValue == 0 {
                    let now = Date()
                    if let last = lastScanTabTap, now.timeIntervalSince(last) < 0.4 {
                        lastScanTabTap = nil
                        if !nfcReader.isScanning {
                            nfcReader.beginScanning(historyManager: historyManager)
                        }
                    } else {
                        lastScanTabTap = now
                    }
                }
                #endif
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        Group {
            if classeHorizontale == .regular {
                deplie
            } else {
                onglets
            }
        }
        .modifier(BordDeDefilementDoux())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tailleFenetre = $0 }
        // Une carte lue ou importée passe devant la fiche de l'historique.
        .onChange(of: nfcReader.isReadComplete) { _, lue in if lue { ficheHistorique = nil } }
        #if os(iOS)
        .overlay { barreDuDuo }
        .sheet(isPresented: $reglagesOuverts) {
            NavigationStack {
                SettingsPageView(historyManager: historyManager)
                    // Sans titre, la feuille n'avait que son OK, seul à droite.
                    .navigationTitle("Réglages")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { reglagesOuverts = false }
                        }
                    }
            }
        }
        #endif
        #if os(iOS)
        .environment(\.angleDesBoutons, angleDesBoutons)
        #endif
        .task {
            // Au lancement, et là seulement : c'est le moment où une
            // autorisation accordée « cette fois seulement » a expiré.
            LocationProvider.shared.forgetLapsedPermission()
            // Les tables d'arrêts et de lignes se décodent tout de suite, hors du
            // fil principal : la première carte lue les trouve prêtes.
            await Task.detached(priority: .userInitiated) { DonneesLivrees.prechauffer() }.value
        }
        .onOpenURL { url in
            handleIncomingFile(url: url)
        }
        .onChange(of: scenePhase) { _, phase in
            // En arrière-plan, l'app peut être suspendue sans préavis : ce qui
            // reste à écrire s'écrit avant.
            if phase == .background { Persistance.attendre() }
            #if os(iOS)
            lancerLeScanDemande()
            #endif
        }
        #if os(iOS)
        .onChange(of: actionsRapides.scanDemande, initial: true) {
            lancerLeScanDemande()
        }
        #endif
    }

    /// Le Duo déplié : le scan du côté de l'antenne NFC, l'historique de
    /// l'autre. L'antenne ne bouge pas sur l'appareil, mais le système tourne
    /// l'interface, et elle passe d'un bord à l'autre : le panneau de scan la
    /// suit. Les boutons montent dans sa barre — les Réglages compris, faute
    /// d'onglets.
    ///
    /// Inverser l'ordre par le sens de lecture aurait gardé la navigation des
    /// panneaux, mais un ancêtre lu de droite à gauche renverse aussi les
    /// coordonnées globales, et la cible ne trouvait plus l'antenne : passer
    /// l'antenne d'un côté à l'autre ramène chaque panneau à sa racine.
    @ViewBuilder
    private var deplie: some View {
        Group {
            if let id = ficheHistorique, let fiche = historyManager.history.first(where: { $0.id == id }) {
                // Une carte de l'historique, comme une carte lue : tout l'écran.
                NavigationStack {
                    ScanView(cardID: fiche.cardID, tagIcc: fiche.icc, tagEnvHolder: fiche.envHolder,
                             tagContracts: fiche.contracts, tagEvents: fiche.events,
                             tagSpecialEvents: fiche.specialEvents, export: fiche.export,
                             depuisHistorique: true, historyManager: historyManager)
                }
                .modifier(FicheDuDeplie(enHauteur: enHauteur))
                .environment(\.retraitDeLaBarre, Self.largeurBarre)
            } else if nfcReader.isReadComplete {
                // Une carte lue prend tout l'écran, en deux colonnes : la fiche
                // à gauche, le détail à droite. La colonne de droite s'écarte
                // de la barre par l'intérieur, pour que la séparation tombe sur
                // la charnière.
                panneauScan
                    .modifier(FicheDuDeplie(enHauteur: enHauteur))
                    .environment(\.retraitDeLaBarre, Self.largeurBarre)
            } else if enHauteur {
                // En portrait, l'un sur l'autre, comme l'écran plié : le scan
                // dans la moitié de l'antenne. Le panneau du haut côtoie la
                // barre.
                VStack(spacing: 0) {
                    if scanEnPremier {
                        panneauScan.environment(\.retraitDeLaBarre, Self.largeurBarre)
                        separateur
                        panneauSecond
                    } else {
                        panneauSecond.environment(\.retraitDeLaBarre, Self.largeurBarre)
                        separateur
                        panneauScan
                    }
                }
                // Toute la hauteur de l'écran : la barre d'état ne réservait
                // que le haut, et la séparation tombait sous le milieu.
                .ignoresSafeArea(.container, edges: .vertical)
            } else {
                // En paysage, côte à côte, chacun sa moitié : la séparation
                // tombe sur la charnière. Le panneau de droite côtoie la barre.
                HStack(spacing: 0) {
                    if scanEnPremier {
                        panneauScan
                        separateur
                        panneauSecond.environment(\.retraitDeLaBarre, Self.largeurBarre)
                    } else {
                        panneauSecond
                        separateur
                        panneauScan.environment(\.retraitDeLaBarre, Self.largeurBarre)
                    }
                }
                // Toute la largeur de l'écran, pas celle de sa zone sûre : sinon
                // la marge des capteurs, d'un côté seulement, décalait la
                // séparation hors de la charnière.
                .ignoresSafeArea(.container, edges: .horizontal)
            }
        }
        .environment(\.ecranDeplie, true)
    }

    private var panneauScan: some View {
        NavigationStack {
            ScanPageView(nfcReader: nfcReader, historyManager: historyManager)
        }
        .frame(maxWidth: .infinity)
    }

    /// L'autre panneau, tant qu'aucune carte n'est lue : l'historique.
    private var panneauSecond: some View {
        NavigationStack {
            // Sans onglet pour le nommer, le panneau dit ce qu'il est.
            HistoryPageView(historyManager: historyManager)
                .navigationTitle("Historique")
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.ouvrirFicheHistorique) { fiche in ficheHistorique = fiche.id }
                .modifier(ScanCarteEcarteDeLaBarre())
        }
        .frame(maxWidth: .infinity)
    }

    /// La place que la barre du Duo prend au bord de l'écran, et un peu d'air
    /// pour que rien ne la touche.
    private static let largeurBarre: CGFloat = 96

    #if os(iOS)
    /// La barre du Duo, sous la caméra, plié comme déplié. Pliée, elle ne vaut
    /// que pour l'onglet de scan, et les Réglages y ont déjà leur onglet.
    @ViewBuilder
    private var barreDuDuo: some View {
        let deplie = classeHorizontale == .regular
        // Pliée, elle vaut pour l'onglet de scan, et pour toute carte ouverte :
        // depuis l'historique aussi, la fiche y a ses boutons et son retour.
        if Duo.estUnDuo && (deplie || selectedTab == 0 || actionsDuDuo.carteAffichee || actionsDuDuo.retourPossible) {
            BarreDuDuo(
                // Pliée, hors de l'onglet de scan, seule la bulle de la carte.
                avecLecture: deplie,
                // Déplié, une carte lue tient tout l'écran : refermer la carte
                // rend l'historique.
                retourALHistorique: deplie && (nfcReader.isReadComplete || ficheHistorique != nil) ? {
                    if ficheHistorique != nil { ficheHistorique = nil } else { nfcReader.clearData() }
                } : nil,
                scanner: {
                    if !nfcReader.isScanning { nfcReader.beginScanning(historyManager: historyManager) }
                },
                ouvrirReglages: {
                    if deplie { reglagesOuverts = true } else { selectedTab = 2 }
                }
            )
            // Sous l'heure et le réseau, que le système range sous la caméra.
            .padding(.top, deplie ? 120 : 165)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .ignoresSafeArea()
        }
    }
    #endif

    private var separateur: some View {
        Divider()
            .ignoresSafeArea()
    }

    /// L'écran déplié tenu en portrait : les panneaux s'empilent.
    private var enHauteur: Bool {
        tailleFenetre.height > tailleFenetre.width
    }

    /// Le panneau de scan vient en premier — à gauche, ou en haut — quand
    /// l'antenne est dans cette moitié de l'écran.
    private var scanEnPremier: Bool {
        #if os(iOS)
        _ = tailleFenetre
        let antenne = Ecran.antenneDuDuoDeplie
        let taille = Ecran.taille
        return enHauteur ? antenne.y < taille.height / 2 : antenne.x < taille.width / 2
        #else
        return true
        #endif
    }

    #if os(iOS)
    /// Relu à chaque rotation : l'interface a pu tourner avec l'appareil.
    private var angleDesBoutons: Angle {
        _ = tailleFenetre
        return orientation.angle(deplie: classeHorizontale == .regular)
    }
    #endif

    /// Plié, le Duo range sa barre d'état sur le côté, sous la caméra : rien ne
    /// réserve plus le haut de l'écran, et les listes s'y collaient au bord.
    private var margeDuHautPlie: CGFloat {
        #if os(iOS)
        Duo.estUnDuo ? 24 : 0
        #else
        0
        #endif
    }

    private var onglets: some View {
        TabView(selection: tabSelection) {
            // Page 1: Scan
            NavigationStack {
                ScanPageView(nfcReader: nfcReader, historyManager: historyManager)
            }
            #if os(iOS)
            .modifier(PaysageSurLeDuoPlie(actif: nfcReader.isReadComplete))
            #endif
            .tabItem {
                Label("Scan", systemImage: "wave.3.forward")
            }
            .tag(0)

            // Page 2: History
            NavigationStack {
                HistoryPageView(historyManager: historyManager)
            }
            .contentMargins(.top, margeDuHautPlie, for: .scrollContent)
            #if os(iOS)
            .modifier(PaysageSurLeDuoPlie())
            #endif
            .tabItem {
                Label("Historique", systemImage: "clock.arrow.circlepath")
            }
            .tag(1)

            // Page 3: Settings
            NavigationStack {
                SettingsPageView(historyManager: historyManager)
            }
            .contentMargins(.top, margeDuHautPlie, for: .scrollContent)
            #if os(iOS)
            .modifier(PaysageSurLeDuoPlie())
            #endif
            .tabItem {
                Label("Réglages", systemImage: "gearshape")
            }
            .tag(2)
        }
    }

    private func handleIncomingFile(url: URL) {
        guard url.pathExtension.lowercased() == "metropass" else { return }
        DispatchQueue.main.async {
            self.selectedTab = 0
            self.nfcReader.importFile(at: url, historyManager: historyManager)
        }
    }

    #if os(iOS)
    // Appui long sur l'icône, « Scanner une carte ». L'action peut arriver
    // avant que la scène soit active — au lancement, elle précède même la
    // première vue : elle attend donc, et part dès que les deux sont réunis.
    private func lancerLeScanDemande() {
        guard actionsRapides.scanDemande, scenePhase == .active else { return }
        actionsRapides.scanDemande = false
        selectedTab = 0
        if !nfcReader.isScanning {
            nfcReader.beginScanning(historyManager: historyManager)
        }
    }
    #endif
}

/// Le fondu du haut des vues défilantes reste doux partout. C'est le défaut
/// d'iOS 26, mais iOS 27 prend `.hard` : on le pose à la racine pour que les
/// deux systèmes se ressemblent. Le bas garde le réglage du système.
/// Avant iOS 26, l'effet de bord n'existe pas.
private struct BordDeDefilementDoux: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

#if os(iOS)
// SwiftUI ne transmet pas les actions rapides de l'écran d'accueil : elles
// passent par le délégué de scène, dans `willConnectTo` quand l'app était
// fermée, dans `performActionFor` quand elle attendait en arrière-plan.
// L'action « scan » est déclarée dans Info.plist.
@MainActor
final class ActionsRapides: ObservableObject {
    static let shared = ActionsRapides()
    @Published var scanDemande = false

    func recevoir(_ action: UIApplicationShortcutItem) -> Bool {
        guard action.type == "\(Bundle.main.bundleIdentifier ?? "").scan" else { return false }
        scanDemande = true
        return true
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let action = connectionOptions.shortcutItem {
            _ = ActionsRapides.shared.recevoir(action)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(ActionsRapides.shared.recevoir(shortcutItem))
    }
}
#endif

@main
struct NFCReaderApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Avant que la moindre vue ne lise ses réglages.
        TimerSettings.reprendreLesAnciennesCles()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#Preview {
    ContentView()
}


/// Une liste qui côtoie la barre du Duo s'en écarte par une marge de contenu :
/// son cadre ne bouge pas, la séparation des panneaux reste sur la charnière.
struct ScanCarteEcarteDeLaBarre: ViewModifier {
    @Environment(\.retraitDeLaBarre) private var retrait

    /// Loin de la barre, la liste garde sa marge ordinaire : une marge nulle
    /// remplaçait la sienne, et ses cartes touchaient le bord de l'écran.
    func body(content: Content) -> some View {
        if retrait > 0 {
            content.contentMargins(.trailing, retrait, for: .scrollContent)
        } else {
            content
        }
    }
}

/// Une carte ouverte sur l'écran déplié. En paysage, deux colonnes ; en
/// portrait, la fiche ordinaire de l'iPhone, sur toute la largeur, qui
/// s'écarte seulement de la barre.
private struct FicheDuDeplie: ViewModifier {
    let enHauteur: Bool

    func body(content: Content) -> some View {
        if enHauteur {
            content
                .modifier(ScanCarteEcarteDeLaBarre())
                .environment(\.ecranDeplie, false)
        } else {
            content
        }
    }
}
