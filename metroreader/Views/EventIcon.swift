//
//  EventIcon.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

struct EventIcon: View {
    var eventTransportMode: String
    let eventTransition: String

    /// Le mode que le pictogramme annonce : celui où l'on entre, pas celui
    /// qu'on quitte. Sortir du RER par une porte de correspondance, c'est
    /// entrer dans le métro — le libellé, lui, garde la ligne d'où l'on vient.
    private var mode: String {
        correspondanceVersMetro(transition: eventTransition, mode: eventTransportMode)
            ? "Métro"
            : eventTransportMode
    }

    var body: some View {
        ZStack {
            switch (mode) {
            case "Bus urbain":
                Image("mode_bus")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "Noctilien":
                Image("mode_noctilien")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .brightness(1.0)
            case "Bus interurbain":
                Image("mode_bus")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "Train":
                Image("mode_train")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "RER":
                Image("mode_rer")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "Train / RER":
                Image("mode_train_rer")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "Tramway":
                Image("mode_tram")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "Métro":
                Image("mode_metro")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            case "Câble":
                Image("mode_cable")
                    .resizable(resizingMode: .stretch)
                    .padding(.all, 8.0)
                    .colorInvert()
            default:
                Image(systemName: "questionmark.circle.fill")
            }
        }
            .foregroundColor(Color.white)
            .frame(width: 40.0, height: 40.0)
            .background(TransitionKind(eventTransition).color)
            .clipShape(RoundedRectangle(cornerRadius: 5.0))
    }
}

#Preview {
    EventIcon(eventTransportMode: "Câble", eventTransition: "Entrée")
}
