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
    /// l'arrêt et de la ligne — un train devient RER, un bus devient Noctilien.
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
    /// refusée, elle, se dit « Refus » : elle n'a rien franchi.
    let transition: String

    /// `suivants` et `precedents` : les validations écrites après et avant
    /// celle-ci, de la plus proche à la plus lointaine. Sans elles, une sortie
    /// « voie publique » reste une sortie, et l'entrée une entrée.
    init(_ eventInfo: [String: Any], suivants: [[String: Any]] = [], precedents: [[String: Any]] = []) {
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

        var finalRouteName: String? = nil
        if self.routeNumber != nil {
            finalRouteName = interpretRouteNumber(routeBits ?? "", codeBits, providerBits)
        }

        self.location = interpretLocationId(locationBits, codeBits, providerBits, routeBits)

        let eventCode = interpretEventCode(codeBits,
                                           isRouteNumberPresent: routeBits != nil,
                                           routeNumber: Int(routeBits ?? "0", radix: 2),
                                           serviceProvider: self.providerId)
        var finalMode = eventCode.0
        self.lookupMode = eventCode.0
        // Un refus n'a rien franchi. Une porte relevée tranche d'elle-même ;
        // ailleurs, la sortie « voie publique » et l'entrée qui la suit se
        // reconnaissent l'une l'autre.
        let instant = Self.instant(eventInfo)
        let parLaPorte = transitionAuxPortes(eventCode.1, eventInfo)
        if isRefus(eventInfo) {
            self.transition = transitionRefus
        } else if parLaPorte != eventCode.1 {
            self.transition = parLaPorte
        } else if sortieVersCorrespondance(transition: eventCode.1, instant: instant, suivants: suivants)
                    || entreeApresCorrespondance(transition: eventCode.1, mode: eventCode.0, instant: instant, precedents: precedents) {
            self.transition = correspondanceVoiePublique
        } else {
            self.transition = eventCode.1
        }

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

        // Le journal d'abord, comme dans `interpretRouteCandidates` : les deux
        // chemins cherchaient dans l'ordre inverse l'un de l'autre, si bien
        // qu'une ligne nommée à la main s'affichait en pastille pendant que le
        // `public_id` restait celui du référentiel — et c'est ce `public_id`
        // qui filtre les arrêts proposés. Même événement, deux réponses.
        self.lineData = ManualEntries.shared.line(provider: self.providerId,
                                                  route: self.routeNumber ?? -1,
                                                  mode: self.lookupMode)
            ?? NavigoLines.find(self.providerId, self.routeNumber ?? 0, finalMode)

        if self.lineData?.is_noctilien == true {
            finalMode = "Noctilien"
        }

        self.mode = finalMode
        self.routeName = finalRouteName
        let candidats = routeBits.map { interpretRouteCandidates($0, codeBits, providerBits) } ?? []
        self.routeCandidates = candidats
        self.route = candidats.first
    }

    /// Jour et heure de la validation, pour juger la fraîcheur d'une position.
    static func instant(_ eventInfo: [String: Any]) -> Date? {
        guard let jour = getKey(eventInfo, "EventDateStamp") else { return nil }
        return interpretEventInstant(jour, getKey(eventInfo, "EventTimeStamp") ?? "")
    }

    // MARK: - Ce qui manque au référentiel

    /// L'arrêt est annoncé mais introuvable, et personne ne l'a encore nommé.
    var isStopUnidentified: Bool { !location.found && locationId != nil }

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
