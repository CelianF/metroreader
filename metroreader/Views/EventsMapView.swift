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
    let eventNumber: Int
    /// Le pictogramme IDFM du mode, rien quand le mode n'en a pas.
    let pictogramme: String?
    let eventTransition: String
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

    /// Les repères affichés. Ils restent en place pendant qu'un nouveau calcul
    /// tourne, et la carte ne renaît plus pour se recadrer : le cadrage se règle
    /// à part.
    @State private var annotations: [EventAnnotation] = []
    @State private var enCalcul = true
    @State private var position: MapCameraPosition = .automatic

    /// Ce qui oblige à recalculer les repères : combien s'affichent, et le
    /// journal des saisies, qui peut nommer un arrêt resté inconnu.
    private var cle: String {
        "\(affiches)|\(events.count)|\(entries.stops.count)|\(entries.lines.count)|\(entries.providers.count)"
    }

    var body: some View {
        Map(position: $position) {
            ForEach(annotations) { annotation in
                if let pictogramme = annotation.pictogramme {
                    Marker(annotation.name, image: pictogramme, coordinate: annotation.coordinate)
                        .tint(TransitionKind(annotation.eventTransition).color)
                } else {
                    Marker(annotation.name, systemImage: "questionmark", coordinate: annotation.coordinate)
                        .tint(TransitionKind(annotation.eventTransition).color)
                }
            }

            MapPolyline(coordinates: annotations.map { $0.coordinate })
                .stroke(.blue.opacity(0.5), lineWidth: 3)
        }
        .mapStyle(.standard(emphasis: .muted))
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
            annotations = calcules
            position = Self.cadrage(calcules)
            enCalcul = false
        }
    }

    /// Le cadrage qui montre tous les repères, avec de la marge autour.
    private static func cadrage(_ annotations: [EventAnnotation]) -> MapCameraPosition {
        guard let premier = annotations.first else { return .automatic }
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
        return .region(MKCoordinateRegion(center: centre, span: etendue))
    }

    /// Les repères des `affiches` premières validations, hors du fil principal.
    nonisolated private static func reperes(events: [[String: Any]], affiches: Int,
                                            contrats: [[String: Any]]) async -> [EventAnnotation] {
        var reperes: [EventAnnotation] = []
        for (index, eventInfo) in events.prefix(affiches).enumerated() {
            if Task.isCancelled { break }
            // Du plus récent au plus ancien : ce qui précède a suivi, ce qui
            // vient après a précédé.
            let event = ResolvedEvent(eventInfo,
                                      suivants: Array(events[..<index]),
                                      precedents: Array(events[(index + 1)...]),
                                      contrats: contrats)
            guard event.location.isLocatable else { continue }
            reperes.append(EventAnnotation(
                name: event.location.name,
                coordinate: CLLocationCoordinate2D(latitude: event.location.lat, longitude: event.location.lon),
                eventNumber: index + 1,
                pictogramme: pictogrammeIDFM(modeDuPictogramme(mode: event.mode, transition: event.transition)),
                eventTransition: event.transition
            ))
        }
        return reperes
    }
}
