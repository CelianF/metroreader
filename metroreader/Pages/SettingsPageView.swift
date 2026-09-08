//
//  SettingsPageView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//

import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var historyManager: HistoryManager
    // This stores the preference in the phone's memory automatically
    #if os(iOS)
    @AppStorage("autoLaunchScan") private var autoLaunchScan = false
    #endif
    @AppStorage("isHistoryEnabled") private var isHistoryEnabled = false
    #if os(iOS)
    @AppStorage(LocationProvider.settingKey) private var locateOnScan = true
    #endif

    @AppStorage(TimerSettings.alreadyValidated) private var alreadyValidatedTimer = true
    @AppStorage(TimerSettings.sale) private var saleTimer = true
    @AppStorage(TimerSettings.control) private var controlTimer = true
    
    @ObservedObject private var stopJournal = StopReports.shared

    @State private var showingDeleteAlert = false
    @State private var showingJournalAlert = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            Section(header: Text("Comportement")) {
                #if os(iOS)
                Toggle(isOn: $autoLaunchScan) {
                    Label("Scan au démarrage", systemImage: "bolt.fill")
                }
                #endif
                
                Toggle(isOn: $isHistoryEnabled) {
                    Label("Conserver l'historique", systemImage: "clock.arrow.circlepath")
                }

                #if os(iOS)
                Toggle(isOn: $locateOnScan) {
                    Label("Relever la position au scan", systemImage: "location")
                }
                #endif
            }
            
            Section(header: Text("Timers"), footer: Text("Affichés sous le visuel de la carte. Le timer Contrôle pilote aussi le contour du pass.")) {
                Toggle(isOn: $alreadyValidatedTimer) {
                    Label("Pass déjà validé", systemImage: "arrow.uturn.backward.circle")
                }

                Toggle(isOn: $saleTimer) {
                    Label("Vente", systemImage: "cart")
                }

                Toggle(isOn: $controlTimer) {
                    Label("Contrôle", systemImage: "checkmark.seal")
                }
            }

            Section {
                if stopJournal.reports.isEmpty {
                    Text("Aucun arrêt signalé")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stopJournal.reports) { report in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.stationName)
                                .fontWeight(.semibold)
                            Text("\(interpretServiceProviderName(report.providerId)) · \(report.locationId)\(report.lineName.map { " · ligne " + $0 } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { stopJournal.delete(at: $0) }

                    if let data = stopJournal.exportData {
                        ShareLink(item: StopJournalFile(data: data),
                                  preview: SharePreview("Arrêts à identifier")) {
                            Label("Exporter le journal", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button(role: .destructive) {
                        showingJournalAlert = true
                    } label: {
                        Label("Vider le journal", systemImage: "trash")
                    }
                }
            } header: {
                Text("Arrêts signalés")
            } footer: {
                Text("Treize réseaux n'ont pas déclaré leurs codes d'arrêt au référentiel régional. Les arrêts que tu identifies s'affichent aussitôt et sont conservés ici, pour être exportés et versés au jeu de données.")
            }

            Section(header: Text("Confidentialité")) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Effacer tout l'historique", systemImage: "trash")
                }
                .disabled(historyManager.history.isEmpty)
            }
            
            Section(header: Text("Crédits")) {
                VStack(alignment: .leading, spacing: 8) {
                    // Lien pour DocSystem
                    Link(destination: URL(string: "https://twitter.com/TheDocSystem")!) {
                        HStack {
                            Text("DocSystem")
                                .font(.headline)
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.caption)
                        }
                    }
                    
                    Text("Recherche, rétro-ingénierie et développement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Lien pour Stitch
                    Link(destination: URL(string: "https://twitter.com/TweetingStitch")!) {
                        HStack {
                            Text("Stitch")
                                .font(.headline)
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.caption)
                        }
                    }
                    
                    Text("Interface de l'application, design des cartes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("À propos")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundColor(.secondary)
                }
                Link(destination: URL(string: "https://github.com/DocSystem/metroreader")!) {
                    HStack {
                        Label("GitHub", systemImage: "terminal.fill")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Réglages")
        .alert("Effacer l'historique ?", isPresented: $showingDeleteAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Tout effacer", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("Cette action est irréversible. Tous vos scans enregistrés seront supprimés.")
        }
        .alert("Vider le journal ?", isPresented: $showingJournalAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Tout effacer", role: .destructive) { stopJournal.clearAll() }
        } message: {
            Text("Les arrêts que tu as identifiés seront oubliés et réafficheront leur identifiant brut.")
        }
    }
}

#Preview {
    SettingsPageView(historyManager: HistoryManager())
}
