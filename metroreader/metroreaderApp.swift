import SwiftUI

struct ContentView: View {
    @StateObject private var nfcReader = NFCReader()
    @StateObject private var historyManager = HistoryManager()
    @State private var selectedTab = 0
    @State private var lastScanTabTap: Date?

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
        .onOpenURL { url in
            handleIncomingFile(url: url)
        }
    }
    
    private func handleIncomingFile(url: URL) {
        print("Opening URL \(url)")
            
        // 1. Validate extension
        guard url.pathExtension.lowercased() == "metropass" else { return }
        
        // 2. Request access
        // This is required when LSSupportsOpeningDocumentsInPlace is YES
        let canAccess = url.startAccessingSecurityScopedResource()
        print("Security Access: \(canAccess)")
        
        defer {
            if canAccess { url.stopAccessingSecurityScopedResource() }
        }
        
        do {
            // 3. Load Data
            let data = try Data(contentsOf: url)
            print("Data Loaded Successfully")
            
            // 4. Update UI on Main Thread
            DispatchQueue.main.async {
                self.selectedTab = 0 // Switch to Scan Tab
                self.nfcReader.importJSON(from: data, historyManager: historyManager)
                print("Import Complete")
            }
        } catch {
            print("Erreur lors de la lecture du fichier : \(error.localizedDescription)")
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
