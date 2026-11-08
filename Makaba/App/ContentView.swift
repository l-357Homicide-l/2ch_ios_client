//
//  ContentView.swift
//  Makaba
//
//  Root application view hosting adaptive navigation (NavigationSplitView for iPad,
//  NavigationStack for iPhone) with board picker, catalog browser, and thread reader.
//

import SwiftUI
import UIKit

@MainActor
public struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedBoard: Board? = nil

    public init() {}

    public var body: some View {
        if horizontalSizeClass == .regular {
            // iPad / Regular Width: Multi-Column Split View
            NavigationSplitView {
                BoardListView(selectedBoard: $selectedBoard)
            } detail: {
                if let board = selectedBoard {
                    NavigationStack {
                        CatalogView(board: board)
                    }
                } else {
                    emptySelectionView
                }
            }
        } else {
            // iPhone / Compact Width: Hierarchical Navigation Stack
            NavigationStack {
                BoardListView(selectedBoard: $selectedBoard)
                    .navigationDestination(for: Board.self) { board in
                        CatalogView(board: board)
                    }
            }
        }
    }

    // MARK: - iPad Placeholder Detail View

    private var emptySelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange.opacity(0.8))

            Text("Выберите доску")
                .font(.title2.weight(.bold))

            Text("Выберите интересующую доску в боковой панели для просмотра каталога тредов.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
