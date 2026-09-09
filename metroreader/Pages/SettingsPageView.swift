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
    // Éteint par défaut : la valeur par défaut d'un @AppStorage n'écrit rien
    // dans UserDefaults, si bien qu'un interrupteur allumé d'origine se lisait
    // éteint côté lecture — et iOS, lui, n'avait jamais été sollicité.
    @AppStorage(LocationProvider.settingKey) private var locateOnScan = false
    @ObservedObject private var gps = LocationProvider.shared
    #endif

    @AppStorage(TimerSettings.alreadyValidated) private var alreadyValidatedTimer = true
    @AppStorage(TimerSettings.sale) private var saleTimer = true
    @AppStorage(TimerSettings.control) private var controlTimer = true
    
    @ObservedObject private var journal = ManualEntries.shared

    /// Les logos de marque ne sont pas des SF Symbols : il faut les
    /// dimensionner soi-même, et leur faire suivre les tailles de texte de
    /// l'utilisateur.
    @ScaledMetric(relativeTo: .body) private var coteLogo: CGFloat = 20

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
            Section {
                #if os(iOS)
                Toggle(isOn: $autoLaunchScan) {
                    Label("Scan au démarrage", systemImage: "bolt.fill")
                }
                #endif

                
                Toggle(isOn: $isHistoryEnabled) {
                    Label("Conserver l'historique", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Comportement")
            } footer: {
                Text("Sans historique, un pass ne peut être ni renommé ni recoloré : il n'y a pas de fiche où l'écrire.")
            }

            #if os(iOS)
            Section {
                Toggle(isOn: $locateOnScan) {
                    Label("Relever la position au scan", systemImage: "location")
                }
                .onChange(of: locateOnScan) { _, active in
                    if active { gps.requestPermission() }
                }

                if locateOnScan, gps.isDeniedBySystem,
                   let reglages = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: reglages) {
                        Label("Autoriser dans les réglages de l'iPhone", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Position")
            } footer: {
                Text("Relevée au moment du scan seulement, pour proposer les arrêts proches quand la carte annonce un arrêt inconnu. Elle n'est ni enregistrée ni transmise.")
            }
            #endif
            
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

                NavigationLink {
                    ControlSettingsView()
                } label: {
                    Label("Options du contrôle", systemImage: "slider.horizontal.3")
                }
                .disabled(!controlTimer)
            }

            Section {
                NavigationLink {
                    ManualDataView()
                } label: {
                    Label("Données saisies", systemImage: "tablecells")
                }

                if let data = journal.export {
                    ShareLink(item: ManualEntriesFile(data: data, fileName: "donnees-saisies.json"),
                              preview: SharePreview("Données saisies")) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    .disabled(journal.isEmpty)
                }

                Button(role: .destructive) {
                    showingJournalAlert = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .disabled(journal.isEmpty)
            } header: {
                Text("Données")
            } footer: {
                Text("Les réseaux, lignes et arrêts que tu as identifiés faute de référentiel. Ils se parcourent par réseau, puis par ligne, et s'exportent pour être versés au jeu de données.")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Effacer tout l'historique", systemImage: "trash")
                }
                .disabled(historyManager.history.isEmpty)
            } header: {
                Text("Confidentialité")
            }
            
            Section(header: Text("Fait avec ❤️ par")) {
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
            
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundColor(.secondary)
                }
                Link(destination: URL(string: "https://github.com/CelianF/metroreader")!) {
                    HStack {
                        Label {
                            Text("GitHub").foregroundColor(.primary)
                        } icon: {
                            // Le sigle est presque noir : rendu en template
                            // pour qu'il suive le thème au lieu de disparaître
                            // sur fond sombre. Le Discord, lui, garde sa
                            // couleur, qui tient dans les deux.
                            Image("GitHub")
                                .resizable()
                                .scaledToFit()
                                .frame(width: coteLogo, height: coteLogo)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Link(destination: URL(string: "https://discord.gg/KJbVn9wXBg")!) {
                    HStack {
                        Label {
                            Text("Discord").foregroundColor(.primary)
                        } icon: {
                            // Le logo de la marque plutôt qu'un symbole
                            // approchant. Encadré à la largeur d'un SF Symbol
                            // pour que les deux libellés s'alignent.
                            Image("Discord")
                                .resizable()
                                .scaledToFit()
                                .frame(width: coteLogo, height: coteLogo)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("À propos")
            } footer: {
                // Dernier mot de l'écran, et de l'application : ce qu'elle est,
                // et surtout ce qu'elle n'est pas.
                Text("""
                Cette application est un service indépendant et non officiel. Elle n'est en aucun cas affiliée, approuvée ou gérée par Île-de-France Mobilités ou la Calypso Networks Association.

                L'application permet uniquement la lecture locale des données à titre informatif. Elle ne permet aucunement d'acheter, de recharger, de valider ou de modifier des titres de transport.
                """)
                .padding(.top, 4)
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
        .alert("Supprimer les données saisies ?", isPresented: $showingJournalAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Tout effacer", role: .destructive) { journal.clearAll() }
        } message: {
            Text("Les réseaux, lignes et arrêts que tu as identifiés seront oubliés, et réafficheront leur identifiant brut.")
        }
    }
}

#Preview {
    SettingsPageView(historyManager: HistoryManager())
}
