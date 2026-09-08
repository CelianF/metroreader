//
//  IdentifyProviderSheet.swift
//  metroreader
//

import SwiftUI


/// Nommage d'un exploitant que la carte désigne par un numéro auquel aucun
/// libellé ne répond.
///
/// Les champs sont ceux du référentiel, et pour la même raison : un exploitant
/// d'Île-de-France se nomme par son réseau, la société qui le fait rouler et le
/// numéro de lot de sa délégation. SNCF et RATP n'en ont pas — d'où le libellé
/// simple, pour tout ce qui n'entre pas dans ce moule.
struct IdentifyProviderSheet: View {
    let providerId: Int

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var journal = ManualEntries.shared

    private enum Forme: Int, CaseIterable {
        case dsp, libelle
        var titre: String { self == .dsp ? "Délégation" : "Libellé simple" }
    }

    @State private var forme: Forme = .dsp
    @State private var reseau = ""
    @State private var exploitant = ""
    @State private var dsp = ""
    @State private var libelle = ""

    init(providerId: Int) {
        self.providerId = providerId
        let existant = ManualEntries.shared.provider(providerId)
        _reseau = State(initialValue: existant?.network ?? "")
        _exploitant = State(initialValue: existant?.operatorName ?? "")
        _dsp = State(initialValue: existant?.dsp.map(String.init) ?? "")
        _libelle = State(initialValue: existant?.name ?? "")
        _forme = State(initialValue: (existant?.network?.isEmpty == false) ? .dsp
                                   : (existant?.name?.isEmpty == false) ? .libelle : .dsp)
    }

    private func suggestions(_ connus: [String], pour saisie: String) -> [String] {
        guard !saisie.isEmpty else { return [] }
        let correspondances = connus.filter { $0.localizedCaseInsensitiveContains(saisie) }
        // Une correspondance exacte n'a rien à proposer.
        if correspondances.count == 1 && correspondances[0] == saisie { return [] }
        return Array(correspondances.prefix(5))
    }

    private var estValide: Bool {
        forme == .dsp ? !reseau.trimmed.isEmpty : !libelle.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Identifiant", value: "\(providerId)")
                } header: {
                    Text("Ce que la carte annonce")
                } footer: {
                    Text("Aucun libellé ne répond à ce numéro d'exploitant. En le nommant, tu l'ajoutes au journal, consultable depuis Réglages › Données.")
                }

                Section {
                    Picker("Forme", selection: $forme) {
                        ForEach(Forme.allCases, id: \.rawValue) { forme in
                            Text(forme.titre).tag(forme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if forme == .dsp {
                    Section {
                        TextField("Réseau", text: $reseau)
                        ForEach(suggestions(ProviderCatalog.knownNetworkNames, pour: reseau), id: \.self) { nom in
                            Button(nom) { reseau = nom }
                                .font(.caption)
                        }
                    } header: {
                        Text("Réseau")
                    } footer: {
                        Text("Le nom du réseau tel qu'IDFM le publie, par exemple « Paris Saclay » ou « Vallée Sud Bièvre ».")
                    }

                    Section {
                        TextField("Exploitant", text: $exploitant)
                        ForEach(suggestions(ProviderCatalog.knownOperatorNames, pour: exploitant), id: \.self) { nom in
                            Button(nom) { exploitant = nom }
                                .font(.caption)
                        }
                    } header: {
                        Text("Exploitant")
                    } footer: {
                        Text("La société qui fait rouler le réseau. Facultatif.")
                    }

                    Section {
                        TextField("Numéro de lot", text: $dsp)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    } header: {
                        Text("Délégation de service public")
                    } footer: {
                        Text("Facultatif. Il s'affiche entre parenthèses derrière l'exploitant.")
                    }
                } else {
                    Section {
                        TextField("Nom", text: $libelle)
                    } header: {
                        Text("Libellé")
                    } footer: {
                        Text("Pour ce qui n'est pas une délégation : un opérateur historique, un service dédié, un réseau hors Île-de-France.")
                    }
                }

                Section {
                    LabeledContent("Aperçu", value: apercu)
                }
            }
            .navigationTitle("Identifier le réseau")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { enregistrer() }
                        .disabled(!estValide)
                }
            }
        }
    }

    private var apercu: String {
        entree.displayName
    }

    private var entree: ProviderEntry {
        ProviderEntry(id: journal.provider(providerId)?.id ?? UUID(),
                      date: Date(),
                      providerId: providerId,
                      network: forme == .dsp ? reseau.trimmed.nilIfEmpty : nil,
                      operatorName: forme == .dsp ? exploitant.trimmed.nilIfEmpty : nil,
                      dsp: forme == .dsp ? Int(dsp.trimmed) : nil,
                      name: forme == .libelle ? libelle.trimmed.nilIfEmpty : nil)
    }

    private func enregistrer() {
        guard estValide else { return }
        journal.save(entree)
        dismiss()
    }
}
