//
//  ShippedCorrectionsView.swift
//  metroreader
//

import SwiftUI


/// Les corrections que l'app livre, données à lire et rien d'autre.
///
/// Elles surchargent le référentiel là où il rattache une course à la mauvaise
/// ligne. Rien ne s'y modifie : ce sont des données de l'app, pas du journal —
/// mais elles se lisent, parce qu'une surcharge invisible est une surcharge
/// qu'on ne peut pas contester.
struct ShippedCorrectionsView: View {
    private var corrections: [LineCorrection] { LineCorrections.all }

    private func compteCourses(_ n: Int) -> String {
        n == 1 ? "1 course" : "\(n) courses"
    }

    var body: some View {
        List {
            if corrections.isEmpty {
                Section {
                    Text("Aucune correction livrée")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Le référentiel rattache parfois un numéro de course à la mauvaise ligne. Les redressements connus se rangeraient ici.")
                }
            } else {
                Section {
                    ForEach(LineCorrections.parExploitant, id: \.providerId) { reseau in
                        NavigationLink {
                            ShippedNetworkCorrectionsView(providerId: reseau.providerId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(interpretServiceProviderShortName(reseau.providerId))
                                if let detail = interpretServiceProviderDetail(reseau.providerId) {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(compteCourses(reseau.corrections.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Réseaux")
                } footer: {
                    Text("Le numéro de course qu'une carte annonce n'est publié nulle part : le référentiel ne donne qu'un code, qu'il partage parfois entre plusieurs lignes. Le rapprochement se fait donc en observant de vraies cartes, et il se trompe parfois de ligne.")
                }

                Section {
                    Text("Ces corrections sont livrées avec l'app et ne se modifient pas ici. Ce que tu nommes toi-même, dans Données saisies, l'emporte sur elles.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Corrections livrées")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


/// Les courses redressées d'un réseau.
private struct ShippedNetworkCorrectionsView: View {
    let providerId: Int

    private var corrections: [LineCorrection] {
        LineCorrections.parExploitant.first { $0.providerId == providerId }?.corrections ?? []
    }

    var body: some View {
        List {
            Section {
                ForEach(corrections) { correction in
                    NavigationLink {
                        ShippedCorrectionDetailView(correction: correction)
                    } label: {
                        LigneCorrigee(correction: correction)
                    }
                }
            } header: {
                Text("Courses")
            } footer: {
                Text("Le numéro de course est ce que la carte annonce. Le référentiel le rattachait à une autre ligne, ou à aucune.")
            }
        }
        .navigationTitle(interpretServiceProviderShortName(providerId))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


/// La ligne retenue, et celle qu'elle déloge.
private struct LigneCorrigee: View {
    let correction: LineCorrection

    private var retenue: NavigoLineInfo? { LineCorrections.ligne(correction) }
    private var delogee: NavigoLineInfo? {
        correction.remplace.flatMap { NavigoLines.byPublicId($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let retenue {
                    LineIcons(lines: [retenue])
                } else {
                    Text(correction.public_id).fontWeight(.semibold)
                }
            }
            Text("course \(correction.line_id)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let delogee {
                Text("à la place de \(delogee.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("créneau vide au référentiel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


/// Le détail d'une correction : ce qu'elle change, et sur quelle foi.
private struct ShippedCorrectionDetailView: View {
    let correction: LineCorrection

    private var retenue: NavigoLineInfo? { LineCorrections.ligne(correction) }
    private var delogee: NavigoLineInfo? {
        correction.remplace.flatMap { NavigoLines.byPublicId($0) }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Exploitant", value: interpretServiceProviderName(correction.provider_id))
                LabeledContent("Numéro de course", value: "\(correction.line_id)")
                LabeledContent("Mode", value: correction.mode)
            } header: {
                Text("Ce que la carte annonce")
            }

            Section {
                if let retenue {
                    HStack {
                        LineIcons(lines: [retenue])
                        Spacer()
                        Text(retenue.public_id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Identifiant", value: correction.public_id)
                }
            } header: {
                Text("Ligne retenue")
            }

            if let delogee {
                Section {
                    HStack {
                        LineIcons(lines: [delogee])
                        Spacer()
                        Text(delogee.public_id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ligne délogée")
                } footer: {
                    Text("Ce que le référentiel répondait à cette course.")
                }
            }

            Section {
                if let fonde = correction.fonde_sur {
                    LabeledContent("Fondement", value: fonde)
                }
                if let jour = correction.jour {
                    LabeledContent("Constaté le", value: jour.formatted(date: .long, time: .omitted))
                } else if let constate = correction.constate {
                    LabeledContent("Constaté le", value: constate)
                }
            } header: {
                Text("D'où ça vient")
            } footer: {
                if let raison = correction.raison {
                    Text(raison)
                }
            }
        }
        .navigationTitle(retenue?.name ?? correction.public_id)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


#Preview {
    NavigationStack { ShippedCorrectionsView() }
}
