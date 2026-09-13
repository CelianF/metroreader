//
//  PastilleLigne.swift
//  metroreader
//

import SwiftUI


/// Une ligne, telle qu'on la reconnaît sur un quai.
///
/// Métro, RER, Transilien, tramway et câble ont un indice officiel dessiné par
/// Île-de-France Mobilités — le rond du métro, le carré du RER et du train :
/// c'est lui qu'on montre, comme le logo d'Orlyval. Le reste garde une pastille
/// de texte aux couleurs de la ligne ; celle du Noctilien est bleu nuit, sa
/// couleur de ligne réduite à une bande dessous.
struct PastilleLigne: View {
    let nom: String
    let mode: String?
    let fond: String
    let texte: String
    var taille: CGFloat = 25
    let noctilien: Bool

    private static let bleuNoctilien = "0F408B"

    init(nom: String, mode: String?, fond: String, texte: String, taille: CGFloat = 25,
         noctilien: Bool = false) {
        self.nom = nom
        self.mode = mode
        self.fond = fond
        self.texte = texte
        self.taille = taille
        // Une validation et les lignes d'un arrêt disent « Noctilien » par leur
        // mode ; le référentiel, lui, les laisse en bus et lève un drapeau.
        self.noctilien = noctilien || mode == ModeTransport.noctilien.rawValue
    }

    init(_ ligne: NavigoLineInfo, taille: CGFloat = 25) {
        self.init(nom: ligne.name, mode: ligne.mode, fond: ligne.background_color,
                  texte: ligne.text_color, taille: taille, noctilien: ligne.is_noctilien)
    }

    /// Ce que la pastille écrit. Un TER porte le nom de sa région — « TER Centre
    /// - Val de Loire » — qui ne tient pas dans une pastille : il s'y dit TER, et
    /// le nom complet reste pour VoiceOver.
    private var libelle: String { modeTransport == .ter ? "TER" : nom }

    private var modeTransport: ModeTransport? { mode.flatMap(ModeTransport.init(rawValue:)) }

    var body: some View {
        let indices = IndicesLignes.images(nom: nom, mode: mode)
        if indices.isEmpty {
            // Le cinquième bas du Noctilien, à la couleur de la ligne : le
            // numéro se pose au-dessus.
            let bande = noctilien ? taille / 5 : 0
            Text(libelle)
                .font(.system(size: 16 * (taille / 25), weight: .bold))
                // À l'étroit, une pastille comprimée n'était plus qu'un trait
                // gris : elle garde sa largeur, comme les indices à côté d'elle.
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: libelle.count == 1 ? taille : nil, height: taille - bande)
                .padding(.bottom, bande)
                .padding(.horizontal, libelle.count > 1 ? taille / 5 : 0)
                .background {
                    VStack(spacing: 0) {
                        Color(hex: noctilien ? Self.bleuNoctilien : fond)
                        Color(hex: fond).frame(height: bande)
                    }
                }
                .cornerRadius(modeTransport == .metro ? taille / 2 : 4)
                .foregroundColor(noctilien ? .white : Color(hex: texte))
                .accessibilityLabel(nom)
        } else {
            HStack(spacing: taille / 10) {
                ForEach(indices, id: \.self) { indice in
                    Image(indice)
                        .resizable()
                        .scaledToFit()
                        .frame(width: IndicesLignes.largeur(indice, hauteur: taille), height: taille)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(nom)
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        HStack {
            PastilleLigne(nom: "3B", mode: "Métro", fond: "6ec4e8", texte: "000000")
            PastilleLigne(nom: "16/17", mode: "Métro", fond: "000000", texte: "ffffff")
            PastilleLigne(nom: "A", mode: "RER", fond: "eb2132", texte: "ffffff")
            PastilleLigne(nom: "T3a", mode: "Tramway", fond: "ff5a00", texte: "ffffff")
            PastilleLigne(nom: "183", mode: "Bus urbain", fond: "82c8e6", texte: "000000")
        }
        HStack {
            PastilleLigne(nom: "FUN", mode: "Câble", fond: "afafaf", texte: "000000")
            PastilleLigne(nom: "ORLYVAL", mode: "Train", fond: "5ec5ed", texte: "ffffff")
            PastilleLigne(nom: "N01", mode: "Noctilien", fond: "a0006e", texte: "ffffff")
            PastilleLigne(nom: "N122", mode: "Noctilien", fond: "ffbe00", texte: "000000")
        }
    }
}
