//
//  CreditRow.swift
//  metroreader
//

import SwiftUI


/// Une personne derrière l'app, dans Réglages : sa photo de profil d'abord,
/// puis son nom suivi du logo de son compte Twitter, que la rangée ouvre.
struct CreditRow: View {
    let nom: String
    let role: String
    /// La photo de profil, dans les assets
    let photo: String
    let compte: URL

    /// Les tailles suivent celles du texte choisies par l'utilisateur, comme
    /// les logos du reste de l'écran.
    @ScaledMetric(relativeTo: .body) private var cotePhoto: CGFloat = 40
    @ScaledMetric(relativeTo: .headline) private var coteLogo: CGFloat = 16

    var body: some View {
        Link(destination: compte) {
            Label {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(nom)
                            .font(.headline)

                        Image("Twitter")
                            .resizable()
                            .scaledToFit()
                            .frame(width: coteLogo, height: coteLogo)
                    }

                    Text(role)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cotePhoto, height: cotePhoto)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }
}
