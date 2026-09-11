//
//  EventPreview.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

struct EventPreview: View {
    var eventInfo: [String: Any]
    /// Les validations écrites après et avant celle-ci : elles disent si une
    /// sortie ou une entrée « voie publique » formaient une correspondance.
    var suivants: [[String: Any]]
    var precedents: [[String: Any]]

    // La résolution suit le journal des saisies : identifier un arrêt met à
    // jour la liste sans qu'il faille quitter l'écran.
    @ObservedObject private var entries = ManualEntries.shared

    init(eventInfo: [String : Any] = [:], suivants: [[String: Any]] = [], precedents: [[String: Any]] = []) {
        self.eventInfo = eventInfo
        self.suivants = suivants
        self.precedents = precedents
    }

    private var event: ResolvedEvent { ResolvedEvent(eventInfo, suivants: suivants, precedents: precedents) }

    var body: some View {
        let event = self.event
        HStack {
            EventIcon(eventTransportMode: event.mode, eventTransition: event.transition)
            VStack(alignment: .leading) {
                if event.location.found {
                    Text("\(event.location.name)")
                        .fontWeight(.bold)
                    
                    HStack(spacing: 0) {
                        Text("\(event.mode)")
                            .font(.caption)
                            .foregroundColor(Color.gray)
                        if let routeName = event.routeName {
                            Text(" \(routeName)")
                                .font(.caption)
                                .foregroundColor(Color.gray)
                        }
                        if let resultat = interpretEventResult(of: eventInfo) {
                            Text(" - \(resultat)")
                                .font(.caption)
                                .foregroundColor(Color.gray)
                        }
                        else {
                            Text(" - \(interpretTransitionLabel(event.transition, mode: event.mode))")
                                .font(.caption)
                                .foregroundColor(Color.gray)
                        }
                    }
                }
                else {
                    HStack(spacing: 0) {
                        Text("\(event.mode)")
                            .fontWeight(.bold)
                        if let routeName = event.routeName {
                            Text(" \(routeName)")
                                .fontWeight(.bold)
                        }
                    }
                    if let resultat = interpretEventResult(of: eventInfo) {
                        Text(resultat)
                            .font(.caption)
                            .foregroundColor(Color.gray)
                    }
                    else {
                        Text(interpretTransitionLabel(event.transition, mode: event.mode))
                            .font(.caption)
                            .foregroundColor(Color.gray)
                    }
                }
                Text("\(interpretDate(getKey(eventInfo, "EventDateStamp") ?? "")) - \(interpretTime(getKey(eventInfo, "EventTimeStamp") ?? ""))")
                    .font(.caption)
                    .foregroundColor(Color.gray)
            }
            
            Spacer()
        }
        
    }
}

#Preview {
    EventPreview()
}
