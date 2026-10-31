//
//  EcranDeplie.swift
//  metroreader
//

import SwiftUI


extension EnvironmentValues {
    /// Vrai sur l'iPhone Duo déplié : l'app tient en deux panneaux, le scan à
    /// gauche, sous l'antenne NFC, et l'historique à droite.
    @Entry var ecranDeplie: Bool = false

    /// L'angle dont tourner les boutons pour qu'ils restent droits quand on
    /// tourne le Duo. Nul ailleurs : un iPhone ordinaire reste en portrait.
    @Entry var angleDesBoutons: Angle = .zero

    /// Vrai dans le cadre tourné du Duo plié tenu en paysage : la page dispose
    /// de la largeur, et peut se mettre en colonnes.
    @Entry var paysagePlie: Bool = false
}


/// L'iPhone Duo, plié ou déplié.
enum Duo {
    /// L'identifiant du modèle ; au simulateur, celui de l'appareil simulé.
    static let estUnDuo: Bool = {
        #if targetEnvironment(simulator)
        let modele = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var systeme = utsname()
        uname(&systeme)
        let modele = withUnsafeBytes(of: &systeme.machine) { octets in
            String(decoding: octets.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
        return modele == "iPhone19,4"
    }()
}


#if os(iOS)
/// L'orientation dans laquelle on tient le Duo.
///
/// L'app ne tourne pas : l'antenne NFC est sous les boutons de volume, à une
/// place fixe, et la cible reste dessus quoi qu'on fasse du téléphone. Seuls
/// les boutons pivotent, pour se lire droits. À plat sur une table, on garde
/// le dernier angle plutôt que de revenir au portrait.
@MainActor
final class OrientationDuDuo: ObservableObject {
    static let shared = OrientationDuDuo()

    /// L'orientation de l'appareil, en angle depuis le portrait de l'écran
    /// extérieur.
    @Published private(set) var angleDeLAppareil: Angle = .zero

    /// L'angle dont tourner les boutons sur l'écran en usage : ce dont
    /// l'appareil a tourné, moins ce dont le système a déjà tourné l'interface.
    /// L'écran intérieur est posé d'un quart de tour par rapport à l'extérieur :
    /// déplié et tenu droit, l'appareil se dit en paysage, interface en portrait.
    func angle(deplie: Bool) -> Angle {
        let degres = angleDeLAppareil.degrees - Ecran.angleDeLInterface - (deplie ? 90 : 0)
        // Ramené entre -180 et 180, pour que le bouton tourne par le plus court.
        let ramene = (degres + 540).truncatingRemainder(dividingBy: 360) - 180
        return .degrees(ramene == -180 ? 180 : ramene)
    }

    private init() {
        guard Duo.estUnDuo else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relire() }
        }
        relire()
    }

    private func relire() {
        let nouvel: Angle
        switch UIDevice.current.orientation {
        case .portrait:           nouvel = .zero
        case .landscapeLeft:      nouvel = .degrees(90)
        case .landscapeRight:     nouvel = .degrees(-90)
        case .portraitUpsideDown: nouvel = .degrees(180)
        default:                  return
        }
        withAnimation(.snappy(duration: 0.35)) { angleDeLAppareil = nouvel }
    }
}
#endif


#if os(iOS)
/// L'écran où l'app s'affiche, et ce qu'il dit de l'antenne.
enum Ecran {
    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// L'orientation de l'interface, dans la convention des angles de
    /// l'appareil — un paysage « gauche » de l'interface est un paysage
    /// « droite » de l'appareil.
    static var angleDeLInterface: Double {
        switch scene?.effectiveGeometry.interfaceOrientation {
        case .portraitUpsideDown: return 180
        case .landscapeLeft:      return -90
        case .landscapeRight:     return 90
        default:                  return 0
        }
    }

    /// L'antenne NFC du Duo déplié, sous les boutons de volume. Elle ne bouge
    /// pas sur l'appareil, mais le système tourne l'interface : on la fixe donc
    /// dans le repère de l'écran, où elle tient contre le bord gauche à 190 pt
    /// du haut, et on la ramène dans l'orientation du moment. Relevé sur
    /// l'habillage du simulateur — la charnière coupe l'écran à mi-hauteur, les
    /// boutons sont à 285 pt d'elle.
    static var antenneDuDuoDeplie: CGPoint {
        let fixe = CGPoint(x: 0, y: 190)
        guard let ecran = scene?.screen else { return fixe }
        return ecran.coordinateSpace.convert(fixe, from: ecran.fixedCoordinateSpace)
    }

    /// La taille de l'écran dans l'orientation du moment.
    static var taille: CGSize { scene?.screen.bounds.size ?? .zero }
}
#endif


extension View {
    /// Fait pivoter un bouton ou une icône pour qu'il reste droit sur le Duo.
    func droitSurLeDuo() -> some View {
        modifier(DroitSurLeDuo())
    }
}

private struct DroitSurLeDuo: ViewModifier {
    @Environment(\.angleDesBoutons) private var angle

    func body(content: Content) -> some View {
        content.rotationEffect(angle)
    }
}


#if os(iOS)
/// Ce que la barre du Duo demande, et ce que la fiche affichée lui propose.
///
/// Les boutons quittent les barres des pages pour une barre à eux, sous la
/// caméra. Leurs actions restent pourtant là où vivent leurs états : l'import
/// dans la page de scan, le renommage et l'image dans la fiche. La barre lève
/// une demande, la vue concernée y répond et la baisse.
@MainActor
final class ActionsDuDuo: ObservableObject {
    static let shared = ActionsDuDuo()

    @Published var importer = false
    @Published var reglages = false
    @Published var renommer = false
    @Published var changerImage = false
    /// La reconstitution des voyages tient le panneau de gauche : le retour à
    /// la fiche prend la place du bouton Modifier.
    @Published var retourPossible = false
    @Published var retour = false

    /// Une carte est affichée : la seconde bulle a lieu d'être.
    @Published var carteAffichee = false
    /// La carte est dans l'historique : on peut la renommer et l'habiller.
    @Published var peutPersonnaliser = false
    /// Ce qu'exporter la carte affichée partagerait.
    @Published var export: ExportFile?
    @Published var titreExport = ""

    private init() {}
}


/// La barre du Duo, sous la caméra : deux bulles, l'une pour lire une carte —
/// importer, relancer le scan, les Réglages —, l'autre pour la carte affichée.
struct BarreDuDuo: View {
    @ObservedObject var actions = ActionsDuDuo.shared
    /// Plié, la barre d'onglets du système fait déjà scanner et les Réglages :
    /// la bulle de lecture y ferait double emploi.
    var avecLecture = true
    let scanner: () -> Void
    let ouvrirReglages: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if avecLecture {
                bulle {
                    bouton("Importer", "square.and.arrow.down") { actions.importer = true }
                    bouton("Scanner", "wave.3.forward", action: scanner)
                    bouton("Réglages", "gearshape", action: ouvrirReglages)
                }
            }

            // Les voyages remplacent la fiche, qui en disparaissant se dit
            // fermée : la bulle reste tant qu'il y a un retour à faire.
            if actions.carteAffichee || actions.retourPossible {
                bulle {
                    if actions.retourPossible {
                        bouton("Retour à la fiche", "chevron.left") { actions.retour = true }
                    } else if actions.peutPersonnaliser {
                        Menu {
                            Button { actions.renommer = true } label: {
                                Label("Renommer le pass", systemImage: "pencil")
                            }
                            Button { actions.changerImage = true } label: {
                                Label("Changer l'image", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            icone("square.and.pencil")
                        }
                        .accessibilityLabel("Modifier le pass")
                    }
                    if let export = actions.export {
                        ShareLink(item: export, preview: SharePreview(actions.titreExport)) {
                            icone("square.and.arrow.up")
                        }
                        .accessibilityLabel("Exporter")
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: actions.carteAffichee || actions.retourPossible)
    }

    private func bulle<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(spacing: 4) { contenu() }
            .padding(6)
            .modifier(VerreDeLaBulle())
    }

    private func bouton(_ titre: String, _ symbole: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icone(symbole) }
            .accessibilityLabel(titre)
    }

    private func icone(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .droitSurLeDuo()
    }
}

/// Le verre liquide d'iOS 26, le matériau translucide avant.
private struct VerreDeLaBulle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
#endif


#if os(iOS)
/// Le Duo plié tenu en paysage. L'écran ne tourne pas — l'antenne est à une
/// place fixe et la cible avec elle —, mais une page qu'on lit se présente
/// droite : elle est mise en page aux dimensions du paysage, dans la zone sûre,
/// puis tournée d'un quart.
struct PaysageSurLeDuoPlie: ViewModifier {
    /// Faux pour l'écran de scan vide : seuls ses boutons y pivotent.
    var actif = true
    /// L'angle, quand l'environnement ne le porte plus : une page présentée en
    /// plein écran depuis le cadre tourné y reçoit un angle nul.
    var angleImpose: Angle? = nil
    @Environment(\.angleDesBoutons) private var angleDuMilieu
    @Environment(\.ecranDeplie) private var deplie

    private var angle: Angle { angleImpose ?? angleDuMilieu }

    private var couche: Bool {
        Duo.estUnDuo && actif && !deplie && abs(angle.degrees) == 90
    }

    func body(content: Content) -> some View {
        if couche {
            // Tout l'écran, et non la zone que la barre d'onglets laisse à la
            // page : plus étroite et décalée de 84 pt sous le haut, elle
            // laissait une bande vide côté caméra une fois tournée. Le cadre
            // prend la taille de l'écran et se centre sur lui, où que la zone
            // commence.
            GeometryReader { zone in
                let ecran = Ecran.taille == .zero ? zone.size : Ecran.taille
                let origine = zone.frame(in: .global).origin
                content
                    // Les zones sûres se calculent avant la rotation : celle de
                    // la barre d'onglets, à droite du portrait, retombait sur
                    // le bord du cadre côté caméra et y laissait une marge vide.
                    .ignoresSafeArea()
                    .environment(\.paysagePlie, true)
                    // Tout est déjà droit : rien n'y pivote plus.
                    .environment(\.angleDesBoutons, .zero)
                    // La largeur d'un paysage se lit mieux en texte plus serré.
                    .dynamicTypeSize(...DynamicTypeSize.xSmall)
                    .frame(width: ecran.height, height: ecran.width)
                    .rotationEffect(angle)
                    .position(x: ecran.width / 2 - origine.x, y: ecran.height / 2 - origine.y)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}
#endif


extension View {
    /// Dans le cadre tourné du Duo plié, une page poussée par la navigation
    /// reçoit des marges de sécurité calculées avant la rotation, qui tombent
    /// du mauvais côté : elle les ignore.
    func pleinCadreSurLeDuo() -> some View {
        modifier(PleinCadreSurLeDuo())
    }
}

private struct PleinCadreSurLeDuo: ViewModifier {
    @Environment(\.paysagePlie) private var paysagePlie

    func body(content: Content) -> some View {
        if paysagePlie {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}
