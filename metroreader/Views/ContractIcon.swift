//
//  ContractIcon.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 07/02/2025.
//

import SwiftUI

struct ContractIcon: View {
    let contractType: Int

    var body: some View {
        ZStack {
            Image(TariffCatalog.find(contractType)?.icon ?? TariffCatalog.defaultIcon)
                .resizable(resizingMode: .stretch)
                .padding(.all, 8.0)
        }
        .frame(width: 40.0, height: 40.0)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5.0))
    }
}

#Preview {
    ContractIcon(contractType: 0x0000)
}
