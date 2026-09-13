//
//  ExportFile.swift
//  metroreader
//
//  Created by Antoine Souben-Fink on 30/12/2025.
//


import SwiftUI
import UniformTypeIdentifiers


extension UTType {
    // This must match the Identifier you put in Xcode
    static var metropass: UTType {
        UTType(exportedAs: "xyz.docsystem.metropass")
    }
}

struct ExportFile: Transferable {
    let fileName: String
    /// Le contenu, sérialisé seulement au moment du partage. Le préparer à
    /// chaque rendu recopiait toute la fiche en JSON indenté, pour un bouton
    /// qu'on touche rarement.
    let contenu: () -> Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .metropass) { item in
            guard let data = item.contenu() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName { item in
            item.fileName.hasSuffix(".metropass") ? item.fileName : "\(item.fileName).metropass"
        }
    }
}
