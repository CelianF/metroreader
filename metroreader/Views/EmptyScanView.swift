//
//  EmptyScanView.swift
//  metroreader
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EmptyScanView: View {
    var isScanning: Bool = false
    /// Levé dès que la carte est sous l'antenne : l'animation en cours va à son
    /// terme, mais on n'en relance pas.
    var isTagDetected: Bool = false
    let onScan: () -> Void
    let onImport: () -> Void

    @State private var pulse = false

    /// Le centre et le côté de la cible au repos. Déduits de la colonne,
    /// jamais mesurés sur la cible elle-même : `frame(in: .global)` suit le
    /// décalage, donc une mesure prise là décrirait l'arrivée, ce qui
    /// annulerait le décalage, ce qui la ramènerait au départ — sans fin.
    @State private var mesure = MesureCible()

    /// Le passe montré en exemple, retiré au sort à chaque tour.
    @State private var exemple: String?

    /// Ce que le cycle a déjà montré. Une carte vue ne repasse plus jusqu'à la
    /// lecture suivante ; annuler et relancer rend tout le vivier disponible.
    @State private var dejaVues: Set<String> = []

    /// La catégorie du tour précédent, pour ne pas la reprendre aussitôt.
    @State private var derniereCategorie: String?

    /// Où en est la carte dans sa traversée.
    @State private var etape = Etape.cachee

    /// Vrai quand le tour en cours doit être le dernier. Un `@State` plutôt
    /// que le paramètre lui-même : la boucle tourne dans une tâche qui a
    /// capturé la vue, elle relirait éternellement la valeur du départ.
    @State private var dernierTour = false

    /// Tiré au sort à chaque tour : le bord d'où la carte entre (-1 à gauche,
    /// +1 à droite), son inclinaison en arrivant, celle qu'elle garde une fois
    /// posée. Deux passages ne se ressemblent donc jamais tout à fait.
    @State private var sensEntree: CGFloat = 1
    @State private var angleEntree: Double = 0
    @State private var anglePose: Double = 0

    /// Hauteur du bouton de scan, mesurée pour que l'import soit un cercle
    /// exactement aussi haut. Le style système décide de sa propre marge, on ne
    /// peut donc pas la deviner.
    @State private var hauteurBouton: CGFloat = 0

    private static let hauteurContenu: CGFloat = 30

    /// Côté maximal de la cible, pour qu'elle ne devienne pas démesurée sur
    /// iPad. Sert aussi à déduire sa hauteur, le dessin étant carré.
    private static let coteCible: CGFloat = 420

    /// Proportions de la carte : celles des SVG du catalogue (533 × 334), et
    /// sa largeur en fraction du côté de la cible avant qu'elle ne se pose.
    private static let formatCarte: CGFloat = 533 / 334
    private static let largeurCarte: CGFloat = 0.55

    /// Ce qui reste de la carte une fois posée sur la cible. Elle rapetisse en
    /// se posant, comme si elle s'éloignait d'un cran vers le fond.
    private static let echellePosee: CGFloat = 0.72

    /// De combien la carte se pose sous le centre de la cible, en fraction de
    /// son côté. Pile au centre, elle irait se loger derrière la Dynamic
    /// Island et déborderait du haut de l'écran : c'est le temps où elle
    /// s'attarde le plus, autant qu'elle y soit entière.
    private static let poseSousCentre: CGFloat = 0.20

    /// Le vivier des exemples, les cartes d'entreprise écartées. Rangé par
    /// catégorie et non à plat : le tirage a besoin de savoir d'où vient
    /// chaque carte. Ordre et contenu : Data/PassCategories.json
    private static let vivier: [PassCategory] = PassCatalog.categories
        .filter { $0.folder != "Entreprises" }

    /// Les visuels par défaut, ceux qu'on a vraiment en poche. Ils sortent une
    /// fois et demie plus souvent que les autres.
    private static let categorieCourante = "Originaux"
    private static let faveurCourante = 1.5

    /// Une carte et la catégorie d'où elle sort.
    private struct Tirage {
        let image: String
        let categorie: String
    }

    /// Les quatre temps de la traversée d'une carte.
    private enum Etape {
        /// Hors champ, sur le côté, en attente d'entrer.
        case cachee
        /// Arrivée à plat dans le creux que la cible laisse en montant.
        case sousCible
        /// Remontée et posée sur la cible, plus petite et presque droite.
        case posee
        /// Repartie par le haut.
        case sortie
    }

    var body: some View {
        VStack(spacing: 24) {
            cible

            Text(isScanning ? "Collez la carte sur la cible" : "Aucun Navigo scanné")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            actions
        }
        .background(mesureColonne)
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(CibleKey.self) { mesure = $0 }
    }

    // MARK: - Cible

    /// Pendant la lecture, la cible monte jusqu'à ce que son centre tombe sur
    /// la Dynamic Island : l'antenne NFC est juste derrière, sous les caméras.
    /// Sa moitié haute sort de l'écran, ce qui suffit à dire où poser la carte
    /// ; elle redescend dès que la lecture s'arrête ou est annulée.
    ///
    /// La carte d'exemple est empilée par-dessus : elle finit posée sur la
    /// cible, elle doit donc passer devant.
    private var cible: some View {
        ZStack {
            dessinCible
            carteExemple
        }
        .task(id: isScanning) { await defilerExemples() }
        .onChange(of: isTagDetected) { _, detectee in
            if detectee { dernierTour = true }
        }
    }

    private var dessinCible: some View {
        Image("Cible")
            .resizable()
            .scaledToFit()
            // Pleine largeur, bornée pour ne pas devenir démesurée sur iPad
            .frame(maxWidth: Self.coteCible)
            // Pendant la lecture, la cible bat entre demi-opacité et pleine
            .opacity(pulse ? 0.5 : 1.0)
            // L'animation est choisie ici plutôt qu'au moment de la
            // mutation : à l'arrêt, c'est le fondu court qui reprend la
            // main, là où un withAnimation laissait la boucle courir.
            .animation(isScanning
                       ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                       : .easeInOut(duration: 0.35),
                       value: pulse)
            // Le glissement est posé au-dessus du battement : plus bas, il
            // serait happé par la boucle infinie et la cible ferait la navette
            // au lieu de monter une fois. Un décalage plutôt qu'une mise en
            // page, pour que le reste de l'écran ne bouge pas avec elle.
            .offset(y: decalage)
            // L'animation suit le décalage lui-même et non isScanning : quand
            // la lecture repart depuis une carte affichée, l'écran vide naît
            // alors qu'elle a déjà commencé et isScanning ne change plus.
            .animation(.snappy(duration: 0.4), value: decalage)
            .onChange(of: isScanning) { _, enCours in pulse = enCours }
            .onAppear { pulse = isScanning }
    }

    // MARK: - Carte d'exemple

    /// Un passe tiré au sort, qui traverse l'écran pendant la lecture pour
    /// montrer le geste. Sa taille est fixée une fois pour toutes et c'est
    /// `scaleEffect` qui la fait rapetisser : une transformation s'anime sans
    /// relayouter, là où une largeur qui change ferait tressauter le dessin.
    @ViewBuilder
    private var carteExemple: some View {
        if let exemple, mesure.cote > 0 {
            let largeur = mesure.cote * Self.largeurCarte
            NavigoImage(imageName: exemple)
                .frame(width: largeur, height: largeur / Self.formatCarte)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
                .rotationEffect(.degrees(angleCarte))
                .scaleEffect(echelleCarte)
                .offset(decalageCarte)
                .transition(.opacity)
        }
    }

    /// Où se trouve la carte, en écart depuis le centre de l'emplacement de la
    /// cible. Le pas « posée » vise `decalage` : c'est de cette hauteur que la
    /// cible s'est déplacée, la carte tombe donc pile sur son centre.
    private var decalageCarte: CGSize {
        let cote = mesure.cote
        switch etape {
        case .cachee:
            return CGSize(width: sensEntree * cote * 1.3, height: cote * 0.30)
        case .sousCible:
            return CGSize(width: 0, height: cote * 0.30)
        case .posee:
            return CGSize(width: 0, height: decalage + cote * Self.poseSousCentre)
        case .sortie:
            // Assez haut pour sortir entièrement du cadre : la carte s'en va
            // en bougeant, elle ne s'efface pas sur place.
            return CGSize(width: 0, height: decalage - cote * 1.3)
        }
    }

    private var echelleCarte: CGFloat {
        switch etape {
        case .cachee, .sousCible: return 1
        case .posee, .sortie: return Self.echellePosee
        }
    }

    private var angleCarte: Double {
        switch etape {
        case .cachee, .sousCible: return angleEntree
        case .posee, .sortie: return anglePose
        }
    }

    /// La traversée, en boucle tant que la lecture dure : la carte entre par un
    /// bord, se pose sous la cible, remonte s'y poser, se réajuste d'un rien,
    /// attend, puis s'en va par le haut. Une tâche liée à `isScanning` plutôt
    /// qu'une minuterie : SwiftUI l'annule de lui-même à la fin de la lecture,
    /// et le sommeil s'interrompt avec.
    private func defilerExemples() async {
        guard isScanning else {
            withAnimation(.easeInOut(duration: 0.3)) { exemple = nil }
            etape = .cachee
            return
        }
        dernierTour = isTagDetected
        // Chaque lecture repart d'un vivier entier : une carte vue ne compte
        // que pour la lecture où elle est passée.
        dejaVues = []
        derniereCategorie = nil
        while !Task.isCancelled {
            // Le vivier épuisé, on cesse de montrer plutôt que de recommencer :
            // une carte ne repasse pas dans le même cycle.
            guard let tirage = Self.tirage(apres: derniereCategorie, dejaVues: dejaVues) else {
                exemple = nil
                return
            }
            dejaVues.insert(tirage.image)
            derniereCategorie = tirage.categorie

            // Hors animation : la carte doit reparaître sur le côté sans
            // revenir en arrière depuis sa sortie par le haut.
            exemple = tirage.image
            sensEntree = Bool.random() ? -1 : 1
            angleEntree = Double.random(in: 9...20) * (Bool.random() ? -1 : 1)
            anglePose = Double.random(in: -4...4)
            etape = .cachee
            guard await pause(0.1) else { return }

            // L'attente couvre l'entrée (0,75 s) et laisse ensuite la carte
            // immobile sous la cible : sans cette respiration, elle traverse
            // sans jamais s'y poser à plat, et le temps ne se lit pas.
            withAnimation(.easeOut(duration: 0.75)) { etape = .sousCible }
            guard await pause(1.5) else { return }

            // Un ressort qui rebondit un peu : la carte se pose, elle ne
            // s'arrête pas net.
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) { etape = .posee }
            guard await pause(0.8) else { return }

            // Le petit réajustement d'angle, comme une main qui rectifie.
            withAnimation(.easeInOut(duration: 0.8)) { anglePose += Double.random(in: -5...5) }
            guard await pause(1.6) else { return }

            withAnimation(.easeIn(duration: 0.55)) { etape = .sortie }
            guard await pause(0.6) else { return }

            // La carte est partie par le haut : c'est le seul moment où
            // s'arrêter ne coupe rien. Au-delà, la lecture accapare le fil
            // principal et le tour suivant ne serait qu'une suite de saccades.
            if dernierTour {
                exemple = nil
                return
            }
        }
    }

    /// Dort, et dit si la tâche a survécu — faux quand elle a été annulée.
    private func pause(_ secondes: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(secondes))
            return true
        } catch {
            return false
        }
    }

    /// La carte suivante : jamais une déjà vue dans ce cycle, jamais deux fois
    /// de suite la même catégorie — sans quoi deux Schol'R voisines passeraient
    /// pour un bégaiement.
    private static func tirage(apres derniere: String?, dejaVues: Set<String>) -> Tirage? {
        let restantes = vivier.flatMap { categorie in
            categorie.images
                .filter { !dejaVues.contains($0) }
                .map { Tirage(image: $0, categorie: categorie.folder) }
        }
        let autreCategorie = restantes.filter { $0.categorie != derniere }
        // La règle de catégorie cède la première : quand elle ne laisse plus
        // rien, mieux vaut répéter une catégorie que s'arrêter de montrer.
        return pondere(autreCategorie.isEmpty ? restantes : autreCategorie)
    }

    /// Tirage pondéré : les visuels courants pèsent une fois et demie les autres.
    private static func pondere(_ cartes: [Tirage]) -> Tirage? {
        guard !cartes.isEmpty else { return nil }
        let poids = cartes.map { $0.categorie == categorieCourante ? faveurCourante : 1 }
        let total = poids.reduce(0, +)
        var seuil = Double.random(in: 0..<total)
        for (carte, p) in zip(cartes, poids) {
            seuil -= p
            if seuil < 0 { return carte }
        }
        return cartes.last
    }

    // MARK: - Géométrie

    /// La colonne ne bouge pas quand son contenu se décale : c'est le seul
    /// repère sûr. La cible en occupe le haut, et son côté vaut la largeur
    /// disponible tant qu'elle n'est pas coiffée — d'où son centre.
    private var mesureColonne: some View {
        GeometryReader { proxy in
            let cote = min(proxy.size.width, Self.coteCible)
            Color.clear.preference(
                key: CibleKey.self,
                value: MesureCible(centre: proxy.frame(in: .global).minY + cote / 2,
                                   cote: cote)
            )
        }
    }

    /// De combien remonter pour amener le centre de la cible sur l'île.
    private var decalage: CGFloat {
        #if os(iOS)
        guard isScanning, mesure.cote > 0 else { return 0 }
        return centreIle - mesure.centre
        #else
        return 0
        #endif
    }

    #if os(iOS)
    /// Le centre vertical de la Dynamic Island, en coordonnées écran. Son cadre
    /// n'est pas public, mais la moitié de l'encart haut de la fenêtre tombe
    /// dessus sur les modèles à île (59 pt donne 29,5) et reste dans l'encoche
    /// sur les autres. La fenêtre plutôt que la vue : ici, la zone sûre
    /// compterait aussi la barre de navigation.
    private var centreIle: CGFloat {
        let fenetre = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return (fenetre?.safeAreaInsets.top ?? 59) / 2
    }
    #endif

    // MARK: - Boutons

    private var actions: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            styled(scanButton)
                .disabled(isScanning)
                .background(mesureBouton)
            importButton
            #else
            // Pas de NFC sur macOS : l'import reste la seule entrée
            styled(importButton)
            #endif
        }
        .onPreferenceChange(HauteurBouton.self) { hauteurBouton = $0 }
    }

    private var scanButton: some View {
        Button(action: onScan) {
            Text(isScanning ? "Scan en cours…" : "Scanner une carte")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: Self.hauteurContenu)
        }
    }

    #if os(iOS)
    /// Le même matériau que la barre du bas, translucide, sur un cercle aussi
    /// haut que le bouton de scan.
    private var importButton: some View {
        let cote = max(hauteurBouton, Self.hauteurContenu)
        return Button(action: onImport) {
            Image(systemName: "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: cote, height: cote)
                .background(.bar, in: Circle())
        }
        .buttonStyle(.plain)
    }
    #else
    private var importButton: some View {
        Button(action: onImport) {
            Label("Importer un fichier", systemImage: "square.and.arrow.down")
                .font(.headline)
                .frame(minHeight: Self.hauteurContenu)
        }
    }
    #endif

    /// Liquid Glass à partir d'iOS 26, style plein en dessous
    @ViewBuilder
    private func styled<V: View>(_ button: V, tint: Color = .blue) -> some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .tint(tint)
    }

    private var mesureBouton: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HauteurBouton.self, value: proxy.size.height)
        }
    }
}

/// Ce que la colonne sait de la cible : où tombe son centre à l'écran, et de
/// quel côté elle est. Les deux voyagent ensemble dans une seule préférence,
/// une par grandeur s'étant révélée trop fragile.
private struct MesureCible: Equatable {
    var centre: CGFloat = 0
    var cote: CGFloat = 0
}

private struct CibleKey: PreferenceKey {
    static let defaultValue = MesureCible()
    // Le plus grand côté l'emporte, comme le `max` de la hauteur des boutons :
    // sinon les frères de la colonne écrasent la mesure avec leur défaut.
    static func reduce(value: inout MesureCible, nextValue: () -> MesureCible) {
        let suivant = nextValue()
        if suivant.cote > value.cote { value = suivant }
    }
}

private struct HauteurBouton: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    EmptyScanView(onScan: {}, onImport: {})
}

#Preview("Scan en cours") {
    EmptyScanView(isScanning: true, onScan: {}, onImport: {})
}
