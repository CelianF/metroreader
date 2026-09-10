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
    @AppStorage(ScanSettings.sansAnimation) private var sansAnimation = false
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

                Toggle(isOn: $sansAnimation) {
                    Label("Sans animation", systemImage: "livephoto.slash")
                }
                #endif

                
                Toggle(isOn: $isHistoryEnabled) {
                    Label("Conserver l'historique", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Comportement")
            } footer: {
                #if os(iOS)
                Text("""
                Sans animation, la cible se tient d'emblée à l'aplomb de l'antenne, coupée par le haut de l'écran, et plus rien ne bouge pendant la lecture.

                Sans historique, un pass ne peut être ni renommé ni recoloré : il n'y a pas de fiche où l'écrire.
                """)
                #else
                Text("Sans historique, un pass ne peut être ni renommé ni recoloré : il n'y a pas de fiche où l'écrire.")
                #endif
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
                    Label("Titres Incompatibles", systemImage: "cart")
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
                    .eteint(quand: journal.isEmpty)
                }

                Button(role: .destructive) {
                    showingJournalAlert = true
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .destructrice(vide: journal.isEmpty)
            } header: {
                Text("Données")
            } footer: {
                Text("Les réseaux, lignes et arrêts que tu as identifiés faute de référentiel. Ils se parcourent par réseau, puis par ligne, et s'exportent pour être versés au jeu de données.")
            }

            Section {
                NavigationLink {
                    ShippedCorrectionsView()
                } label: {
                    Label("Corrections livrées", systemImage: "checkmark.seal")
                }
                .eteint(quand: LineCorrections.all.isEmpty)
            } footer: {
                Text("Là où le référentiel rattache un numéro de course à la mauvaise ligne, l'app le redresse. Ces corrections se lisent mais ne se modifient pas — une surcharge invisible serait une surcharge qu'on ne peut pas contester. Tes propres saisies l'emportent sur elles.")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Effacer tout l'historique", systemImage: "trash")
                }
                .destructrice(vide: historyManager.history.isEmpty)
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


private extension View {
    /// Éteint une rangée quand il n'y a rien à partager ni à effacer.
    ///
    /// `.disabled` seul bloque bien le geste, mais ne grise rien dans une liste :
    /// le libellé garde son noir et l'icône sa teinte, si bien que le bouton
    /// paraît disponible et qu'on le touche pour rien. On dit donc
    /// l'indisponibilité nous-mêmes, et seulement dans ce cas — sinon le rouge
    /// du bouton destructeur y passerait aussi.
    @ViewBuilder
    func eteint(quand vide: Bool) -> some View {
        if vide {
            self.disabled(true).foregroundStyle(.tertiary)
        } else {
            self
        }
    }

    /// Une rangée qui efface : rouge d'un bout à l'autre, et éteinte quand il
    /// n'y a rien à effacer.
    ///
    /// Le rôle destructeur ne rougit que le libellé ; le pictogramme, lui,
    /// suit la teinte d'accentuation et restait bleu. `.tint(.red)` n'y change
    /// rien, il faut le dire en couleur de premier plan. Mais alors la rangée
    /// éteinte garderait son rouge — une couleur posée ici l'emporte sur le
    /// gris que `eteint` appliquerait par-dessus. Les deux états sont donc
    /// décidés au même endroit, l'un excluant l'autre.
    @ViewBuilder
    func destructrice(vide: Bool) -> some View {
        if vide {
            self.disabled(true).foregroundStyle(.tertiary)
        } else {
            self.foregroundStyle(.red)
        }
    }
}
