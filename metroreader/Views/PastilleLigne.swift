//
//  PastilleLigne.swift
//  metroreader
//

import SwiftUI


/// Une ligne, telle qu'on la reconnaît sur un quai.
///
/// Métro, RER, Transilien, tramway et câble ont un indice officiel dessiné par
/// Île-de-France Mobilités — le rond du métro, le carré du RER et du train :
/// c'est lui qu'on montre. Le reste garde une pastille de texte aux couleurs de
/// la ligne.
struct PastilleLigne: View {
    let nom: String
    let mode: String?
    let fond: String
    let texte: String
    var taille: CGFloat = 25

    init(nom: String, mode: String?, fond: String, texte: String, taille: CGFloat = 25) {
        self.nom = nom
        self.mode = mode
        self.fond = fond
        self.texte = texte
        self.taille = taille
    }

    init(_ ligne: NavigoLineInfo, taille: CGFloat = 25) {
        self.init(nom: ligne.name, mode: ligne.mode, fond: ligne.background_color,
                  texte: ligne.text_color, taille: taille)
    }

    /// Ce que la pastille écrit. Un TER porte le nom de sa région — « TER Centre
    /// - Val de Loire » — qui ne tient pas dans une pastille : il s'y dit TER, et
    /// le nom complet reste pour VoiceOver.
    private var libelle: String { modeTransport == .ter ? "TER" : nom }

    private var modeTransport: ModeTransport? { mode.flatMap(ModeTransport.init(rawValue:)) }

    var body: some View {
        let indices = IndicesLignes.images(nom: nom, mode: mode)
        if indices.isEmpty {
            Text(libelle)
                .font(.system(size: 16 * (taille / 25), weight: .bold))
                // À l'étroit, une pastille comprimée n'était plus qu'un trait
                // gris : elle garde sa largeur, comme les indices à côté d'elle.
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: libelle.count == 1 ? taille : nil, height: taille)
                .padding(.horizontal, libelle.count > 1 ? taille / 5 : 0)
                .background(Color(hex: fond))
                .cornerRadius(modeTransport == .metro ? taille / 2 : 4)
                .foregroundColor(Color(hex: texte))
                .accessibilityLabel(nom)
        } else {
            HStack(spacing: taille / 10) {
                ForEach(indices, id: \.self) { indice in
                    Image(indice)
                        .resizable()
                        .scaledToFit()
                        .frame(width: taille, height: taille)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(nom)
        }
    }
}

#Preview {
    HStack {
        PastilleLigne(nom: "3B", mode: "Métro", fond: "6ec4e8", texte: "000000")
        PastilleLigne(nom: "16/17", mode: "Métro", fond: "000000", texte: "ffffff")
        PastilleLigne(nom: "A", mode: "RER", fond: "eb2132", texte: "ffffff")
        PastilleLigne(nom: "T3a", mode: "Tramway", fond: "ff5a00", texte: "ffffff")
        PastilleLigne(nom: "183", mode: "Bus urbain", fond: "82c8e6", texte: "000000")
    }
}
