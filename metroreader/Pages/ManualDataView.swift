//
//  ManualDataView.swift
//  metroreader
//

import SwiftUI


/// Ce que l'utilisateur a saisi faute de référentiel, parcouru comme le réseau
/// se parcourt : un exploitant, ses lignes, les arrêts de chaque ligne.
///
/// Les trois journaux sont cousus ensemble : une ligne peut n'exister que par
/// les arrêts qui la citent, un réseau que par une ligne qu'on lui a nommée.
struct ManualDataView: View {
    @ObservedObject private var journal = ManualEntries.shared

    var body: some View {
        List {
            if journal.networks.isEmpty {
                Section {
                    Text("Aucune donnée saisie")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Quand une carte annonce un réseau, une ligne ou un arrêt absent du jeu de données, l'écran de l'événement propose de le nommer. Ce qui est saisi se range ici.")
                }
            } else {
                Section {
                    ForEach(journal.networks) { reseau in
                        NavigationLink {
                            ManualNetworkView(providerId: reseau.providerId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(interpretServiceProviderShortName(reseau.providerId))
                                    if isServiceProviderNamedByHand(reseau.providerId) { EtiquetteSaisie() }
                                }
                                if let detail = interpretServiceProviderDetail(reseau.providerId) {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(compte(reseau.lines.count, "ligne", "lignes")
                                     + " · " + compte(reseau.stopCount, "arrêt", "arrêts"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Réseaux")
                } footer: {
                    Text("Une pastille signale ce que tu as nommé toi-même. Le reste vient du référentiel, et n'est là que parce qu'il porte une de tes saisies.")
                }
            }
        }
        .navigationTitle("Données saisies")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


/// Les lignes d'un réseau.
struct ManualNetworkView: View {
    let providerId: Int

    @ObservedObject private var journal = ManualEntries.shared

    private var reseau: ManualNetwork? {
        journal.networks.first { $0.providerId == providerId }
    }

    var body: some View {
        List {
            if let entry = reseau?.entry {
                Section {
                    LabeledContent("Identifiant", value: "\(entry.providerId)")
                    LabeledContent("Libellé", value: entry.displayName)
                    Button(role: .destructive) {
                        journal.delete(provider: entry.id)
                    } label: {
                        Label("Oublier ce nom", systemImage: "trash")
                    }
                } header: {
                    Text("Ce que tu as saisi")
                } footer: {
                    Text("Sans ce nom, l'exploitant réafficherait son numéro brut.")
                }
            }

            Section {
                ForEach(reseau?.lines ?? []) { ligne in
                    NavigationLink {
                        ManualLineView(providerId: providerId, lineName: ligne.name)
                    } label: {
                        HStack(spacing: 10) {
                            PastilleLigne(nom: ligne.name ?? "?",
                                          fond: ligne.backgroundColor,
                                          texte: ligne.textColor)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ligne.name ?? "Sans ligne")
                                    if ligne.entry != nil { EtiquetteSaisie() }
                                }
                                Text(compte(ligne.stopCount, "arrêt", "arrêts")
                                     + " · " + compte(ligne.codeCount, "code", "codes"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Lignes")
            } footer: {
                Text("Les arrêts relevés sans ligne connue sont regroupés à part.")
            }
        }
        .navigationTitle(interpretServiceProviderShortName(providerId))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


/// Les arrêts d'une ligne, chacun avec les codes qui le désignent.
struct ManualLineView: View {
    let providerId: Int
    let lineName: String?

    @ObservedObject private var journal = ManualEntries.shared
    @State private var renommage: Renommage?

    private struct Renommage: Identifiable {
        let id: UUID
        let quoi: Quoi
        var nom: String
        enum Quoi { case ligne, arret }
    }

    private var ligne: ManualLine? {
        journal.networks
            .first { $0.providerId == providerId }?
            .lines.first { $0.name == lineName }
    }

    var body: some View {
        List {
            if let entry = ligne?.entry {
                Section {
                    LabeledContent("Numéro de course", value: "\(entry.routeNumber)")
                    LabeledContent("Mode", value: entry.mode)
                    if let publicId = entry.publicId {
                        LabeledContent("Identifiant IDFM", value: publicId)
                    }
                    Button {
                        renommage = Renommage(id: entry.id, quoi: .ligne, nom: entry.name)
                    } label: {
                        Label("Renommer la ligne", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        journal.delete(line: entry.id)
                    } label: {
                        Label("Oublier ce nom", systemImage: "trash")
                    }
                } header: {
                    Text("Ce que tu as saisi")
                } footer: {
                    Text("Sans ce nom, la ligne réafficherait son numéro de course.")
                }
            }

            if let arrets = ligne?.stops, !arrets.isEmpty {
                ForEach(arrets) { arret in
                    Section {
                        ForEach(arret.reports) { report in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("\(report.locationId)")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                    Text(report.mode)
                                    if !report.hasCoordinates { Text("sans position") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let reference = report.referenceId {
                                    Text("Arrêt IDFM \(reference)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                renommage = Renommage(id: report.id, quoi: .arret, nom: report.stationName)
                            }
                            .swipeActions {
                                Button("Supprimer", role: .destructive) { journal.delete(stop: report.id) }
                            }
                        }
                    } header: {
                        HStack {
                            Text(arret.name)
                            Spacer()
                            Text(compte(arret.reports.count, "code", "codes"))
                        }
                    }
                }
            } else {
                Section {
                    Text("Aucun arrêt identifié sur cette ligne")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(lineName ?? "Sans ligne")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Renommer", isPresented: Binding(get: { renommage != nil },
                                                set: { if !$0 { renommage = nil } }),
               presenting: renommage) { cible in
            TextField("Nom", text: Binding(get: { renommage?.nom ?? "" },
                                           set: { renommage?.nom = $0 }))
            Button("Annuler", role: .cancel) { renommage = nil }
            Button("Enregistrer") {
                let nom = (renommage?.nom ?? "").trimmed
                if !nom.isEmpty {
                    switch cible.quoi {
                    case .ligne: journal.rename(line: cible.id, to: nom)
                    case .arret: journal.rename(stop: cible.id, to: nom)
                    }
                }
                renommage = nil
            }
        } message: { cible in
            Text(cible.quoi == .ligne
                 ? "Le nom qui remplace le numéro de course à l'écran."
                 : "Le nom qui remplace le code d'arrêt à l'écran. Tous les codes rangés sous ce nom le suivent.")
        }
    }
}


// MARK: - Menus

/// Le journal contient les arrêts d'un même lieu sous plusieurs codes : le
/// compte accompagne chaque niveau pour qu'on sache ce qu'on va ouvrir.
private func compte(_ n: Int, _ singulier: String, _ pluriel: String) -> String {
    "\(n) \(n == 1 ? singulier : pluriel)"
}

/// Distingue ce qui a été nommé à la main de ce qui vient du référentiel.
private struct EtiquetteSaisie: View {
    var body: some View {
        Text("saisi")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

private struct PastilleLigne: View {
    let nom: String
    let fond: String
    let texte: String

    var body: some View {
        Text(nom)
            .font(.system(size: 15, weight: .bold))
            .frame(minWidth: 25, minHeight: 25)
            .padding(.horizontal, nom.count > 1 ? 6 : 0)
            .background(Color(hex: fond))
            .foregroundColor(Color(hex: texte))
            .cornerRadius(4)
    }
}

#Preview {
    NavigationStack { ManualDataView() }
}
