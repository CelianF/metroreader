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
        TabView(selection: tabSelection) {
            // Page 1: Scan
            NavigationStack {
                ScanPageView(nfcReader: nfcReader, historyManager: historyManager)
            }
            .tabItem {
                Label("Scan", systemImage: "wave.3.forward")
            }
            .tag(0)

            // Page 2: History
            NavigationStack {
                HistoryPageView(historyManager: historyManager)
            }
            .tabItem {
                Label("Historique", systemImage: "clock.arrow.circlepath")
            }
            .tag(1)

            // Page 3: Settings
            NavigationStack {
                SettingsPageView(historyManager: historyManager)
            }
            .tabItem {
                Label("Réglages", systemImage: "gearshape")
            }
            .tag(2)
        }
        .modifier(BordDeDefilementDoux())
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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#Preview {
    ContentView()
}
