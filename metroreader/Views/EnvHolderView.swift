//
//  EnvHolder.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 06/02/2025.
//

import SwiftUI

struct EnvHolderView: View {
    var envHolderInfo: [String: Any]
    /// Le numéro de la carte, rien quand la lecture ne l'a pas donné. Il se lit
    /// ici plutôt que sur le visuel du pass, qu'il masquait.
    var cardID: UInt64 = 0

    /// Ce que dit la lettre imprimée sur la carte : A pour un Navigo Annuel,
    /// I pour un Imagine R.
    private var typeDeLaCarte: String? {
        guard let statut = getKey(envHolderInfo, "HolderDataCardStatus") else { return nil }
        switch interpretNavigoPersonalizationStatusCode(statut) {
        case "Navigo Annuel":    return "Annuel"
        case "Navigo Imagine R": return "Imagine R"
        default:                 return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if cardID != 0 {
                HStack {
                    Text("Numéro de carte")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(cardID)")
                        .fontWeight(.semibold)
                }

                Divider()
            }

            if let type = typeDeLaCarte {
                HStack {
                    Text("Type")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(type)
                        .fontWeight(.semibold)
                }

                Divider()
            }

            HStack {
                Text("Version de l'app")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(interpretAppVersionNumber(getKey(envHolderInfo, "EnvApplicationVersionNumber") ?? ""))")
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            HStack {
                Text("Pays")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(interpretNetworkId(getKey(envHolderInfo, "EnvNetworkId") ?? "").0)")
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            HStack {
                Text("Réseau")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(interpretNetworkId(getKey(envHolderInfo, "EnvNetworkId") ?? "").1)")
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            HStack {
                Text("Date d'expiration")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(interpretDate(getKey(envHolderInfo, "EnvApplicationValidityEndDate") ?? ""))")
                    .fontWeight(.semibold)
            }
            
            if let holderCardStatus = getKey(envHolderInfo, "HolderDataCardStatus") {
                
                Divider()
                
                HStack {
                    Text("Type de carte")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(interpretPersonalizationStatusCode(holderCardStatus).0)")
                        .fontWeight(.semibold)
                }
            }
            if let holderCommercialId = getKey(envHolderInfo, "HolderDataCommercialID") {
                Divider()
                
                HStack {
                    Text("Type commercial")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(interpretNavigoCommercialId(holderCommercialId))")
                        .fontWeight(.semibold)
                }
            }
            
            if let issuerId = getKey(envHolderInfo, "EnvApplicationIssuerId"), Int(issuerId, radix: 2) != 0 {
                Divider()
                
                HStack {
                    Text("Fournisseur")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(interpretServiceProvider(issuerId))")
                        .fontWeight(.semibold)
                }
            }
            
            Divider()
            
            HStack {
                Text("Authenticateur")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(interpretInt(getKey(envHolderInfo, "EnvAuthenticator") ?? ""))")
                    .fontWeight(.semibold)
            }
        }
    }
}

#Preview {
    EnvHolderView(envHolderInfo: ["EnvBitmap" : [
        "EnvAuthenticator" : "1110010100010011",
        "EnvApplicationIssuerId" : "00000000",
        "EnvApplicationValidityEndDate" : "11010001100101",
        "EnvNetworkId" : "001001010000100100000001"
      ],
      "HolderBitmap" : [
        "HolderDataBitmap" : [
          "HolderDataCommercialID" : "010001",
          "HolderDataCardStatus" : "0000"
        ]
      ],
      "EnvApplicationVersionNumber" : "001001"])
}
