//
//  ManualDataView.swift
//  metroreader
//

import SwiftUI
import CoreLocation


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
                                          mode: ligne.mode,
                                          fond: ligne.backgroundColor,
                                          texte: ligne.textColor,
                                          noctilien: ligne.reference?.is_noctilien ?? false)
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
    @State private var corrigeLaLigne = false
    @State private var confirmation: Confirmation?

    private struct Renommage: Identifiable {
        let id: UUID
        let quoi: Quoi
        var nom: String
        enum Quoi { case ligne, arret }
    }

    /// Une correction proposée, en attente d'un oui.
    ///
    /// Ces boutons sont serrés les uns contre les autres et renomment d'un
    /// contact : viser à côté suffisait à renommer un arrêt pour un autre, sans
    /// rien à annuler derrière.
    private struct Confirmation: Identifiable {
        let id = UUID()
        let ancien: String
        let nouveau: String
        let codes: [UUID]
    }

    private var ligne: ManualLine? {
        journal.networks
            .first { $0.providerId == providerId }?
            .lines.first { $0.name == lineName }
    }

    /// L'identifiant IDFM de la ligne : celui qu'on a saisi, sinon celui que le
    /// référentiel lui donne. C'est lui qui ouvre la liste de ses arrêts, donc
    /// lui qui permet de juger ceux qu'on a nommés.
    private var publicId: String? {
        ligne?.entry?.publicId ?? ligne?.reference?.public_id
    }

    /// Les numéros de course que la carte annonce pour cette ligne.
    ///
    /// C'est le seul numéro qui puisse servir de clé à une saisie : le
    /// référentiel rend parfois une ligne dont le `line_id` diffère, quand il a
    /// fallu retomber sur `line_id >> 8`. Une même ligne s'annonce aussi sous
    /// plusieurs numéros, d'où la liste.
    private var courses: [Int] {
        var vus = Set<Int>()
        var out: [Int] = []
        if let n = ligne?.entry?.routeNumber, vus.insert(n).inserted { out.append(n) }
        for arret in ligne?.stops ?? [] {
            for report in arret.reports {
                if let n = report.routeNumber, vus.insert(n).inserted { out.append(n) }
            }
        }
        return out
    }

    private var laLigne: String {
        lineName.map { "la ligne \($0)" } ?? "cette ligne"
    }

    /// Un arrêt nommé que la ligne ne dessert pas.
    ///
    /// Le code qu'écrit un valideur de bus ou de tram est un numéro de séquence
    /// le long de sa ligne : l'arrêt qu'il désigne y figure forcément. Un nom
    /// absent de la liste vient donc d'une saisie faite depuis une autre ligne,
    /// ou d'un libellé emprunté à un réseau voisin. Sans liste d'arrêts pour la
    /// ligne, on ne juge rien.
    private func pistes(pour arret: ManualStop) -> [LineStop]? {
        guard let publicId, LineStops.connait(publicId),
              !LineStops.dessert(publicId, arret: arret.name) else { return nil }
        // La position relevée d'abord : elle situe l'arrêt, là où le nom ne dit
        // que ce qu'on a bien voulu taper.
        if let report = arret.reports.first(where: \.hasCoordinates),
           let lat = report.lat, let lon = report.lon {
            let proches = LineStops.around(CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                           forLine: publicId, limit: 3)
            if !proches.isEmpty { return proches.map(\.stop) }
        }
        return LineStops.semblables(arret.name, forLine: publicId)
    }

    /// L'avertissement porté par un arrêt que la ligne ne dessert pas, et les
    /// arrêts de la ligne qui le remplaceraient. Corriger d'ici emmène tous les
    /// codes rangés sous ce nom, pas seulement celui qu'on regarde.
    @ViewBuilder
    private func alerteHorsLigne(_ pistes: [LineStop], pour arret: ManualStop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ce nom ne figure pas sur \(laLigne)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.orange)

            if pistes.isEmpty {
                Text("Aucun arrêt de la ligne ne s'en approche, ni par la position ni par le nom. Touche un code pour corriger à la main.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Soit l'arrêt d'une autre ligne, soit le même lieu sous un autre libellé. Sur la ligne :")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pistes, id: \.libelle) { piste in
                    Button {
                        confirmation = Confirmation(ancien: arret.name,
                                                    nouveau: piste.libelle,
                                                    codes: arret.reports.map(\.id))
                    } label: {
                        Label(piste.libelle, systemImage: "arrow.turn.down.right")
                            .font(.callout)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.orange.opacity(0.10))
    }

    var body: some View {
        List {
            // L'éditeur passe en tête quoi qu'il arrive : une ligne reconnue
            // par le référentiel se corrige comme une autre, et c'est même là
            // qu'on en a besoin quand la reconnaissance est tombée à côté.
            Section {
                LabeledContent("Numéro de course",
                               value: courses.isEmpty
                                      ? "inconnu"
                                      : courses.map(String.init).joined(separator: ", "))
                LabeledContent("Mode", value: ligne?.mode ?? "inconnu")
                LabeledContent("Identifiant IDFM", value: publicId ?? "aucun")

                if let course = courses.first, let mode = ligne?.mode {
                    Button {
                        corrigeLaLigne = true
                    } label: {
                        Label(ligne?.entry == nil ? "Corriger la ligne" : "Changer de ligne",
                              systemImage: "arrow.triangle.swap")
                    }
                    .sheet(isPresented: $corrigeLaLigne) {
                        IdentifyLineSheet(providerId: providerId, routeNumber: course, mode: mode)
                    }
                }

                if let entry = ligne?.entry {
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
                }
            } header: {
                Text(ligne?.entry != nil ? "Ce que tu as saisi" : "Ce que le référentiel dit")
            } footer: {
                Text(ligne?.entry != nil
                     ? "Sans ce nom, la ligne réafficherait son numéro de course."
                     : "Cette ligne vient du référentiel. La corriger crée une saisie qui la remplace partout, et rend sa liste d'arrêts — celle qui sert à vérifier les noms ci-dessous.")
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
                        if let pistes = pistes(pour: arret) {
                            alerteHorsLigne(pistes, pour: arret)
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
        .alert("Renommer cet arrêt ?",
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { cible in
            Button("Annuler", role: .cancel) { confirmation = nil }
            Button("Renommer") {
                journal.rename(stops: cible.codes, to: cible.nouveau)
                confirmation = nil
            }
        } message: { cible in
            Text("« \(cible.ancien) » deviendra « \(cible.nouveau) », et "
                 + (cible.codes.count == 1
                    ? "le code rangé sous ce nom le suit."
                    : "les \(cible.codes.count) codes rangés sous ce nom le suivent."))
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

#Preview {
    NavigationStack { ManualDataView() }
}
