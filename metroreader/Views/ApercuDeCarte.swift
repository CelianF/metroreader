//
//  ApercuDeCarte.swift
//  metroreader
//

import SwiftUI
import MapKit


/// La carte des validations, en image, pour la liste.
///
/// Une `Map` se bâtit sur le fil principal : le temps qu'elle s'installe, la
/// page ne défilait plus. Dans la liste, la carte ne se manipule pas — la
/// toucher l'ouvre en grand —, alors elle y est dessinée hors du fil principal
/// par `MKMapSnapshotter`, et ses repères sont posés par-dessus, sans leurs
/// noms : ils sont sur la carte en grand. L'image porte d'elle-même le logo de
/// Plans ; les mentions légales sont sur la carte en grand.
struct ApercuDeCarte: View {
    /// Tous les événements de la carte, du plus récent au plus ancien.
    let events: [[String: Any]]
    /// Combien, en tête, se placent sur la carte.
    let affiches: Int
    /// Les titres de la carte, pour les correspondances sous forfait.
    let contrats: [[String: Any]]

    static let hauteur: CGFloat = 300

    // Un arrêt identifié à la main entre dans la carte : le journal est observé
    // pour que la vue s'en aperçoive.
    @ObservedObject private var entries = ManualEntries.shared
    @Environment(\.colorScheme) private var apparence
    @Environment(\.displayScale) private var echelle

    /// Les repères, et la clé pour laquelle ils ont été calculés.
    @State private var reperes: (cle: String, liste: [EventAnnotation])?
    @State private var largeur: CGFloat = 0
    @State private var photo: Photo?
    @State private var enCalcul = true

    /// `reperesInitiaux` : des repères déjà calculés, qui n'ont plus qu'à être
    /// photographiés.
    init(events: [[String: Any]], affiches: Int, contrats: [[String: Any]],
         reperesInitiaux: [EventAnnotation]? = nil) {
        self.events = events
        self.affiches = affiches
        self.contrats = contrats
        _reperes = State(initialValue: reperesInitiaux.map {
            (cle: Self.cleDesReperes(affiches: affiches, events: events), liste: $0)
        })
    }

    /// L'image et ce qu'on pose dessus, calculés ensemble : ils ne peuvent pas
    /// se décaler.
    private struct Photo {
        let image: Image
        let trace: [CGPoint]
        let pastilles: [PastilleSurPhoto]
    }

    private struct PastilleSurPhoto: Identifiable {
        var annotation: EventAnnotation
        let point: CGPoint
        var id: UUID { annotation.id }
    }

    /// Ce qui oblige à recalculer les repères : combien s'affichent, et le
    /// journal des saisies, qui peut nommer un arrêt resté inconnu.
    private static func cleDesReperes(affiches: Int, events: [[String: Any]]) -> String {
        "\(affiches)|\(events.count)|\(ManualEntries.shared.revision)"
    }

    var body: some View {
        // Une autre largeur ou une autre apparence demandent une autre photo.
        let cle = "\(Self.cleDesReperes(affiches: affiches, events: events))|\(largeur)|\(apparence == .dark)"
        ZStack {
            if let photo {
                photo.image
                    .overlay(alignment: .topLeading) { calque(photo) }
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.hauteur)
        .clipped()
        .overlay {
            if enCalcul {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        // Arrondie au point : une largeur qui ne bouge que d'une fraction ne
        // relance pas une photo.
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { largeur = $0 }
        // La largeur et l'apparence de la clé, figées à sa création : lues au
        // moment où la tâche s'exécute, celle d'avant la mesure prenait déjà la
        // largeur mesurée, et deux photos partaient ensemble.
        .task(id: cle) { [largeur, apparence] in
            await photographier(largeur: largeur, sombre: apparence == .dark)
        }
    }

    /// Le tracé et les pastilles, posés aux points que la photo leur donne.
    private func calque(_ photo: Photo) -> some View {
        ZStack(alignment: .topLeading) {
            Path { chemin in
                guard let premier = photo.trace.first else { return }
                chemin.move(to: premier)
                for point in photo.trace.dropFirst() {
                    chemin.addLine(to: point)
                }
            }
            .stroke(.blue.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            ForEach(photo.pastilles) { pastille in
                PastilleDeRepere(pictogramme: pastille.annotation.pictogramme,
                                 transition: pastille.annotation.eventTransition,
                                 poids: pastille.annotation.poids)
                    .position(pastille.point)
            }
        }
    }

    private func photographier(largeur: CGFloat, sombre: Bool) async {
        guard largeur > 0 else { return }
        enCalcul = true
        let cleReperes = Self.cleDesReperes(affiches: affiches, events: events)
        let liste: [EventAnnotation]
        if let reperes, reperes.cle == cleReperes {
            liste = reperes.liste
        } else {
            liste = await EventsMapView.reperes(events: events, affiches: affiches, contrats: contrats)
            guard !Task.isCancelled else { return }
            reperes = (cle: cleReperes, liste: liste)
        }
        let nouvelle = await Self.photo(de: liste, taille: CGSize(width: largeur, height: Self.hauteur),
                                        sombre: sombre, echelle: echelle)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { photo = nouvelle }
        enCalcul = false
    }

    /// La carte cadrée sur les repères, dessinée hors du fil principal.
    nonisolated private static func photo(de reperes: [EventAnnotation], taille: CGSize,
                                          sombre: Bool, echelle: CGFloat) async -> Photo? {
        guard let region = EventsMapView.region(reperes) else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = taille
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        #if os(iOS)
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = sombre ? .dark : .light
            traits.displayScale = echelle
        }
        #else
        options.appearance = NSAppearance(named: sombre ? .darkAqua : .aqua)
        #endif

        let snapshotter = MKMapSnapshotter(options: options)
        let cliche: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { suite in
            snapshotter.start(with: .global(qos: .userInitiated)) { cliche, _ in
                suite.resume(returning: cliche)
            }
        }
        guard let cliche else { return nil }
        #if os(iOS)
        let image = Image(uiImage: cliche.image)
        #else
        let image = Image(nsImage: cliche.image)
        #endif
        let pastilles = reperes.uneParArret()
            .sansChevauchement(cote: PastilleDeRepere.cote) { cliche.point(for: $0.coordinate) }
        return Photo(
            image: image,
            trace: reperes.trace().map { cliche.point(for: $0) },
            pastilles: pastilles.map { PastilleSurPhoto(annotation: $0, point: cliche.point(for: $0.coordinate)) }
        )
    }
}


/// La pastille d'un repère : le pictogramme IDFM du mode, en blanc, son fond
/// rempli de la couleur de la transition. Le fond épouse la forme du
/// pictogramme — rond pour le métro, carré pour le reste —, sans cadre autour ;
/// la même pastille sur l'aperçu et sur la carte en grand.
struct PastilleDeRepere: View {
    let pictogramme: String?
    let transition: String
    /// Combien de validations la pastille porte : son ombre s'épaissit avec.
    var poids: Int = 1

    nonisolated static let cote: CGFloat = 18

    /// Le fond, pris sur le dessin des SVG IDFM, 283,46 de côté : l'anneau du
    /// métro touche leurs bords ; le train et le RER sont un carré aux coins de
    /// 63,78, et le funiculaire aussi, à l'échelle près ; le bus, le tram, le
    /// câble, la navette et le Noctilien, deux barres aux bouts arrondis de 9,21.
    private var fond: AnyShape {
        switch pictogramme {
        case "mode_metro":
            return AnyShape(Circle())
        case "mode_train", "mode_rer", "mode_train_rer", "mode_funiculaire":
            return AnyShape(RoundedRectangle(cornerRadius: Self.cote * 63.78 / 283.46))
        default:
            return AnyShape(RoundedRectangle(cornerRadius: Self.cote * 9.21 / 283.46))
        }
    }

    var body: some View {
        // Au-delà de six validations, l'ombre ne dit plus rien de plus.
        let surplus = CGFloat(min(poids, 6) - 1)
        ZStack {
            fond
                .fill(TransitionKind(transition).color)
            if let pictogramme {
                Image(pictogramme)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: Self.cote, height: Self.cote)
        // Une ombre pour la pastille entière, et non une par couche.
        .compositingGroup()
        .shadow(color: .black.opacity(0.3 + 0.07 * surplus), radius: 1.5 + 0.7 * surplus, y: 1 + 0.4 * surplus)
    }
}
