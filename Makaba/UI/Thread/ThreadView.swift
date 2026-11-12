//
//  ThreadView.swift
//  Makaba
//
//  Smooth-scrolling thread reader with OP header, reply graph navigation,
//  quote popover interception, auto-scroll, and media gallery integration.
//

import SwiftUI
import SafariServices
import UIKit

// MARK: - Thread View Model

@MainActor
public final class ThreadViewModel: ObservableObject {
    public let boardId: String
    public let threadNum: Int

    @Published public var posts: [Post] = []
    @Published public var threadResponse: ThreadResponse? = nil
    @Published public var isLoading: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var errorMessage: String? = nil

    /// Lookup table mapping post number -> array of post numbers replying to it.
    @Published public var repliesToMap: [Int: [Int]] = [:]

    /// Flat ordered list of all media files in this thread.
    @Published public var allMediaFiles: [MediaFile] = []

    /// Pre-parsed HTML AttributedString cache per post number to prevent main thread hitches.
    @Published public var parsedComments: [Int: AttributedString] = [:]

    /// Associated board model when loaded.
    @Published public var board: Board? = nil

    /// Whether this thread was retrieved from the 2ch archive (read-only).
    @Published public var isArchived: Bool = false

    private let apiClient: MakabaAPIClient
    private var activeLoadTask: Task<Void, Never>?

    public init(boardId: String, threadNum: Int, apiClient: MakabaAPIClient = .shared) {
        self.boardId = boardId
        self.threadNum = threadNum
        self.apiClient = apiClient
    }

    /// Fetches all posts in the thread and calculates the reply graph with smooth incremental diffing.
    public func loadThread(forceRefresh: Bool = false) async {
        if (isLoading || isRefreshing) && !forceRefresh {
            return
        }
        activeLoadTask?.cancel()
        let currentTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.posts.isEmpty {
                self.isLoading = true
            } else {
                self.isRefreshing = true
            }
            self.errorMessage = nil

            do {
                let response = try await self.apiClient.fetchThread(board: self.boardId, threadNum: self.threadNum, ignoreCache: forceRefresh)
                self.threadResponse = response

                // Offload HTML Parsing: re-parse all if forceRefresh, otherwise parse new arrivals only
                let existingParsedKeys = Set(self.parsedComments.keys)
                let newPostsToParse = forceRefresh
                    ? response.posts
                    : response.posts.filter { !existingParsedKeys.contains($0.num) }
                let parsedMap = await Task.detached(priority: .userInitiated) {
                    newPostsToParse.reduce(into: [Int: AttributedString]()) { map, post in
                        map[post.num] = MakabaHTMLParser.parse(html: post.comment)
                    }
                }.value
                self.parsedComments.merge(parsedMap) { _, new in new }

                // Moderation-Aware Incremental Diffing
                let responsePostMap = Dictionary(response.posts.map { ($0.num, $0) }, uniquingKeysWith: { first, _ in first })
                let existingIDs = Set(self.posts.map(\.num))
                let responseIDs = Set(response.posts.map(\.num))

                let deletedIDs = existingIDs.subtracting(responseIDs)
                let newPosts = response.posts.filter { !existingIDs.contains($0.num) }

                if self.posts.isEmpty || forceRefresh {
                    self.posts = response.posts
                    self.buildReplyGraph()
                    self.buildMediaList()
                } else {
                    var updatedPosts = self.posts
                    // 1. Surgical removal of moderated/deleted posts
                    if !deletedIDs.isEmpty {
                        updatedPosts.removeAll { deletedIDs.contains($0.num) }
                    }
                    // 2. In-place metadata updates (scores, likes)
                    for i in 0..<updatedPosts.count {
                        if let updated = responsePostMap[updatedPosts[i].num] {
                            updatedPosts[i] = updated
                        }
                    }
                    // 3. Append strictly new posts
                    if !newPosts.isEmpty {
                        updatedPosts.append(contentsOf: newPosts)
                    }
                    // 4. Atomic publisher emission
                    self.posts = updatedPosts

                    // 5. Rebuild reply backlinks graph and media list if set of posts changed
                    if !deletedIDs.isEmpty || !newPosts.isEmpty {
                        self.buildReplyGraph()
                        self.buildMediaList()
                    }
                }

                self.isLoading = false
                self.isRefreshing = false
            } catch let apiError as MakabaAPIError {
                // Auto-fallback to archived thread on 404 ([ISSUE-24])
                var is404 = false
                if case .httpError(let code, _) = apiError, code == 404 { is404 = true }
                if is404, let archived = try? await self.apiClient.fetchArchivedThread(board: self.boardId, threadNum: self.threadNum) {
                    self.threadResponse = archived
                    self.posts = archived.posts
                    self.isArchived = true
                    self.buildReplyGraph()
                    self.buildMediaList()
                    self.isLoading = false
                    self.isRefreshing = false
                    return
                }
                self.errorMessage = apiError.localizedDescription
                self.isLoading = false
                self.isRefreshing = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.isRefreshing = false
            }
        }
        self.activeLoadTask = currentTask
        await currentTask.value
    }

    /// Computes the bidirectional reply graph across all posts.
    private func buildReplyGraph() {
        var map: [Int: [Int]] = [:]

        for post in posts {
            let referencedNumbers = post.referencedPostNumbers
            for targetNum in referencedNumbers {
                if map[targetNum] == nil {
                    map[targetNum] = [post.num]
                } else if !(map[targetNum]?.contains(post.num) ?? false) {
                    map[targetNum]?.append(post.num)
                }
            }
        }

        self.repliesToMap = map
    }

    /// Incremental reply graph update for appended posts only.
    private func buildIncrementalReplyGraph(newPosts: [Post]) {
        for post in newPosts {
            let referencedNumbers = post.referencedPostNumbers
            for targetNum in referencedNumbers {
                if repliesToMap[targetNum] == nil {
                    repliesToMap[targetNum] = [post.num]
                } else if !(repliesToMap[targetNum]?.contains(post.num) ?? false) {
                    repliesToMap[targetNum]?.append(post.num)
                }
            }
        }
    }

    /// Flattens all media files across all posts for the fullscreen gallery.
    private func buildMediaList() {
        var files: [MediaFile] = []
        for post in posts {
            files.append(contentsOf: post.files)
        }
        self.allMediaFiles = files
    }

    /// Incremental media list append for new posts only.
    private func buildIncrementalMediaList(newPosts: [Post]) {
        for post in newPosts {
            allMediaFiles.append(contentsOf: post.files)
        }
    }

    public var opPost: Post? {
        posts.first
    }

    public var threadTitle: String {
        if let title = threadResponse?.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if let opSubj = opPost?.displaySubject, !opSubj.isEmpty {
            return opSubj
        }
        return "Тред #\(threadNum)"
    }
}

// MARK: - Active Media Gallery Presentation

public struct ActiveMediaGalleryPresentation: Identifiable, Sendable {
    public var id: String { "\(index)_\(file.path)" }
    public let index: Int
    public let file: MediaFile
    public let allFiles: [MediaFile]

    public init(index: Int, file: MediaFile, allFiles: [MediaFile]) {
        self.index = index
        self.file = file
        self.allFiles = allFiles
    }
}

// MARK: - Thread Active Sheet

private enum ActiveSheet: Identifiable {
    case quote(Post)
    case safari(URL)
    case posting(Post)

    var id: String {
        switch self {
        case .quote(let post):
            return "quote_\(post.num)"
        case .safari(let url):
            return "safari_\(url.absoluteString)"
        case .posting(let post):
            return "posting_\(post.num)"
        }
    }
}

// MARK: - Thread View

@MainActor
public struct ThreadView: View {
    @EnvironmentObject private var apiClient: MakabaAPIClient
    @StateObject private var viewModel: ThreadViewModel

    // Unified state for modal sheets & popovers
    @State private var activeSheet: ActiveSheet? = nil
    @State private var activeMediaGallery: ActiveMediaGalleryPresentation? = nil
    @State private var toastMessage: String? = nil

    public init(
        boardId: String,
        threadNum: Int,
        threadSubject: String? = nil,
        apiClient: MakabaAPIClient = .shared
    ) {
        self._viewModel = StateObject(
            wrappedValue: ThreadViewModel(boardId: boardId, threadNum: threadNum, apiClient: apiClient)
        )
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        loadingView
                    } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                        errorView(error)
                    } else {
                        threadContent(proxy: proxy)
                    }
                }

                // Floating Action Buttons (Scroll to Bottom / Top / Reply)
                if !viewModel.posts.isEmpty {
                    floatingControls(proxy: proxy)
                        .padding(.trailing, 16)
                        .padding(.bottom, 20)
                }

                // Toast Feedback Overlay
                if let toast = toastMessage {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast)
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation {
                                self.toastMessage = nil
                            }
                        }
                }
            }
            .navigationTitle("/\(viewModel.boardId)/ #\(viewModel.threadNum)")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .toolbarBackground(Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Manual Refresh Button
                    Button {
                        Task {
                            await viewModel.loadThread(forceRefresh: true)
                        }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshing)

                    // Share Thread Link
                    if let threadURL = DomainConfigurationService.shared.buildURL(path: "/\(viewModel.boardId)/res/\(viewModel.threadNum).html") {
                        ShareLink(item: threadURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.loadThread(forceRefresh: true)
            }
            .task {
                if viewModel.posts.isEmpty {
                    await viewModel.loadThread()
                }
            }
            // Quote URL Scheme Interception for Quote Popovers
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "makaba-quote" || url.scheme == "2ch-quote" {
                    let targetStr = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
                    if let targetNum = Int(targetStr) {
                        if let targetPost = viewModel.posts.first(where: { $0.num == targetNum }) {
                            self.activeSheet = .quote(targetPost)
                        } else {
                            self.toastMessage = "Пост >>\(targetNum) находится в другом треде или был удалён."
                        }
                    }
                    return .handled
                } else if url.scheme == "http" || url.scheme == "https" {
                    self.activeSheet = .safari(url)
                    return .handled
                }
                return .systemAction
            })
            // Unified Modal Sheet Presentation
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .quote(let post):
                    QuotePreviewSheet(
                        post: post,
                        allPosts: viewModel.posts,
                        onJump: { jumpNum in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(jumpNum, anchor: .top)
                            }
                        }
                    )
                    .presentationDetents([.fraction(0.4), .medium, .large])
                    .presentationDragIndicator(.visible)
                case .safari(let url):
                    SafariView(url: url)
                case .posting(let post):
                    PostingSheet(
                        board: viewModel.boardId,
                        threadNum: viewModel.threadNum,
                        replyToPostNum: post.num,
                        threadTitle: viewModel.threadTitle,
                        boardModel: viewModel.board,
                        apiClient: apiClient,
                        onPostSuccess: { _ in
                            Task {
                                await viewModel.loadThread()
                            }
                        }
                    )
                }
            }
            // Fullscreen Media Gallery
            .fullScreenCover(item: $activeMediaGallery) { gallery in
                MediaGalleryView(
                    files: gallery.allFiles,
                    initialIndex: gallery.index
                )
                .id(gallery.id)
            }
        }
    }

    // MARK: - Thread Scroll Content

    private func threadContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // OP Header Banner
                opThreadHeaderView

                // Posts List
                ForEach(viewModel.posts) { post in
                    PostRowView(
                        post: post,
                        isOPPost: post.num == viewModel.threadNum,
                        boardId: viewModel.boardId,
                        threadNum: viewModel.threadNum,
                        replyNumbers: viewModel.repliesToMap[post.num] ?? [],
                        preParsedComment: viewModel.parsedComments[post.num],
                        onQuoteTapped: { quoteNum in
                            if let targetPost = viewModel.posts.first(where: { $0.num == quoteNum }) {
                                self.activeSheet = .quote(targetPost)
                            } else {
                                withAnimation {
                                    proxy.scrollTo(quoteNum, anchor: .top)
                                }
                            }
                        },
                        onReplyTapped: { targetPost in
                            self.activeSheet = .posting(targetPost)
                        },
                        onMediaTapped: { file in
                            let foundIndex = viewModel.allMediaFiles.firstIndex(where: { $0.path == file.path })
                                ?? viewModel.allMediaFiles.firstIndex(where: { $0.name == file.name })
                                ?? 0
                            self.activeMediaGallery = ActiveMediaGalleryPresentation(
                                index: foundIndex,
                                file: file,
                                allFiles: viewModel.allMediaFiles
                            )
                        }
                    )
                    .id(post.num)
                }

                // Bottom Anchor Spacer
                Color.clear
                    .frame(height: 60)
                    .id("bottom_anchor")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - OP Thread Header View

    private var opThreadHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Archive Notification Banner ([ISSUE-24])
            if viewModel.isArchived {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(.orange)
                    Text("Тред находится в архиве 2ch (только чтение)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Subject Title
            Text(viewModel.threadTitle)
                .font(.title3.weight(.bold))
                .foregroundColor(.primary)

            // Thread Stats Banner
            HStack(spacing: 16) {
                // Posts count
                Label("\(viewModel.posts.count) постов", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                // Files count
                if viewModel.allMediaFiles.count > 0 {
                    Label("\(viewModel.allMediaFiles.count) файлов", systemImage: "paperclip")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }

                // Unique posters
                if let posters = viewModel.threadResponse?.uniquePosters {
                    Label("\(posters) анонов", systemImage: "person.2.fill")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.top, 2)

            Divider()
                .padding(.top, 4)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    // MARK: - Floating Controls

    private func floatingControls(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            // Scroll to Top
            Button {
                if let firstPost = viewModel.posts.first {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(firstPost.num, anchor: .top)
                    }
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                    )
            }

            // Scroll to Bottom
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("bottom_anchor", anchor: .bottom)
                }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                    )
            }

            // Floating New Post / Reply Button
            Button {
                if let op = viewModel.opPost {
                    self.activeSheet = .posting(op)
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color.orange)
                            .shadow(color: Color.orange.opacity(0.4), radius: 6, x: 0, y: 3)
                    )
            }
        }
    }

    // MARK: - Loading & Error States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Загрузка треда #\(viewModel.threadNum)...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Не удалось загрузить тред")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task {
                    await viewModel.loadThread()
                }
            } label: {
                Label("Повторить", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Safari View Wrapper

public struct SafariView: UIViewControllerRepresentable {
    public let url: URL

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
