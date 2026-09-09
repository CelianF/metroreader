//
//  ControlMode.swift
//  metroreader
//

import Foundation


/// Le mode dans lequel on se déclare contrôlé.
///
/// La carte ne sait que ce qu'on a validé. Se dire contrôlé en RER après avoir
/// validé en métro, c'est la correspondance qu'on a oublié de valider : le
/// titre passe encore, et l'encart le dit en jaune. Se dire contrôlé en bus
/// avec une validation ferrée, c'est autre chose — un train n'est pas un bus,
/// et l'encart passe au rouge.
enum ControlMode: String, CaseIterable, Identifiable {
    // L'ordre est celui du menu. Les rawValue ne bougent pas : un réglage déjà
    // enregistré se relit.
    case automatique
    case metro
    case rail
    case aeroport
    case bus
    case tram
    case cable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatique: return "Automatique"
        case .bus:         return "Bus"
        case .tram:        return "Tramway"
        case .cable:       return "Câble"
        case .metro:       return "Métro"
        case .rail:        return "Train"
        case .aeroport:    return "Aéroport"
        }
    }

    /// Le même, tourné pour entrer dans une phrase.
    var enPhrase: String {
        switch self {
        case .automatique: return ""
        case .bus:         return "en bus"
        case .tram:        return "en tramway"
        case .cable:       return "en câble"
        case .metro:       return "en métro"
        case .rail:        return "en train"
        case .aeroport:    return "vers les aéroports"
        }
    }

    /// Le même, en sujet de phrase.
    var sujet: String {
        switch self {
        case .automatique: return "ce mode"
        case .bus:         return "le bus"
        case .tram:        return "le tramway"
        case .cable:       return "le câble"
        case .metro:       return "le métro"
        case .rail:        return "le RER ou le train"
        case .aeroport:    return "les aéroports"
        }
    }

    var icon: String {
        switch self {
        // Le ticket vierge : aucun mode déclaré, on s'en remet à la carte.
        case .automatique: return "ic_ticketing_default"
        case .metro:       return "mode_metro"
        case .rail:        return "mode_train_rer"
        case .aeroport:    return "mode_aeroport"
        case .bus:         return "mode_bus"
        case .tram:        return "mode_tram"
        case .cable:       return "mode_cable"
        }
    }

    /// Deux modes d'une même famille se valident aux mêmes bornes ou se
    /// succèdent sans en croiser : l'oubli y est vénieux. D'une famille à
    /// l'autre, non.
    private enum Famille { case surface, rail }

    private var famille: Famille? {
        switch self {
        case .bus, .tram, .cable: return .surface
        case .metro, .rail:       return .rail
        default:                  return nil
        }
    }

    /// Bus et tramway se valident à bord ou sur le quai, sans barrière à
    /// franchir. Avec un forfait en poche, y oublier le geste n'est pas voyager
    /// sans titre : le trajet est déjà payé, et l'encart le dit en jaune plutôt
    /// qu'en rouge. Partout ailleurs, on n'entre pas sans valider.
    var oubliVeniel: Bool {
        switch self {
        case .bus, .tram: return true
        default:          return false
        }
    }

    /// Le mode couvert par une validation, ramené aux mêmes termes.
    static func couvrant(_ mode: String) -> ControlMode? {
        switch mode {
        case "Bus urbain", "Bus interurbain", "Noctilien": return .bus
        case "Tramway":                                    return .tram
        case "Câble":                                      return .cable
        case "Métro":                                      return .metro
        case "RER", "Train", "Transilien":                 return .rail
        default:                                           return nil
        }
    }

    enum Accord {
        case exact   // la validation couvre ce mode
        case voisin  // même famille : la correspondance n'a pas été revalidée
        case non     // rien à voir
    }

    /// Ce que la validation en cours vaut face au mode où l'on se dit contrôlé.
    func accord(avec coverage: PassTimers.Coverage) -> Accord {
        switch self {
        case .automatique:
            // Sans contexte déclaré, on ne peut rien contredire.
            return .exact
        case .aeroport:
            return coverage.airport ? .exact : .non
        default:
            guard let couvert = Self.couvrant(coverage.mode) else { return .non }
            if couvert == self { return .exact }
            return couvert.famille == famille ? .voisin : .non
        }
    }
}
