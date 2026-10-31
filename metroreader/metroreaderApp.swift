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
        #if os(iOS)
        .overlay { barreDuDuo }
        .sheet(isPresented: $reglagesOuverts) {
            NavigationStack {
                SettingsPageView(historyManager: historyManager)
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
            if enHauteur {
                // En portrait, l'un sur l'autre, comme l'écran plié : le scan
                // dans la moitié de l'antenne.
                VStack(spacing: 0) {
                    if scanEnPremier {
                        panneauScan.safeAreaPadding(.trailing, Self.largeurBarre)
                        separateur
                        panneauSecond
                    } else {
                        panneauSecond.safeAreaPadding(.trailing, Self.largeurBarre)
                        separateur
                        panneauScan
                    }
                }
            } else {
                // En paysage, côte à côte. Le panneau de droite laisse la place
                // de la barre, sous la caméra.
                HStack(spacing: 0) {
                    if scanEnPremier {
                        panneauScan
                        separateur
                        panneauSecond.safeAreaPadding(.trailing, Self.largeurBarre)
                    } else {
                        panneauSecond
                        separateur
                        panneauScan.safeAreaPadding(.trailing, Self.largeurBarre)
                    }
                }
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

    /// L'autre panneau : l'historique, ou, une carte lue, ses validations —
    /// le panneau de l'antenne n'en garde que la carte et ses contrats.
    private var panneauSecond: some View {
        NavigationStack {
            if nfcReader.isReadComplete {
                ScanView(cardID: nfcReader.cardID, tagIcc: nfcReader.tagIcc, tagEnvHolder: nfcReader.tagEnvHolder,
                         tagContracts: nfcReader.tagContracts, tagEvents: nfcReader.tagEvents,
                         tagSpecialEvents: nfcReader.tagSpecialEvents, export: nfcReader.export,
                         partie: .validations, historyManager: historyManager)
            } else {
                HistoryPageView(historyManager: historyManager)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// La place que la barre du Duo prend au bord de l'écran.
    private static let largeurBarre: CGFloat = 76

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
