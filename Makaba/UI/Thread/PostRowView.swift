//
//  PostRowView.swift
//  Makaba
//
//  Individual post view with rich formatted content, media previews, OP/Sage badges, and quote navigation.
//

import SwiftUI
import UIKit

public struct PostRowView: View {
    public let post: Post
    public let isOPPost: Bool
    public let boardId: String?
    public let threadNum: Int?
    public let replyNumbers: [Int]
    public let onQuoteTapped: (Int) -> Void
    public let onReplyTapped: (Post) -> Void
    public let onMediaTapped: (MediaFile) -> Void

    @State private var revealedNSFWFiles: Set<String> = []
    private let parsedComment: AttributedString

    public init(
        post: Post,
        isOPPost: Bool = false,
        boardId: String? = nil,
        threadNum: Int? = nil,
        replyNumbers: [Int] = [],
        onQuoteTapped: @escaping (Int) -> Void = { _ in },
        onReplyTapped: @escaping (Post) -> Void = { _ in },
        onMediaTapped: @escaping (MediaFile) -> Void = { _ in }
    ) {
        self.post = post
        self.isOPPost = isOPPost
        self.boardId = boardId
        self.threadNum = threadNum
        self.replyNumbers = replyNumbers
        self.onQuoteTapped = onQuoteTapped
        self.onReplyTapped = onReplyTapped
        self.onMediaTapped = onMediaTapped
        self.parsedComment = MakabaHTMLParser.parse(html: post.comment)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar
            headerView

            // Optional Subject Line
            if !post.displaySubject.isEmpty {
                Text(post.displaySubject)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }

            // Attached Media Grid / Carousel
            if post.hasFiles {
                attachmentsView
            }

            // Formatted Post Comment Body
            Text(parsedComment)
                .font(.body)
                .textSelection(.enabled)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Backlink / Reply Graph Pills ("Ответы: >>123, >>124")
            if !replyNumbers.isEmpty {
                repliesFooterView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = MakabaHTMLParser.toPlainText(html: post.comment)
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = ">>\(post.num)"
            } label: {
                Label("Скопировать номер (>>\(post.num))", systemImage: "number")
            }

            Button {
                onReplyTapped(post)
            } label: {
                Label("Ответить на пост", systemImage: "arrowshape.turn.up.left")
            }

            if let fullURL = postPermalinkURL {
                ShareLink(item: fullURL) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    /// Direct permalink URL to this specific post on 2ch.
    public var postPermalinkURL: URL? {
        let path: String
        if let board = boardId, !board.isEmpty {
            let parentThread = threadNum ?? (post.parent != nil && post.parent != 0 ? post.parent! : post.num)
            path = "/\(board)/res/\(parentThread).html#\(post.num)"
        } else if let parent = post.parent, parent != 0 {
            path = "/res/\(parent).html#\(post.num)"
        } else {
            path = "/res/\(post.num).html#\(post.num)"
        }
        return DomainConfigurationService.shared.buildURL(path: path)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center, spacing: 6) {
            // Post Number (tappable to trigger quote/reply)
            Button {
                onReplyTapped(post)
            } label: {
                Text("#\(post.num)")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)

            // Author Name
            Text(cleanAuthorName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(authorNameColor)

            // Tripcode
            if let trip = post.trip, !trip.isEmpty {
                Text(trip)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(.purple)
            }

            // OP Badge
            if post.isOP || isOPPost {
                Text("OP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange))
            }

            // Sage Badge
            if post.isSage {
                Text("SAGE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }

            // Banned Badge
            if post.isBanned {
                Text("ПОПАЛ ПОД ЛОШАДЬ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray))
            }

            Spacer()

            // Date / Time
            Text(post.date)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Net Vote Score
            if post.score != 0 {
                Text(post.score > 0 ? "+\(post.score)" : "\(post.score)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(post.score > 0 ? .green : .red)
            }
        }
    }

    private var cleanAuthorName: String {
        let clean = post.name.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Аноним" : clean
    }

    private var authorNameColor: Color {
        if post.isOP || isOPPost {
            return .orange
        }
        if post.name.contains("Admin") || post.name.contains("Mod") {
            return .red
        }
        return .primary
    }

    private var cardBackgroundColor: Color {
        if post.isOP || isOPPost {
            return Color.orange.opacity(0.04)
        }
        return Color(UIColor.secondarySystemGroupedBackground)
    }

    // MARK: - Attachments View

    @ViewBuilder
    private var attachmentsView: some View {
        if post.files.count == 1, let file = post.files.first {
            singleAttachmentView(file: file)
        } else {
            multipleAttachmentsView(files: post.files)
        }
    }

    private func singleAttachmentView(file: MediaFile) -> some View {
        Button {
            onMediaTapped(file)
        } label: {
            ZStack(alignment: .bottomLeading) {
                attachmentImage(file: file)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 260)
                    .clipped()
                    .cornerRadius(8)

                // Metadata overlay pill
                attachmentBadge(file: file)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }

    private func multipleAttachmentsView(files: [MediaFile]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files) { file in
                    Button {
                        onMediaTapped(file)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            attachmentImage(file: file)
                                .frame(width: 140, height: 140)
                                .clipped()
                                .cornerRadius(8)

                            attachmentBadge(file: file)
                                .padding(4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func attachmentImage(file: MediaFile) -> some View {
        let isNSFW = (file.nsfw ?? 0) != 0 && !revealedNSFWFiles.contains(file.name)

        ZStack {
            if let thumbURL = file.thumbnailURL {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(ProgressView().scaleEffect(0.8))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: isNSFW ? 20 : 0)
                    case .failure:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }

            // NSFW tap-to-reveal overlay
            if isNSFW {
                VStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                    Text("NSFW")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isNSFW {
                revealedNSFWFiles.insert(file.name)
            } else {
                onMediaTapped(file)
            }
        }
    }

    private func attachmentBadge(file: MediaFile) -> some View {
        HStack(spacing: 4) {
            if file.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
            }

            if let duration = file.duration, file.isVideo {
                Text(duration)
                    .font(.system(size: 9, weight: .bold))
            } else {
                Text("\(file.width)×\(file.height), \(file.formattedSize)")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
    }

    // MARK: - Replies Footer View

    private var repliesFooterView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 6) {
                Text("Ответы:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)

                FlowLayout(spacing: 6) {
                    ForEach(replyNumbers, id: \.self) { num in
                        Button {
                            onQuoteTapped(num)
                        } label: {
                            Text(">>\(num)")
                                .font(.system(size: 11, design: .monospaced).weight(.bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout
// High-performance flexible wrapping horizontal layout for quote badges
public struct FlowLayout: Layout {
    public var spacing: CGFloat = 6

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return CGSize(width: totalWidth, height: currentY + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
