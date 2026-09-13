//
//  ModeTransport.swift
//  metroreader
//

import Foundation


/// Les modes tels que la carte, le référentiel et l'affichage les écrivent.
///
/// Ils circulent en chaînes — dans les JSON livrés, dans le journal des
/// saisies, à l'écran —, et chaque table qui les classait tenait sa propre
/// liste : les pastilles ignoraient le câble, un ensemble ferré comptait le
/// Transilien quand l'autre l'oubliait. Ce qui dépend du mode se décide ici,
/// par des `switch` qui énumèrent tous les cas : un mode ajouté ne compile pas
/// tant qu'il n'est pas rangé partout.
enum ModeTransport: String, CaseIterable {
    // Ce que la carte encode
    case nonSpecifie = "Non spécifié"
    case busUrbain = "Bus urbain"
    case busInterurbain = "Bus interurbain"
    case metro = "Métro"
    case tramway = "Tramway"
    case train = "Train"
    case parking = "Parking"
    case consigneVelo = "Consigne à vélo"
    case voitureLibreService = "Voiture libre-service"
    case ruf = "RUF"

    // Ce que la carte ne dit pas, et que l'app ou le référentiel précisent
    case rer = "RER"
    case trainRER = "Train / RER"
    case transilien = "Transilien"
    case ter = "TER"
    case cable = "Câble"
    case noctilien = "Noctilien"
    case navetteFluviale = "Navette fluviale"

    /// Les seize modes de l'EN 1545, par code ; les codes réservés se lisent RUF.
    static let parCode: [ModeTransport] = [
        .nonSpecifie, .busUrbain, .busInterurbain, .metro,
        .tramway, .train, .ruf, .ruf,
        .parking, .ruf, .ruf, .consigneVelo,
        .ruf, .ruf, .voitureLibreService, .ruf,
    ]

    /// Le rail — métro, RER et trains —, qu'un même titre couvre d'un bloc.
    var estFerre: Bool {
        switch self {
        case .metro, .rer, .trainRER, .train, .transilien, .ter:
            return true
        case .nonSpecifie, .busUrbain, .busInterurbain, .tramway, .cable, .noctilien,
             .navetteFluviale, .parking, .consigneVelo, .voitureLibreService, .ruf:
            return false
        }
    }

    /// La surface, celle du ticket Bus-Tram. Le Noctilien n'en est pas : ce
    /// n'est qu'un libellé d'affichage, jamais un mode que la carte encode.
    var estSurface: Bool {
        switch self {
        case .busUrbain, .busInterurbain, .tramway, .cable:
            return true
        case .nonSpecifie, .metro, .rer, .trainRER, .train, .transilien, .ter, .noctilien,
             .navetteFluviale, .parking, .consigneVelo, .voitureLibreService, .ruf:
            return false
        }
    }

    /// Le symbole IDFM du mode, celui des plans et des quais ; rien pour ce qui
    /// n'en a pas.
    var pictogramme: String? {
        switch self {
        case .busUrbain, .busInterurbain: return "mode_bus"
        case .noctilien:                  return "mode_noctilien"
        case .train, .transilien, .ter:   return "mode_train"
        case .rer:                        return "mode_rer"
        case .trainRER:                   return "mode_train_rer"
        case .tramway:                    return "mode_tram"
        case .metro:                      return "mode_metro"
        case .cable:                      return "mode_cable"
        case .navetteFluviale:            return "mode_fluvial"
        case .nonSpecifie, .parking, .consigneVelo, .voitureLibreService, .ruf:
            return nil
        }
    }

    /// Le rang du mode parmi les pastilles d'un arrêt : le ferré d'abord, puis
    /// le métro, le tramway et le câble, la surface en dernier.
    var rangDesPastilles: Int {
        switch self {
        case .rer:             return 0
        case .trainRER:        return 1
        case .transilien:      return 2
        case .train:           return 3
        case .ter:             return 4
        case .metro:           return 5
        case .tramway:         return 6
        case .cable:           return 7
        case .busUrbain:       return 8
        case .busInterurbain:  return 9
        case .noctilien:       return 10
        case .navetteFluviale: return 11
        case .nonSpecifie, .parking, .consigneVelo, .voitureLibreService, .ruf:
            return 12
        }
    }

    /// Ce qu'une validation dans ce mode couvre, dit pour l'encart Titre
    /// valable. Un titre ferré vaut pour le RER et le train ensemble : un seul
    /// libellé et un seul pictogramme pour eux.
    var couverture: (libelle: String, pictogramme: String)? {
        switch self {
        case .busUrbain, .busInterurbain:                return ("en bus", "mode_bus")
        case .noctilien:                                 return ("en Noctilien", "mode_noctilien")
        case .metro:                                     return ("en métro", "mode_metro")
        case .rer, .trainRER, .train, .transilien, .ter: return ("en RER et train", "mode_train_rer")
        case .tramway:                                   return ("en tramway", "mode_tram")
        case .cable:                                     return ("en câble", "mode_cable")
        case .navetteFluviale, .nonSpecifie, .parking, .consigneVelo, .voitureLibreService, .ruf:
            return nil
        }
    }

    /// Le mode de contrôle qu'une validation dans ce mode couvre.
    var modeDeControle: ControlMode? {
        switch self {
        case .busUrbain, .busInterurbain, .noctilien:    return .bus
        case .tramway:                                   return .tram
        case .cable:                                     return .cable
        case .metro:                                     return .metro
        case .rer, .trainRER, .train, .transilien, .ter: return .rail
        case .navetteFluviale, .nonSpecifie, .parking, .consigneVelo, .voitureLibreService, .ruf:
            return nil
        }
    }
}
