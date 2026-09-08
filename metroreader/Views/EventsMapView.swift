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
    // Liste dynamique des stations trouvées
    let events: [[String: Any]]

    // Un arrêt identifié à la main entre dans la carte : le journal est observé
    // pour que la vue s'en aperçoive.
    @ObservedObject private var entries = ManualEntries.shared

    // Transformation des stations en annotations identifiables
    private var annotations: [EventAnnotation] {
        events.enumerated().compactMap { index, eventInfo in
            let event = ResolvedEvent(eventInfo)
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
                .tint(colorForTransition(annotation.eventTransition))
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

    // Optionnel : change la couleur des marqueurs selon l'ancienneté
    private func colorForTransition(_ transition: String) -> Color {
        switch transition {
        case "Entrée", "Entrée (correspondance)", "Entrée (voie publique)":
            return .blue
        case "Sortie", "Sortie (correspondance)", "Sortie (voie publique)":
            return .red
        default:
            return .purple
        }
    }
}
