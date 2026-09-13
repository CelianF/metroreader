//
//  EventsMapView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 03/01/2026.
//


import SwiftUI
import MapKit


struct EventAnnotation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// Le pictogramme IDFM du mode, rien quand le mode n'en a pas.
    let pictogramme: String?
    let eventTransition: String
    /// Combien de validations ce repère porte, une fois ceux d'un même arrêt
    /// regroupés.
    var poids = 1
}

extension Array where Element == EventAnnotation {
    /// Un repère par endroit. Des entrées et des sorties en boucle au même
    /// portique empilaient autant de pastilles au même point : on ne voyait
    /// que celle du dessus, et chacune coûtait sa vue. Le mode n'y change
    /// rien : le carré d'un RER dépassait derrière le rond du métro posé au
    /// même point. Reste la validation la plus récente, qui porte le compte des
    /// autres. Rendus du plus ancien au plus récent : le plus récent est
    /// dessiné par-dessus.
    func uneParArret() -> [EventAnnotation] {
        var rangs: [String: Int] = [:]
        var uniques: [EventAnnotation] = []
        for annotation in self {
            let cle = "\((annotation.coordinate.latitude * 1e5).rounded())|\((annotation.coordinate.longitude * 1e5).rounded())"
            if let rang = rangs[cle] {
                uniques[rang].poids += 1
            } else {
                rangs[cle] = uniques.count
                uniques.append(annotation)
            }
        }
        return uniques.reversed()
    }

    /// Le tracé, sans les allers-retours sur place : deux validations de suite
    /// au même endroit n'y ajoutent rien.
    func trace() -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        for annotation in self {
            if let dernier = points.last,
               dernier.latitude == annotation.coordinate.latitude,
               dernier.longitude == annotation.coordinate.longitude { continue }
            points.append(annotation.coordinate)
        }
        return points
    }

    /// Les repères dont les pastilles se recouvrent à l'écran n'en font qu'un :
    /// celui du dessus — le dernier de la liste —, qui prend le poids des
    /// autres. Deux stations voisines laissaient dépasser un bout de pastille
    /// derrière l'autre, trop peu pour se lire. Un repère sans point à l'écran
    /// reste tel quel.
    func sansChevauchement(cote: CGFloat, point: (EventAnnotation) -> CGPoint?) -> [EventAnnotation] {
        var gardes: [(annotation: EventAnnotation, point: CGPoint?)] = []
        for annotation in reversed() {
            let ici = point(annotation)
            if let ici, let rang = gardes.firstIndex(where: {
                guard let la = $0.point else { return false }
                return abs(la.x - ici.x) < cote && abs(la.y - ici.y) < cote
            }) {
                gardes[rang].annotation.poids += annotation.poids
            } else {
                gardes.append((annotation, ici))
            }
        }
        return gardes.reversed().map(\.annotation)
    }
}

struct EventsMapView: View {
    /// Tous les événements de la carte, du plus récent au plus ancien : ceux
    /// qui ne se placent pas disent encore si une entrée formait correspondance.
    let events: [[String: Any]]
    /// Combien, en tête, se placent sur la carte.
    let affiches: Int
    /// Les titres de la carte, pour les correspondances sous forfait.
    let contrats: [[String: Any]]
    /// Rien pour occuper toute la place, en plein écran.
    var hauteur: CGFloat? = 300

    // Un arrêt identifié à la main entre dans la carte : le journal est observé
    // pour que la vue s'en aperçoive.
    @ObservedObject private var entries = ManualEntries.shared

    /// Les repères affichés, un par arrêt, et le tracé. Ils restent en place
    /// pendant qu'un nouveau calcul tourne, et la carte ne renaît plus pour se
    /// recadrer : le cadrage se règle à part.
    @State private var annotations: [EventAnnotation] = []
    @State private var trace: [CLLocationCoordinate2D] = []
    /// Un repère par endroit, avant qu'ils se fondent selon le cadrage.
    @State private var parEndroit: [EventAnnotation] = []
    /// La taille de la carte à l'écran, pour placer les repères sur le cadrage.
    @State private var taille: CGSize = .zero
    @State private var enCalcul = true
    @State private var position: MapCameraPosition = .automatic

    /// Ce qui oblige à recalculer les repères : combien s'affichent, et le
    /// journal des saisies, qui peut nommer un arrêt resté inconnu. Le journal
    /// compte par révision et non par nombre de saisies : renommer un arrêt, ou
    /// en identifier un de nouveau, n'en change pas le nombre, et la carte
    /// gardait l'ancien nom.
    private var cle: String {
        "\(affiches)|\(events.count)|\(entries.revision)"
    }

    var body: some View {
        Map(position: $position) {
            // Les pastilles de l'aperçu, plutôt que les bulles de Plans.
            ForEach(annotations) { annotation in
                Annotation(annotation.name, coordinate: annotation.coordinate, anchor: .center) {
                    PastilleDeRepere(pictogramme: annotation.pictogramme, transition: annotation.eventTransition,
                                     poids: annotation.poids)
                }
            }

            MapPolyline(coordinates: trace)
                .stroke(.blue.opacity(0.5), lineWidth: 3)
        }
        .mapStyle(.standard(emphasis: .muted))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { taille = $0 }
        // Au bout de chaque déplacement, les pastilles qui se recouvrent se
        // fondent : de loin, une station voisine ne dépasse plus derrière une
        // autre ; de près, elles se séparent. Les points se déduisent du cadrage
        // lui-même : la conversion de `MapReader` n'en rendait aucun.
        .onMapCameraChange(frequency: .onEnd) { contexte in
            let cadre = contexte.rect
            let ecran = taille
            annotations = parEndroit.sansChevauchement(cote: PastilleDeRepere.cote) { annotation in
                guard cadre.width > 0, cadre.height > 0, ecran.width > 0 else { return nil }
                let point = MKMapPoint(annotation.coordinate)
                return CGPoint(x: (point.x - cadre.minX) / cadre.width * ecran.width,
                               y: (point.y - cadre.minY) / cadre.height * ecran.height)
            }
        }
        .overlay {
            if enCalcul {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(height: hauteur)
        .task(id: cle) {
            enCalcul = true
            let calcules = await Self.reperes(events: events, affiches: affiches, contrats: contrats)
            guard !Task.isCancelled else { return }
            parEndroit = calcules.uneParArret()
            annotations = parEndroit
            trace = calcules.trace()
            position = Self.cadrage(calcules)
            enCalcul = false
        }
    }

    /// Le cadrage qui montre tous les repères, avec de la marge autour.
    private static func cadrage(_ annotations: [EventAnnotation]) -> MapCameraPosition {
        guard let cadre = Self.region(annotations) else { return .automatic }
        return .region(cadre)
    }

    /// La région qui montre tous les repères, avec de la marge autour ; rien
    /// sans repère. L'aperçu de la liste se cadre sur la même.
    nonisolated static func region(_ annotations: [EventAnnotation]) -> MKCoordinateRegion? {
        guard let premier = annotations.first else { return nil }
        var sud = premier.coordinate.latitude, nord = sud
        var ouest = premier.coordinate.longitude, est = ouest
        for annotation in annotations {
            sud = min(sud, annotation.coordinate.latitude)
            nord = max(nord, annotation.coordinate.latitude)
            ouest = min(ouest, annotation.coordinate.longitude)
            est = max(est, annotation.coordinate.longitude)
        }
        let centre = CLLocationCoordinate2D(latitude: (sud + nord) / 2, longitude: (ouest + est) / 2)
        let etendue = MKCoordinateSpan(latitudeDelta: max((nord - sud) * 1.4, 0.01),
                                       longitudeDelta: max((est - ouest) * 1.4, 0.01))
        return MKCoordinateRegion(center: centre, span: etendue)
    }

    /// Les repères des `affiches` premières validations, hors du fil principal.
    nonisolated static func reperes(events: [[String: Any]], affiches: Int,
                                    contrats: [[String: Any]]) async -> [EventAnnotation] {
        var reperes: [EventAnnotation] = []
        let validations = Validations(events, contrats: contrats)
        for (index, eventInfo) in events.prefix(affiches).enumerated() {
            if Task.isCancelled { break }
            let event = ResolvedEvent(eventInfo, transition: validations.transition(de: index))
            guard event.location.isLocatable else { continue }
            reperes.append(EventAnnotation(
                name: event.location.name,
                coordinate: CLLocationCoordinate2D(latitude: event.location.lat, longitude: event.location.lon),
                pictogramme: pictogrammeIDFM(modeDuPictogramme(mode: event.mode, transition: event.transition)),
                eventTransition: event.transition
            ))
        }
        return reperes
    }
}
