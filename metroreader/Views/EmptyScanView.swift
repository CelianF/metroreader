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

    /// Écran figé quand l'iPhone demande de réduire les animations
    /// (Accessibilité › Mouvement) : la cible se tient d'emblée à sa place
    /// haute, sans monter, sans battre, et sans carte qui défile. Rien ne bouge.
    @Environment(\.accessibilityReduceMotion) private var sansAnimation

    /// Le Duo déplié : la cible tient le panneau de droite, là où est l'antenne.
    @Environment(\.ecranDeplie) private var deplie

    /// Tourné d'un quart sur le Duo, le libellé du bouton ne tient plus en
    /// largeur : il cède la place à son pictogramme.
    @Environment(\.angleDesBoutons) private var angleDesBoutons

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

    /// Tiré au sort à chaque tour : le bord d'où la carte entre, son
    /// inclinaison en arrivant, celle qu'elle garde une fois posée. Deux
    /// passages ne se ressemblent donc jamais tout à fait.
    @State private var entree = Entree.droite
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
    /// Ce qu'elle mesure au moins, celle d'un iPhone ordinaire.
    private static let largeurCarteMinimale: CGFloat = 220

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

    /// Le bord d'où la carte entre.
    private enum Entree { case gauche, droite }

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
            // L'antenne dans la moitié basse — le Duo déplié tourné : la cible
            // passe sous les boutons, sans quoi elle descendait se poser dessus.
            if couche {
                cible
                zoneCouchee
            } else if cibleEnBas {
                titre
                actions
                cible
            } else {
                cible
                titre
                actions
            }
        }
        .background(mesureColonne)
        .padding(.horizontal, 32)
        .padding(cibleEnBas ? .bottom : .top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cibleEnBas ? .bottom : .top)
        // Une passe de mise en page qui sonde la vue remonte parfois une colonne
        // étroite, centrée hors de l'écran ; sur le Duo tourné, c'était elle
        // qu'on gardait, et la cible partait se perdre. Une mesure ne vaut que
        // si son centre tombe dans l'écran.
        .onPreferenceChange(CibleKey.self) { nouvelle in
            if nouvelle.centre > 0 && nouvelle.milieu > 0 { mesure = nouvelle }
        }
    }

    private var titre: some View {
        Text(isScanning ? "Collez la carte sur la cible" : "Aucun Navigo scanné")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    /// Le Duo plié tenu en paysage : l'écran ne tourne pas, la cible reste sur
    /// l'antenne, mais le titre et les boutons pivotent d'un bloc pour se lire
    /// droits.
    private var couche: Bool {
        !deplie && abs(angleDesBoutons.degrees) == 90
    }

    /// Le titre et les boutons, tournés d'un quart, au milieu de la place que
    /// la cible laisse libre. Le bloc reçoit la hauteur de la zone pour
    /// largeur, puis pivote : une fois tourné, il la remplit exactement. Rien
    /// n'y pivote plus de son côté, et le bouton garde son libellé.
    private var zoneCouchee: some View {
        GeometryReader { zone in
            VStack(spacing: 20) {
                titre
                actions
            }
            .environment(\.angleDesBoutons, .zero)
            .frame(width: zone.size.height, height: zone.size.width)
            .rotationEffect(angleDesBoutons)
            .frame(width: zone.size.width, height: zone.size.height)
        }
    }

    /// La cible se range au bas de la colonne quand l'antenne est dans la
    /// moitié basse de l'écran.
    private var cibleEnBas: Bool {
        #if os(iOS)
        deplie && Ecran.antenneDuDuoDeplie.y > Ecran.taille.height / 2
        #else
        false
        #endif
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
        .task(id: defileExemples) { await defilerExemples() }
        .onChange(of: isTagDetected) { _, detectee in
            if detectee { dernierTour = true }
        }
    }

    /// Les exemples ne traversent l'écran que pendant une lecture, et
    /// seulement si l'animation est permise.
    private var defileExemples: Bool { isScanning && !sansAnimation }

    private var dessinCible: some View {
        Image("Cible")
            .resizable()
            .scaledToFit()
            // Pleine largeur, bornée pour ne pas devenir démesurée sur iPad
            .frame(maxWidth: Self.coteCible)
            // Pendant la lecture, la cible bat entre demi-opacité et pleine.
            // L'animation est choisie ici plutôt qu'au moment de la
            // mutation : à l'arrêt, c'est le fondu court qui reprend la
            // main, là où un withAnimation laissait la boucle courir. Elle ne
            // couvre que l'opacité : sur le Duo, déplier pendant la lecture
            // redimensionne le panneau, et une boucle infinie posée sur toute
            // la vue happait ce changement — la cible faisait sans fin la
            // navette entre son ancienne taille et la nouvelle.
            .animation(animationPulse) { $0.opacity(pulse ? 0.5 : 1.0) }
            // Un décalage plutôt qu'une mise en page, pour que le reste de
            // l'écran ne bouge pas avec elle. L'animation suit le décalage
            // lui-même et non isScanning : quand la lecture repart depuis une
            // carte affichée, l'écran vide naît alors qu'elle a déjà commencé
            // et isScanning ne change plus. Elle reste attachée à la valeur, et
            // non limitée au seul décalage comme le battement : sous cette
            // forme, la montée ne jouait plus, la cible sautait d'un coup.
            .offset(decalage)
            .animation(sansAnimation ? nil : .snappy(duration: 0.4), value: decalage)
            .onChange(of: isScanning) { _, enCours in pulse = enCours && !sansAnimation }
            .onChange(of: sansAnimation) { _, fige in if fige { pulse = false } }
            .onAppear { pulse = isScanning && !sansAnimation }
    }

    /// Le battement de la cible. Nul quand l'écran est figé : sans animation à
    /// relayer, `pulse` reste faux et la cible garde son opacité pleine.
    private var animationPulse: Animation? {
        guard !sansAnimation else { return nil }
        return isScanning
            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
            : .easeInOut(duration: 0.35)
    }

    // MARK: - Carte d'exemple

    /// Un passe tiré au sort, qui traverse l'écran pendant la lecture pour
    /// montrer le geste. Sa taille est fixée une fois pour toutes et c'est
    /// `scaleEffect` qui la fait rapetisser : une transformation s'anime sans
    /// relayouter, là où une largeur qui change ferait tressauter le dessin.
    @ViewBuilder
    private var carteExemple: some View {
        if let exemple, mesure.cote > 0 {
            // Dans le demi-panneau du Duo déplié, 55 % de la cible ne faisait
            // plus qu'une vignette : la carte garde la taille qu'elle a sur un
            // iPhone, sans déborder de la cible.
            let largeur = min(max(mesure.cote * Self.largeurCarte, Self.largeurCarteMinimale),
                              mesure.cote * 0.9)
            NavigoImage(imageName: exemple)
                .frame(width: largeur, height: largeur / Self.formatCarte)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
                // Plié couché, la carte suit le titre et les boutons : elle se
                // présente droite pour qui tient le téléphone en paysage.
                .rotationEffect(.degrees(angleCarte) + (couche ? angleDesBoutons : .zero))
                .scaleEffect(echelleCarte)
                .offset(decalageCarte)
                .transition(.opacity)
        }
    }

    /// Où se trouve la carte, en écart depuis le centre de l'emplacement de la
    /// cible. Le pas « posée » vise `decalage` : c'est de là que la cible s'est
    /// déplacée, la carte tombe donc pile sur son centre — un peu en retrait du
    /// bord où elle s'est collée, pour rester entière à l'écran.
    private var decalageCarte: CGSize {
        let cote = mesure.cote
        switch etape {
        case .cachee:
            return CGSize(width: (entree == .gauche ? -1 : 1) * cote * 1.3, height: cote * 0.30)
        case .sousCible:
            return CGSize(width: 0, height: cote * 0.30)
        case .posee:
            return CGSize(width: decalage.width - versLAntenne.width * cote * Self.poseSousCentre,
                          height: decalage.height - versLAntenne.height * cote * Self.poseSousCentre)
        case .sortie:
            // Assez loin pour sortir entièrement du cadre, par le bord de
            // l'antenne : la carte s'en va en bougeant, elle ne s'efface pas
            // sur place.
            return CGSize(width: decalage.width + versLAntenne.width * cote * 1.3,
                          height: decalage.height + versLAntenne.height * cote * 1.3)
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
        guard defileExemples else {
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
            entree = bordDEntree
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

    /// Le bord d'où entrent les cartes. Sur l'iPhone, l'un ou l'autre, au sort.
    /// Sur le Duo déplié, la gauche et elle seule : c'est le bord du panneau de
    /// scan, sous l'antenne, et la droite traverserait l'historique.
    private var bordDEntree: Entree {
        #if os(iOS)
        if deplie {
            // Le côté de l'antenne : le bord où elle tient, ou, collée en haut
            // ou en bas, la moitié de l'écran où elle se trouve.
            if versLAntenne.width != 0 { return versLAntenne.width < 0 ? .gauche : .droite }
            return Ecran.antenneDuDuoDeplie.x < Ecran.taille.width / 2 ? .gauche : .droite
        }
        #endif
        return Bool.random() ? .gauche : .droite
    }

    /// La colonne ne bouge pas quand son contenu se décale : c'est le seul
    /// repère sûr. La cible en occupe le haut, ou le bas quand elle passe sous
    /// les boutons, et son côté vaut la largeur disponible tant qu'elle n'est
    /// pas coiffée — d'où son centre.
    private var mesureColonne: some View {
        GeometryReader { proxy in
            let cote = min(proxy.size.width, Self.coteCible)
            Color.clear.preference(
                key: CibleKey.self,
                value: MesureCible(centre: cibleEnBas ? proxy.frame(in: .global).maxY - cote / 2
                                                      : proxy.frame(in: .global).minY + cote / 2,
                                   milieu: proxy.frame(in: .global).midX,
                                   cote: cote)
            )
        }
    }

    /// De combien déplacer la cible pour amener son centre sur l'antenne :
    /// l'île sur un iPhone, le bord gauche sur le Duo déplié. Écran figé, elle y
    /// est en permanence : c'est la même place, atteinte sans le glissement qui
    /// l'annonçait.
    private var decalage: CGSize {
        #if os(iOS)
        guard isScanning || sansAnimation, mesure.cote > 0 else { return .zero }
        if deplie {
            let antenne = Ecran.antenneDuDuoDeplie
            return CGSize(width: antenne.x - mesure.milieu, height: antenne.y - mesure.centre)
        }
        return CGSize(width: 0, height: centreIle - mesure.centre)
        #else
        return .zero
        #endif
    }

    /// Le sens dans lequel la cible part vers l'antenne : vers le haut sur un
    /// iPhone ; sur le Duo déplié, vers le bord où l'antenne tient dans
    /// l'orientation du moment.
    private var versLAntenne: CGSize {
        #if os(iOS)
        if deplie {
            let antenne = Ecran.antenneDuDuoDeplie
            let taille = Ecran.taille
            let ecarts: [(CGFloat, CGSize)] = [
                (antenne.x, CGSize(width: -1, height: 0)),
                (taille.width - antenne.x, CGSize(width: 1, height: 0)),
                (antenne.y, CGSize(width: 0, height: -1)),
                (taille.height - antenne.y, CGSize(width: 0, height: 1)),
            ]
            return ecarts.min { $0.0 < $1.0 }?.1 ?? CGSize(width: 0, height: -1)
        }
        #endif
        return CGSize(width: 0, height: -1)
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
            LibelleDuScan(enCours: isScanning)
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
                .droitSurLeDuo()
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
/// Le libellé du bouton de scan. Une vue à part pour lire l'angle là où elle
/// est posée : dans le bloc qui pivote d'une pièce sur le Duo plié couché,
/// l'angle y est remis à zéro et le libellé reste entier.
private struct LibelleDuScan: View {
    let enCours: Bool
    @Environment(\.angleDesBoutons) private var angle

    var body: some View {
        Group {
            // Tourné d'un quart, le libellé ne tient plus en largeur : il cède
            // la place à son pictogramme.
            if abs(angle.degrees) == 90 {
                Image(systemName: "wave.3.forward")
                    .accessibilityLabel(enCours ? "Scan en cours…" : "Scanner une carte")
            } else {
                Text(enCours ? "Scan en cours…" : "Scanner une carte")
            }
        }
        .font(.headline)
        .droitSurLeDuo()
    }
}

private struct MesureCible: Equatable {
    var centre: CGFloat = 0
    /// Le milieu horizontal de la colonne, où la cible est centrée.
    var milieu: CGFloat = 0
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
