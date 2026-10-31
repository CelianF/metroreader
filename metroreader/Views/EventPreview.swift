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

    /// Le mode, la ligne, puis le résultat ou la transition.
    private var sousTitre: String {
        var texte = event.mode
        if let routeName = event.routeName { texte += " \(routeName)" }
        let suite = interpretEventResult(of: eventInfo)
            ?? interpretTransitionLabel(event.transition, mode: event.mode)
        return texte + " - " + suite
    }

    var body: some View {
        let event = self.event
        HStack {
            EventIcon(eventTransportMode: event.mode, eventTransition: event.transition)
            VStack(alignment: .leading) {
                if event.location.found {
                    Text("\(event.location.name)")
                        .fontWeight(.bold)

                    // Un seul texte : en morceaux, chacun revenait à la ligne de
                    // son côté dans une colonne étroite, « RER B » à gauche et
                    // « - Correspondance vers / le métro » empilé à droite.
                    Text(sousTitre)
                        .font(.caption)
                        .foregroundColor(Color.gray)
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
