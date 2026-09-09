//
//  EventPreview.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

struct EventPreview: View {
    var eventInfo: [String: Any]

    // La résolution suit le journal des saisies : identifier un arrêt met à
    // jour la liste sans qu'il faille quitter l'écran.
    @ObservedObject private var entries = ManualEntries.shared

    init(eventInfo: [String : Any] = [:]) {
        self.eventInfo = eventInfo
    }

    private var event: ResolvedEvent { ResolvedEvent(eventInfo) }

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
                        if getKey(eventInfo, "EventResult") != nil {
                            Text(" - \(interpretEventResult(getKey(eventInfo, "EventResult") ?? ""))")
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
                    if getKey(eventInfo, "EventResult") != nil {
                        Text("\(interpretEventResult(getKey(eventInfo, "EventResult") ?? ""))")
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
