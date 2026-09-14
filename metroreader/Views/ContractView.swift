//
//  ContractView.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

struct ContractView: View {
    var contractInfo: [String: Any] = [
        "ContractBitmap": [
            "ContractTariff": "0101000000000000",
            // "ContractValidityEndDate": "00000000000000000"
        ],
        "Counter": [
            "CounterStructureNumber": "01100", "CounterRelativeFirstStamp15mn": "010001001010110100", "CounterContractCount": "000010", "CounterLastLoad": "00001010"
        ]
    ]
    
    @AppStorage(ModeDebug.donneesBrutes) private var afficheBrut = false
    @AppStorage(ModeDebug.base) private var baseBrute = BaseBrute.hexadecimal
    /// La base des données brutes à afficher, rien quand elles sont masquées.
    private var brut: BaseBrute? { afficheBrut ? baseBrute : nil }

    var body: some View {
        List {
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Text("\(interpretTariff(getKey(contractInfo, "ContractTariff") ?? "", getKey(contractInfo, "ContractValidityEndDate") ?? ""))")
                        .brut(getKey(contractInfo, "ContractTariff"), si: brut)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    HStack(spacing: 0) {
                        Text(interpretDate(getKey(contractInfo, "ContractValidityStartDate") ?? ""))
                            .brut(getKey(contractInfo, "ContractValidityStartDate"), si: brut)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.gray)
                        if let contractValidityEndDate = getKey(contractInfo, "ContractValidityEndDate") {
                            Text(" - \(interpretDate(contractValidityEndDate))")
                                .brut(contractValidityEndDate, si: brut)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.white.opacity(0.0))
            }
            
            if let counterContractCount = getKey(contractInfo, "CounterContractCount") {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ticket\(interpretInt(counterContractCount) == 1 ? "" : "s") restants")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(interpretInt(counterContractCount))")
                                .brut(counterContractCount, si: brut)
                                .fontWeight(.semibold)
                        }
                        
                        Divider ()
                        
                        HStack {
                            Text("Dernière recharge")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(interpretInt(getKey(contractInfo, "CounterLastLoad") ?? ""))")
                                .brut(getKey(contractInfo, "CounterLastLoad"), si: brut)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("État")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(interpretStatus(getKey(contractInfo, "ContractStatus") ?? ""))
                            .brut(getKey(contractInfo, "ContractStatus"), si: brut)
                            .fontWeight(.semibold)
                    }
                    
                    if let contractValidityZones = getKey(contractInfo, "ContractValidityZones") {
                        Divider()
                        
                        HStack {
                            Text("Zones")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(interpretZonesShort(contractValidityZones))
                                .brut(contractValidityZones, si: brut)
                                .fontWeight(.semibold)
                        }
                    }
                    
                    if let contractSerialNumber = getKey(contractInfo, "ContractSerialNumber") {
                        Divider()
                        
                        HStack {
                            Text("Numéro de série")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(interpretInt(contractSerialNumber))")
                                .brut(contractSerialNumber, si: brut)
                                .fontWeight(.semibold)
                        }
                    }
                    
                    if let contractAuthenticator = getKey(contractInfo, "ContractAuthenticator") {
                        Divider()
                        
                        HStack {
                            Text("Authenticateur")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(interpretInt(contractAuthenticator))")
                                .brut(contractAuthenticator, si: brut)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            
            if let contractSaleDate = getKey(contractInfo, "ContractValiditySaleDate"), Int(contractSaleDate, radix: 2) != 0 {
                Section(header: Text("Vente")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Vendu le")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(interpretDate(getKey(contractInfo, "ContractValiditySaleDate") ?? ""))
                                .brut(getKey(contractInfo, "ContractValiditySaleDate"), si: brut)
                                .fontWeight(.semibold)
                        }
                        
                        if let contractSaleAgent = getKey(contractInfo, "ContractValiditySaleAgent") {
                            Divider()
                            
                            HStack {
                                Text("Vendu par")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(interpretServiceProvider(contractSaleAgent))
                                    .brut(contractSaleAgent, si: brut)
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        if let contractSaleDevice = getKey(contractInfo, "ContractValiditySaleDevice") {
                            Divider()
                            
                            HStack {
                                Text("Appareil")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(interpretInt(contractSaleDevice))")
                                    .brut(contractSaleDevice, si: brut)
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        if let contractPriceAmount = getKey(contractInfo, "ContractPriceAmount") {
                            Divider()
                            
                            HStack {
                                Text("Prix de vente")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(String(format: "%.2f €", interpretAmount(contractPriceAmount)))
                                    .brut(contractPriceAmount, si: brut)
                                    .fontWeight(.semibold)
                            }
                        }
                        
                        if let contractPayMethod = getKey(contractInfo, "ContractPayMethod") {
                            Divider()
                            
                            HStack {
                                Text("Mode de paiement")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(interpretPayMethod(contractPayMethod))
                                    .brut(contractPayMethod, si: brut)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContractView()
}
