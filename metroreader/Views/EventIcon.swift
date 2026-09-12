//
//  EventIcon.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

/// Le mode que le pictogramme annonce : celui où l'on entre, pas celui qu'on
/// quitte. Sortir du RER par une porte de correspondance, c'est entrer dans le
/// métro — le libellé, lui, garde la ligne d'où l'on vient.
func modeDuPictogramme(mode: String, transition: String) -> String {
    correspondanceVersMetro(transition: transition, mode: mode) ? "Métro" : mode
}

/// Le pictogramme IDFM d'un mode, tel qu'il figure au catalogue ; rien pour un
/// mode qui n'en a pas.
func pictogrammeIDFM(_ mode: String) -> String? {
    switch mode {
    case "Bus urbain", "Bus interurbain": return "mode_bus"
    case "Noctilien":                     return "mode_noctilien"
    case "Train":                         return "mode_train"
    case "RER":                           return "mode_rer"
    case "Train / RER":                   return "mode_train_rer"
    case "Tramway":                       return "mode_tram"
    case "Métro":                         return "mode_metro"
    case "Câble":                         return "mode_cable"
    default:                              return nil
    }
}

struct EventIcon: View {
    var eventTransportMode: String
    let eventTransition: String

    private var mode: String {
        modeDuPictogramme(mode: eventTransportMode, transition: eventTransition)
    }

    var body: some View {
        ZStack {
            if let pictogramme = pictogrammeIDFM(mode) {
                // Le Noctilien a son propre dessin, qu'on éclaircit plutôt que
                // d'inverser.
                if mode == "Noctilien" {
                    Image(pictogramme)
                        .resizable(resizingMode: .stretch)
                        .padding(.all, 8.0)
                        .brightness(1.0)
                } else {
                    Image(pictogramme)
                        .resizable(resizingMode: .stretch)
                        .padding(.all, 8.0)
                        .colorInvert()
                }
            } else {
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
