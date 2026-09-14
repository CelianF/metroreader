//
//  ResolvedEvent.swift
//  metroreader
//

import Foundation


/// Ce qu'on sait d'un événement une fois les tables consultées.
///
/// La résolution se faisait dans l'init de chaque vue, donc une fois pour
/// toutes à la création : un arrêt identifié à la main n'apparaissait qu'au
/// prochain affichage de l'écran. Elle est ici recalculée à chaque passe de
/// rendu, et les vues observent le journal des saisies pour en déclencher une.
struct ResolvedEvent {
    let providerId: Int
    let locationId: Int?
    let routeNumber: Int?

    let location: NavigoStationInfo
    /// L'arrêt annoncé a été écarté pour cette validation : `location` ne le
    /// nomme plus.
    let isStopIgnored: Bool
    /// La ligne à représenter, éventuellement un repli portant le numéro de
    /// course brut — c'est `route.found` qui le dit.
    let route: NavigoLineInfo?
    /// Toutes les lignes que le numéro de course peut désigner, `route` en
    /// tête. Plus d'une quand le référentiel leur a donné le même code.
    let routeCandidates: [NavigoLineInfo]
    /// La ligne du référentiel ou du journal, d'où viennent le public_id et
    /// l'appartenance au réseau Noctilien.
    let lineData: NavigoLineInfo?
    let routeName: String?
    /// Le mode à afficher : celui de la carte, précisé par ce qu'on a appris de
    /// l'arrêt et de la ligne — un train devient RER, un bus devient Noctilien,
    /// un métro devient funiculaire.
    let mode: String
    /// Le mode tel que la carte l'encode, avant ces précisions.
    ///
    /// C'est lui, et lui seul, qui sert de clé au journal des saisies : les
    /// fonctions d'interprétation le recalculent chacune de leur côté et
    /// cherchent avec. Enregistrer sous le mode affiché rendait la saisie
    /// introuvable dès que les deux divergeaient — un bus Noctilien s'écrivait
    /// « Noctilien » et se relisait « Bus urbain ».
    let lookupMode: String
    /// La transition telle que le trajet la raconte : celle de la borne, sauf
    /// pour une sortie « voie publique » qu'une entrée ferrée suit de près, et
    /// pour cette entrée. Les deux se disent alors « Correspondance (voie
    /// publique) », ce que la borne ne pouvait pas savoir. Une validation
    /// refusée, elle, se dit « Refus » : elle n'a rien franchi. Et une entrée
    /// qui prolonge un trajet sous forfait se dit « Entrée (correspondance) ».
    let transition: String

    /// `transition` : ce que le trajet raconte de cette validation, que seules
    /// ses voisines permettent de dire — la liste qui les connaît la tire de
    /// `Validations`. Sans elle, c'est celle d'une validation lue seule : une
    /// sortie « voie publique » y reste une sortie.
    init(_ eventInfo: [String: Any], transition: String? = nil) {
        let routeBits = getKey(eventInfo, "EventRouteNumber")
        let codeBits = getKey(eventInfo, "EventCode") ?? ""
        var providerBits = getKey(eventInfo, "EventServiceProvider") ?? ""
        var locationBits = getKey(eventInfo, "EventLocationId") ?? ""

        // Un refus sans titre s'écrit en abrégé chez la SNCF : la gare se
        // retrouve par la porte, quand elle est relevée.
        if let porte = GateCorrections.porteDuRefus(eventInfo) {
            providerBits = String(porte.provider_id, radix: 2)
            locationBits = String(porte.location_id, radix: 2)
        }

        self.providerId = Int(providerBits, radix: 2) ?? 0
        self.locationId = Int(locationBits, radix: 2)
        self.routeNumber = Int(routeBits ?? "", radix: 2)

        // Un arrêt écarté ne se nomme ni ne se place plus : la validation garde
        // son mode, sa ligne et son heure.
        let annonce = interpretLocationId(locationBits, codeBits, providerBits, routeBits)
        self.isStopIgnored = ManualEntries.shared.isStopIgnored(eventInfo)
        self.location = isStopIgnored
            ? NavigoStationInfo(name: "Arrêt ignoré", provider_id: annonce.provider_id, line_id: nil,
                                location_id: annonce.location_id, mode: annonce.mode,
                                lat: 0, lon: 0, found: false)
            : annonce

        let eventCode = interpretEventCode(codeBits,
                                           isRouteNumberPresent: routeBits != nil,
                                           routeNumber: Int(routeBits ?? "0", radix: 2),
                                           serviceProvider: self.providerId)
        var finalMode = eventCode.0
        self.lookupMode = eventCode.0
        self.transition = transition ?? Validations([eventInfo], contrats: []).transition(de: 0)

        // Une seule résolution de ligne pour tout l'écran. Le nom affiché, la
        // pastille et le public_id venaient de trois chemins — une table codée
        // en dur, le référentiel, et le référentiel interrogé sous le mode
        // affiché — qui ne s'accordaient pas : la course 103 de la RATP se
        // lisait « Métro 3 bis » dans la liste et « 3B » dans la fiche.
        let candidats = routeBits.map { interpretRouteCandidates($0, codeBits, providerBits) } ?? []
        self.routeCandidates = candidats
        self.route = candidats.first
        var finalRouteName = self.route?.name

        if self.location.found && finalMode == "Train" {
            let stationModes = Set(self.location.lines.map { $0.mode })

            let hasRER = stationModes.contains("RER")
            let hasTrain = stationModes.contains("Transilien") || stationModes.contains("TER")

            if hasRER && hasTrain {
                finalMode = "Train / RER"
            } else if hasRER {
                finalMode = "RER"
            } else if hasTrain {
                finalMode = "Train"
            }

            if self.location.lines.count == 1 {
                finalRouteName = self.location.lines.first!.name
            }
        }

        // Le funiculaire de Montmartre se valide en métro : c'est son arrêt, que
        // lui seul dessert, qui le dit.
        if self.location.found && finalMode == ModeTransport.metro.rawValue
            && self.location.lines.contains(where: { $0.mode == ModeTransport.funiculaire.rawValue }) {
            finalMode = ModeTransport.funiculaire.rawValue
        }

        // La ligne qui porte le public_id et l'appartenance au Noctilien :
        // celle qu'on retient, pourvu qu'on l'ait trouvée. Un repli qui ne porte
        // que le numéro de course n'a pas d'identifiant à donner.
        self.lineData = (self.route?.found == true) ? self.route : nil

        if self.lineData?.is_noctilien == true {
            finalMode = "Noctilien"
        }

        self.mode = finalMode
        self.routeName = finalRouteName
    }

    /// Jour et heure de la validation, pour juger la fraîcheur d'une position.
    static func instant(_ eventInfo: [String: Any]) -> Date? {
        guard let jour = getKey(eventInfo, "EventDateStamp") else { return nil }
        return interpretEventInstant(jour, getKey(eventInfo, "EventTimeStamp") ?? "")
    }

    // MARK: - Ce qui manque au référentiel

    /// L'arrêt est annoncé mais introuvable, et personne ne l'a encore nommé.
    /// Écarté, il n'est pas à nommer : le code était juste, pas la validation.
    var isStopUnidentified: Bool { !location.found && locationId != nil && !isStopIgnored }

    /// Une validation de bus : le valideur est à bord, et l'arrêt qu'il annonce
    /// est celui qu'on lui a réglé. Mal réglé, il en donne un autre.
    var isBus: Bool {
        lookupMode == ModeTransport.busUrbain.rawValue || lookupMode == ModeTransport.busInterurbain.rawValue
    }

    /// La saisie qui a nommé l'arrêt, quand c'est bien d'elle que vient son nom :
    /// le référentiel passe devant le journal, et ne se supprime pas.
    var stopReport: StopReport? {
        guard let locationId,
              NavigoStations.find(providerId, routeNumber, locationId, lookupMode) == nil else { return nil }
        return ManualEntries.shared.stopReport(provider: providerId, location: locationId, mode: lookupMode)
    }

    /// Ni la table des lignes ni les cas particuliers n'ont donné de nom : ce
    /// qui s'affiche est le numéro de course brut.
    var isLineUnidentified: Bool {
        guard let route, let routeNumber, !route.found else { return false }
        return routeName == "\(routeNumber)"
    }

    /// Le numéro de course répond à plusieurs lignes à la fois : le référentiel
    /// leur a donné le même code, et rien sur la carte ne dit laquelle c'était.
    var isLineAmbiguous: Bool { routeCandidates.count > 1 }

    /// L'exploitant est annoncé par un numéro auquel aucun libellé ne répond.
    var isProviderUnidentified: Bool {
        providerId != 0 && isServiceProviderUnknown(providerId)
    }

    var hasSomethingToIdentify: Bool {
        isStopUnidentified || isLineUnidentified || isProviderUnidentified
    }
}
