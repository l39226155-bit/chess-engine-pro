//
//  PGNImport.swift
//  CHESS ENGINE PRO
//
//  Reusable .pgn file importer for the analysis, training and home screens.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var pgn: UTType {
        UTType(filenameExtension: "pgn") ?? .plainText
    }
}

struct PGNImporter: ViewModifier {
    @Binding var isPresented: Bool
    var onGame: (PGNGame) -> Void
    var onError: (String) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented,
                             allowedContentTypes: [.pgn, .plainText],
                             allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .isoLatin1) else {
                        onError("Die Datei konnte nicht gelesen werden.")
                        return
                    }
                    let games = try PGN.parse(text)
                    guard let game = games.first else {
                        onError("Keine Partie in der Datei gefunden.")
                        return
                    }
                    onGame(game)
                } catch {
                    onError(error.localizedDescription)
                }
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code != NSUserCancelledError {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

extension View {
    func pgnImporter(isPresented: Binding<Bool>,
                     onGame: @escaping (PGNGame) -> Void,
                     onError: @escaping (String) -> Void) -> some View {
        modifier(PGNImporter(isPresented: isPresented, onGame: onGame, onError: onError))
    }
}
