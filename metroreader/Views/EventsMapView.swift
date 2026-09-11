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
    let systemImage: String
    let eventTransition: String
}

struct EventsMapView: View {
    /// Tous les événements de la carte, du plus récent au plus ancien : ceux
    /// qui ne se placent pas disent encore si une entrée formait correspondance.
    let events: [[String: Any]]
    /// Combien, en tête, se placent sur la carte.
    let affiches: Int

    // Un arrêt identifié à la main entre dans la carte : le journal est observé
    // pour que la vue s'en aperçoive.
    @ObservedObject private var entries = ManualEntries.shared

    // Transformation des stations en annotations identifiables
    private var annotations: [EventAnnotation] {
        events.prefix(affiches).enumerated().compactMap { index, eventInfo in
            // Du plus récent au plus ancien : ce qui précède a suivi, ce qui
            // vient après a précédé.
            let event = ResolvedEvent(eventInfo,
                                      suivants: Array(events[..<index]),
                                      precedents: Array(events[(index + 1)...]))
            guard event.location.isLocatable else { return nil }

            return EventAnnotation(
                name: event.location.name,
                coordinate: CLLocationCoordinate2D(latitude: event.location.lat, longitude: event.location.lon),
                eventNumber: index + 1,
                systemImage: getTransitIcon(event.mode, event.transition),
                eventTransition: event.transition
            )
        }
    }

    var body: some View {
        let annotations = self.annotations
        Map {
            ForEach(annotations) { annotation in
                Marker(coordinate: annotation.coordinate) {
                    // Affiche le numéro de l'événement (1 étant le plus récent)
                    Label(annotation.name, systemImage: annotation.systemImage)
                }
                .tint(TransitionKind(annotation.eventTransition).color)
            }
            
            MapPolyline(coordinates: annotations.map { $0.coordinate })
                .stroke(.blue.opacity(0.5), lineWidth: 3)
        }
        .mapStyle(.standard(emphasis: .muted))
        .frame(height: 300)
        // Le cadrage automatique est choisi à la création : un arrêt identifié
        // en cours de route agrandit la carte, il faut la refaire naître.
        .id(annotations.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }.joined(separator: "|"))
    }
}
