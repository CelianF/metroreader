//
//  CreditsAssetsView.swift
//  metroreader
//

import SwiftUI


/// À qui l'on doit les visuels de l'app : les cartes dessinées, et les logos
/// qui restent la propriété de leurs détenteurs.
struct CreditsAssetsView: View {
    var body: some View {
        List {
            Section {
                Auteur(nom: "andretc", role: "Carte Aéroport", photo: "andretc")
                Auteur(nom: "Stitch", role: "Les autres cartes", photo: "Stitch")
            } header: {
                Text("Visuels des cartes")
            }

            Section {
                Text("Île-de-France Mobilités")
                Text("Transilien SNCF")
                Text("RATP")
            } header: {
                Text("Logos et certains éléments")
            } footer: {
                Text("Ces logos, pictogrammes et éléments graphiques appartiennent à leurs détenteurs respectifs. Ils ne servent ici qu'à reconnaître les cartes, les lignes et les modes.")
            }

            Section {
            } footer: {
                Text("PassReader est une application indépendante. Elle n'est ni affiliée, ni approuvée, ni soutenue par Île-de-France Mobilités, SNCF Voyageurs, Transilien SNCF ou la RATP.")
            }
        }
        .navigationTitle("Assets")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}


/// Un auteur de visuels : sa photo, son nom, ce qu'il a dessiné.
private struct Auteur: View {
    let nom: String
    let role: String
    let photo: String

    @ScaledMetric(relativeTo: .body) private var cotePhoto: CGFloat = 40

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(nom)
                    .font(.headline)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(photo)
                .resizable()
                .scaledToFill()
                .frame(width: cotePhoto, height: cotePhoto)
                .clipShape(Circle())
        }
        .padding(.vertical, 4)
    }
}


#Preview {
    NavigationStack { CreditsAssetsView() }
}
