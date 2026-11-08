//
//  BoardListView.swift
//  Makaba
//
//  Categorized list of boards with search, favorites, and metadata badges.
//

import SwiftUI
import UIKit

// MARK: - Favorites Manager

/// Manages persisted favorite board IDs using UserDefaults.
public final class FavoritesManager: ObservableObject {
    private static let storageKey = "Makaba_FavoriteBoardIDs"

    @Published public private(set) var favoriteIDs: Set<String> = []

    public init() {
        loadFavorites()
    }

    public func isFavorite(boardId: String) -> Bool {
        favoriteIDs.contains(boardId)
    }

    public func toggleFavorite(boardId: String) {
        if favoriteIDs.contains(boardId) {
            favoriteIDs.remove(boardId)
        } else {
            favoriteIDs.insert(boardId)
        }
        saveFavorites()
    }

    private func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey) {
            self.favoriteIDs = Set(saved)
        } else {
            // Default favorites for fresh install
            self.favoriteIDs = ["b", "vg", "pr", "mov"]
            saveFavorites()
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.storageKey)
    }
}

// MARK: - Board List View Model

@MainActor
public final class BoardListViewModel: ObservableObject {
    @Published public var categories: [BoardCategory] = []
    @Published public var allBoards: [Board] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private let apiClient: MakabaAPIClient

    public init(apiClient: MakabaAPIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Fetches all boards and groups them into categories.
    public func loadBoards() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedBoards: [Board] = try await apiClient.fetchBoards()
            self.allBoards = fetchedBoards
            self.categories = BoardCategory.groupByCategory(fetchedBoards)
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Boards filtered by the current search query.
    public func filteredBoards(matching query: String) -> [Board] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allBoards
        }
        let clean = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return allBoards.filter { board in
            board.id.lowercased().contains(clean) ||
            board.name.lowercased().contains(clean) ||
            board.category.lowercased().contains(clean) ||
            (board.info.lowercased().contains(clean))
        }
    }

    /// Categories filtered by the search query.
    public var filteredCategories: [BoardCategory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return categories
        }
        let matched = filteredBoards(matching: query)
        return BoardCategory.groupByCategory(matched)
    }
}

// MARK: - Board List View

@MainActor
public struct BoardListView: View {
    @EnvironmentObject private var apiClient: MakabaAPIClient
    @EnvironmentObject private var favoritesManager: FavoritesManager

    @StateObject private var viewModel: BoardListViewModel

    /// Optional binding for split-view selection.
    @Binding public var selectedBoard: Board?

    public init(
        selectedBoard: Binding<Board?> = .constant(nil),
        apiClient: MakabaAPIClient = .shared
    ) {
        self._selectedBoard = selectedBoard
        self._viewModel = StateObject(wrappedValue: BoardListViewModel(apiClient: apiClient))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.categories.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.categories.isEmpty {
                errorView(error)
            } else {
                boardsList
            }
        }
        .navigationTitle("Доски")
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Поиск досок (/b/, Игры, Техника...)"
        )
        .refreshable {
            await viewModel.loadBoards()
        }
        .task {
            if viewModel.categories.isEmpty {
                await viewModel.loadBoards()
            }
        }
    }

    // MARK: - Subviews

    private var boardsList: some View {
        List {
            // Favorites Section (shown when not searching)
            if viewModel.searchText.isEmpty && !favoriteBoards.isEmpty {
                Section {
                    ForEach(favoriteBoards) { board in
                        NavigationLink(value: board) {
                            BoardRowView(board: board, isFavorite: true) {
                                favoritesManager.toggleFavorite(boardId: board.id)
                            }
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            selectedBoard = board
                        })
                    }
                } header: {
                    Label("Избранные доски", systemImage: "star.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline.weight(.semibold))
                }
            }

            // Categorized Sections
            ForEach(viewModel.filteredCategories) { category in
                Section(header: Text(category.name).font(.subheadline.weight(.semibold))) {
                    ForEach(category.boards) { board in
                        NavigationLink(value: board) {
                            BoardRowView(
                                board: board,
                                isFavorite: favoritesManager.isFavorite(boardId: board.id)
                            ) {
                                favoritesManager.toggleFavorite(boardId: board.id)
                            }
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            selectedBoard = board
                        })
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var favoriteBoards: [Board] {
        viewModel.allBoards.filter { favoritesManager.isFavorite(boardId: $0.id) }
            .sorted { $0.id < $1.id }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Загрузка списка досок 2ch.org...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Ошибка загрузки досок")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task {
                    await viewModel.loadBoards()
                }
            } label: {
                Label("Повторить", systemImage: "arrow.clockwise")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Board Row View

public struct BoardRowView: View {
    public let board: Board
    public let isFavorite: Bool
    public let onToggleFavorite: () -> Void

    public init(
        board: Board,
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void
    ) {
        self.board = board
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Board ID Pill (e.g. /b/)
            Text("/\(board.id)/")
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                )

            // Board Name and Metadata
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(board.name)
                        .font(.body.weight(.medium))
                        .foregroundColor(board.isDefunct ? .secondary : .primary)

                    if board.isDefunct {
                        Text("Архив")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if !board.info.isEmpty {
                    Text(cleanInfoText(board.info))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Capability Metadata Tags
                HStack(spacing: 6) {
                    if board.bumpLimit > 0 {
                        MetadataTag(label: "Бамп: \(board.bumpLimit)", icon: "arrow.up")
                    }
                    if board.enableSage {
                        MetadataTag(label: "Sage", icon: "arrow.down.right")
                    }
                    if board.enableIcons {
                        MetadataTag(label: "Иконки", icon: "photo")
                    }
                }
                .padding(.top, 2)
            }

            Spacer()

            // Favorite Star Button
            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .orange : .secondary.opacity(0.4))
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func cleanInfoText(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Metadata Tag

public struct MetadataTag: View {
    public let label: String
    public let icon: String

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.12))
        )
    }
}
