//
//  CatalogView.swift
//  Makaba
//
//  Grid and List catalog browser with sorting, search, and thread previews.
//

import SwiftUI
import UIKit

// MARK: - Catalog Display & Sort Enums

public enum CatalogDisplayMode: String, CaseIterable, Identifiable {
    case grid = "Сетка"
    case list = "Список"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

public enum CatalogSortMode: String, CaseIterable, Identifiable {
    case bump = "По бампу"
    case replies = "По ответам"
    case score = "По оценке"
    case newest = "Сначала новые"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .bump: return "arrow.up.and.down"
        case .replies: return "bubble.left.and.bubble.right"
        case .score: return "hand.thumbsup"
        case .newest: return "clock"
        }
    }
}

// MARK: - Catalog View Model

@MainActor
public final class CatalogViewModel: ObservableObject {
    public let board: Board

    @Published public var threads: [CatalogThreadItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var searchText: String = ""
    @Published public var displayMode: CatalogDisplayMode = .grid
    @Published public var sortMode: CatalogSortMode = .bump

    private let apiClient: MakabaAPIClient

    public init(board: Board, apiClient: MakabaAPIClient = .shared) {
        self.board = board
        self.apiClient = apiClient
    }

    public func loadCatalog(forceRefresh: Bool = false) async {
        if threads.isEmpty {
            isLoading = true
        }
        errorMessage = nil

        if board.isDefunct {
            self.errorMessage = "Доска /\(board.id)/ закрыта администрацией сайта и удалена с серверов двача."
            self.isLoading = false
            return
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw MakabaAPIError.timeout
                }
                group.addTask {
                    try await self.performCatalogCascade(forceRefresh: forceRefresh)
                }
                _ = try await group.next()
                group.cancelAll()
            }
            self.isLoading = false
        } catch let apiError as MakabaAPIError {
            switch apiError {
            case .httpError(let statusCode, _):
                if statusCode == 404 || (500...599).contains(statusCode) {
                    self.errorMessage = "Доска /\(board.id)/ закрыта администрацией сайта или временно недоступна (код \(statusCode))."
                } else {
                    self.errorMessage = apiError.localizedDescription
                }
            case .timeout:
                self.errorMessage = "Превышено время ожидания ответа каталога доски /\(board.id)/ (15 сек)."
            default:
                self.errorMessage = apiError.localizedDescription
            }
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    private func performCatalogCascade(forceRefresh: Bool) async throws {
        // Attempt 1: catalog.json
        do {
            let response = try await apiClient.fetchCatalog(board: board.id, ignoreCache: forceRefresh)
            self.threads = response.threads
            return
        } catch {}

        // Attempt 2: index.json (Page 0)
        if let pageResponse = try? await apiClient.fetchBoardPage(board: board.id, page: 0, ignoreCache: forceRefresh) {
            let convertedThreads = pageResponse.threads.compactMap { threadContainer -> CatalogThreadItem? in
                guard let opPost = threadContainer.posts.first else { return nil }
                return CatalogThreadItem(
                    num: opPost.num,
                    parent: 0,
                    board: board.id,
                    subject: opPost.subject ?? "",
                    comment: opPost.comment,
                    date: opPost.date,
                    timestamp: opPost.timestamp,
                    lasthit: opPost.timestamp,
                    views: opPost.views ?? 0,
                    postsCount: threadContainer.posts.count,
                    filesCount: threadContainer.posts.reduce(0) { $0 + $1.files.count },
                    files: opPost.files
                )
            }
            if !convertedThreads.isEmpty {
                self.threads = convertedThreads
                return
            }
        }

        // Attempt 3: threads.json (flat listing)
        if let listResponse = try? await apiClient.fetchThreadList(board: board.id), !listResponse.threads.isEmpty {
            let convertedThreads = listResponse.threads.map { item in
                CatalogThreadItem(
                    num: item.num,
                    parent: 0,
                    board: board.id,
                    subject: item.subject,
                    comment: item.comment,
                    date: "",
                    timestamp: item.timestamp,
                    lasthit: item.lasthit,
                    views: item.views ?? 0,
                    postsCount: item.postsCount,
                    filesCount: item.filesCount ?? 0,
                    files: []
                )
            }
            self.threads = convertedThreads
            return
        }

        // All cascaded fallbacks failed, throw terminal 404 or network error
        throw MakabaAPIError.httpError(statusCode: 404, data: nil)
    }

    /// Filtered and sorted thread list according to search query and sort mode.
    public var filteredThreads: [CatalogThreadItem] {
        var result = threads

        // Search filtering against plain-text (strips HTML tags to prevent <br> matching)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { thread in
                thread.subject.lowercased().contains(query) ||
                thread.plainTextComment.lowercased().contains(query) ||
                String(thread.num).contains(query)
            }
        }

        // Sorting
        switch sortMode {
        case .bump:
            result.sort {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.lasthit > $1.lasthit
            }
        case .replies:
            result.sort {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.postsCount > $1.postsCount
            }
        case .score:
            result.sort {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return ($0.score ?? 0.0) > ($1.score ?? 0.0)
            }
        case .newest:
            result.sort {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.timestamp > $1.timestamp
            }
        }

        return result
    }
}

// MARK: - Catalog View

@MainActor
public struct CatalogView: View {
    @EnvironmentObject private var apiClient: MakabaAPIClient
    @StateObject private var viewModel: CatalogViewModel
    @State private var isNewThreadSheetPresented: Bool = false
    @State private var loadingSeconds: Int = 0

    public init(board: Board, apiClient: MakabaAPIClient = .shared) {
        self._viewModel = StateObject(wrappedValue: CatalogViewModel(board: board, apiClient: apiClient))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.threads.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.threads.isEmpty {
                errorView(error)
            } else if viewModel.filteredThreads.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle("/\(viewModel.board.id)/ — \(viewModel.board.name)")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Поиск в каталоге /\(viewModel.board.id)/"
        )
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // New Thread Button
                Button {
                    isNewThreadSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Новый тред")

                // Sort Menu
                Menu {
                    Picker("Сортировка", selection: $viewModel.sortMode) {
                        ForEach(CatalogSortMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: viewModel.sortMode.iconName)
                }

                // Grid / List Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.displayMode = (viewModel.displayMode == .grid) ? .list : .grid
                    }
                } label: {
                    Image(systemName: viewModel.displayMode == .grid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .sheet(isPresented: $isNewThreadSheetPresented) {
            PostingSheet(
                board: viewModel.board.id,
                threadNum: nil,
                boardModel: viewModel.board,
                apiClient: apiClient,
                onPostSuccess: { _ in
                    Task {
                        await viewModel.loadCatalog()
                    }
                }
            )
        }
        .refreshable {
            await viewModel.loadCatalog(forceRefresh: true)
        }
        .task {
            if viewModel.threads.isEmpty {
                await viewModel.loadCatalog()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            if viewModel.displayMode == .grid {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(viewModel.filteredThreads) { thread in
                        NavigationLink(value: thread) {
                            CatalogGridCard(thread: thread)
                        }
                        .buttonStyle(PlainNavigationButtonStyle())
                    }
                }
                .padding(10)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredThreads) { thread in
                        NavigationLink(value: thread) {
                            CatalogListRow(thread: thread)
                        }
                        .buttonStyle(PlainNavigationButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .navigationDestination(for: CatalogThreadItem.self) { thread in
            ThreadView(
                boardId: thread.board ?? viewModel.board.id,
                threadNum: thread.num,
                threadSubject: thread.displayTitle,
                apiClient: apiClient
            )
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
                .padding(.bottom, 2)
            Text("Загрузка каталога /\(viewModel.board.id)/")
                .font(.headline)
            Text(loadingSeconds < 2 ? "Подключение к серверам двача..." : "Сервер двача передает каталог тредов...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            loadingSeconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                loadingSeconds += 1
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Не удалось загрузить каталог")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task {
                    await viewModel.loadCatalog()
                }
            } label: {
                Label("Повторить", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Треды не найдены")
                .font(.headline)
            Text("Попробуйте изменить поисковый запрос или обновить каталог.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plain Navigation Button Style
// Prevents default blue button tint while maintaining tap feedback
struct PlainNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Catalog Grid Card

public struct CatalogGridCard: View {
    public let thread: CatalogThreadItem

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with badge overlays
            ZStack(alignment: .topTrailing) {
                thumbnailView

                // Sticky / Locked / Endless Indicators
                HStack(spacing: 4) {
                    if thread.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Circle())
                    }
                    if thread.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Circle())
                    }
                    if thread.isEndless {
                        Image(systemName: "infinity")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.blue.opacity(0.75))
                            .clipShape(Circle())
                    }
                }
                .padding(6)
            }

            // Subject / Title
            Text(thread.displayTitle)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            // Excerpt of Comment
            Text(cleanCommentExcerpt.isEmpty ? " " : cleanCommentExcerpt)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)

            Spacer(minLength: 0)

            // Bottom Badges: Replies, Files, Score
            HStack(spacing: 8) {
                // Replies count
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 10))
                    Text("\(thread.postsCount)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)

                // Files count
                if thread.filesCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                        Text("\(thread.filesCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Score
                if let score = thread.score, score != 0 {
                    Text(score > 0 ? "+\(score)" : "\(score)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(score > 0 ? .green : .red)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(height: 245)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }

    private var thumbnailView: some View {
        Group {
            if let primary = thread.primaryFile, let thumbURL = primary.thumbnailURL {
                MediaThumbnailView(url: thumbURL, targetSize: CGSize(width: 180, height: 180))
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.orange.opacity(0.18), Color.orange.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 4) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.orange.opacity(0.85))
                        Text("Текстовый тред")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 110)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .cornerRadius(8)
        .overlay(alignment: .bottomLeading) {
            if thread.filesCount > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "square.fill.on.square.fill")
                        .font(.system(size: 9))
                    Text("\(thread.filesCount)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(6)
            }
        }
    }

    private var cleanCommentExcerpt: String {
        thread.comment
            .replacingOccurrences(of: "<br/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Catalog List Row

public struct CatalogListRow: View {
    public let thread: CatalogThreadItem

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            ZStack(alignment: .topLeading) {
                thumbnailView

                // Sticky/Locked Badge
                if thread.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Circle())
                        .padding(4)
                }
            }

            // Info Column
            VStack(alignment: .leading, spacing: 4) {
                // Title and Post ID
                HStack(spacing: 6) {
                    Text(thread.displayTitle)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("#\(thread.num)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Comment excerpt
                if !cleanCommentExcerpt.isEmpty {
                    Text(cleanCommentExcerpt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Metadata Footer
                HStack(spacing: 12) {
                    // Replies
                    Label("\(thread.postsCount)", systemImage: "bubble.left.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    // Files
                    if thread.filesCount > 0 {
                        Label("\(thread.filesCount)", systemImage: "paperclip")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Score
                    if let score = thread.score, score != 0 {
                        Text(score > 0 ? "+\(score)" : "\(score)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(score > 0 ? .green : .red)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
    }

    private var thumbnailView: some View {
        Group {
            if let primary = thread.primaryFile, let thumbURL = primary.thumbnailURL {
                MediaThumbnailView(url: thumbURL, targetSize: CGSize(width: 152, height: 152))
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(Image(systemName: "text.bubble").foregroundColor(.secondary))
            }
        }
        .frame(width: 76, height: 76)
        .clipped()
        .cornerRadius(8)
    }

    private var cleanCommentExcerpt: String {
        thread.comment
            .replacingOccurrences(of: "<br/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
