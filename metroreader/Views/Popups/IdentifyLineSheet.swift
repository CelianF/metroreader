//
//  IdentifyLineSheet.swift
//  metroreader
//

import SwiftUI


/// Sélection de la ligne correspondant à un numéro de course que l'app n'a pas
/// su nommer.
///
/// Une même ligne change de numéro de course d'un exploitant à l'autre, mais
/// pas de nom : la reprendre dans le référentiel donne d'un coup son libellé,
/// ses couleurs et son identifiant IDFM — lequel ouvre ensuite la liste de ses
/// arrêts quand il faudra en identifier un.
struct IdentifyLineSheet: View {
    let providerId: Int
    let routeNumber: Int
    let mode: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var journal = ManualEntries.shared

    @State private var recherche = ""
    @State private var toutesLesLignes = false
    @State private var saisieLibre = ""

    /// Lignes déjà nommées à la main, sur ce mode. Un exploitant qui n'a pas
    /// déclaré ses courses en a rarement une seule.
    private var dejaNommees: [LineEntry] {
        var vus = Set<String>()
        return journal.lines
            .filter { $0.mode == mode && !($0.providerId == providerId && $0.routeNumber == routeNumber) }
            .filter { recherche.isEmpty || $0.name.localizedCaseInsensitiveContains(recherche) }
            .filter { vus.insert($0.name).inserted }
            .prefix(6)
            .map { $0 }
    }

    /// Lignes du référentiel, dédoublonnées par identifiant IDFM : une même
    /// ligne y figure une fois par exploitant qui la dessert.
    private var candidats: [NavigoLineInfo] {
        var vus = Set<String>()
        return NavigoLines.allLines
            .filter { toutesLesLignes || $0.mode == mode }
            .filter { recherche.isEmpty || $0.name.localizedCaseInsensitiveContains(recherche) }
            .filter { vus.insert($0.public_id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(recherche.isEmpty ? 40 : 200)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Numéro de course", value: "\(routeNumber)")
                    LabeledContent("Mode", value: mode)
                    LabeledContent("Exploitant", value: interpretServiceProviderName(providerId))
                } header: {
                    Text("Ce que la carte annonce")
                } footer: {
                    Text("Aucune ligne du référentiel ne porte ce numéro de course chez cet exploitant. En la nommant, tu l'ajoutes au journal, consultable depuis Réglages › Données.")
                }

                if !dejaNommees.isEmpty {
                    Section("Lignes que tu as déjà nommées") {
                        ForEach(dejaNommees) { entry in
                            Button {
                                enregistrer(nom: entry.name, publicId: entry.publicId,
                                            fond: entry.backgroundColor, texte: entry.textColor)
                            } label: {
                                HStack {
                                    pastille(nom: entry.name, fond: entry.backgroundColor, texte: entry.textColor)
                                    Text(interpretServiceProviderName(entry.providerId))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("course \(entry.routeNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach(candidats, id: \.public_id) { ligne in
                        Button {
                            enregistrer(nom: ligne.name, publicId: ligne.public_id,
                                        fond: ligne.background_color, texte: ligne.text_color)
                        } label: {
                            HStack {
                                pastille(nom: ligne.name, fond: ligne.background_color, texte: ligne.text_color)
                                Text(ligne.mode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(toutesLesLignes ? "Toutes les lignes" : "Lignes en \(mode.lowercased())")
                } footer: {
                    Text("La ligne reprise garde son nom, ses couleurs et son identifiant IDFM — celui qui donnera ensuite la liste de ses arrêts.")
                }

                Section {
                    Toggle("Chercher dans tous les modes", isOn: $toutesLesLignes)
                }

                Section {
                    TextField("Nom de la ligne", text: $saisieLibre)
                    Button("Enregistrer ce nom") {
                        enregistrer(nom: saisieLibre.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(saisieLibre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Sinon, à la main")
                } footer: {
                    Text("Le nom saisi remplacera le numéro de course à l'écran. Faute d'identifiant IDFM, la ligne restera grise et ne donnera pas accès à ses arrêts.")
                }
            }
            .searchable(text: $recherche, prompt: "Rechercher une ligne")
            .navigationTitle("Identifier la ligne")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func pastille(nom: String, fond: String, texte: String) -> some View {
        Text(nom)
            .font(.system(size: 15, weight: .bold))
            .frame(minWidth: 25, minHeight: 25)
            .padding(.horizontal, nom.count > 1 ? 6 : 0)
            .background(Color(hex: fond))
            .foregroundColor(Color(hex: texte))
            .cornerRadius(4)
    }

    private func enregistrer(nom: String, publicId: String? = nil,
                             fond: String = LineEntry.defaultBackground,
                             texte: String = LineEntry.defaultText) {
        guard !nom.isEmpty else { return }
        journal.save(LineEntry(
            id: UUID(),
            date: Date(),
            providerId: providerId,
            routeNumber: routeNumber,
            mode: mode,
            name: nom,
            publicId: publicId,
            backgroundColor: fond,
            textColor: texte
        ))
        dismiss()
    }
}
