//
//  EventPreview.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

struct EventPreview: View {
    var eventInfo: [String: Any]
    /// La transition que le trajet raconte, tirée par la liste de `Validations`,
    /// qui connaît les voisines ; rien pour une validation lue seule.
    var transition: String?
    /// Faux dans l'historique rangé par jour, où la date coiffe déjà le trajet.
    var afficheDate: Bool

    // La résolution suit le journal des saisies : identifier un arrêt met à
    // jour la liste sans qu'il faille quitter l'écran.
    @ObservedObject private var entries = ManualEntries.shared

    init(eventInfo: [String : Any] = [:], transition: String? = nil, afficheDate: Bool = true) {
        self.eventInfo = eventInfo
        self.transition = transition
        self.afficheDate = afficheDate
    }

    private var event: ResolvedEvent { ResolvedEvent(eventInfo, transition: transition) }

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
                Text(afficheDate
                     ? "\(interpretDate(getKey(eventInfo, "EventDateStamp") ?? "")) - \(interpretTime(getKey(eventInfo, "EventTimeStamp") ?? ""))"
                     : interpretTime(getKey(eventInfo, "EventTimeStamp") ?? ""))
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
