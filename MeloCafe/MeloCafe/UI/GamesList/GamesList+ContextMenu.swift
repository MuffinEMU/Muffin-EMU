//
//  GamesList+ContextMenu.swift
//  MeloCafe
//
//  Created by Stossy11 on 25/4/2026.
//

import SwiftUI

extension GamesListView {
    @ViewBuilder
    func contextMenu(_ game: GameInfoSwift) -> some View {
        Button {
            self.activeSheet = .graphicPacks(game: game)
        } label: {
            Text("Graphic Packs")
        }

    }
}
