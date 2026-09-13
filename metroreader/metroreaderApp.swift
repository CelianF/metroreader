import SwiftUI

struct ContentView: View {
    @StateObject private var nfcReader = NFCReader()
    @StateObject private var historyManager = HistoryManager()
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
        .task {
            // Au lancement, et là seulement : c'est le moment où une
            // autorisation accordée « cette fois seulement » a expiré.
            LocationProvider.shared.forgetLapsedPermission()
        }
        .onOpenURL { url in
            handleIncomingFile(url: url)
        }
        .onChange(of: scenePhase) { _, phase in
            // En arrière-plan, l'app peut être suspendue sans préavis : ce qui
            // reste à écrire s'écrit avant.
            if phase == .background { Persistance.attendre() }
        }
    }

    private func handleIncomingFile(url: URL) {
        guard url.pathExtension.lowercased() == "metropass" else { return }
        DispatchQueue.main.async {
            self.selectedTab = 0
            self.nfcReader.importFile(at: url, historyManager: historyManager)
        }
    }
}

@main
struct NFCReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#Preview {
    ContentView()
}
