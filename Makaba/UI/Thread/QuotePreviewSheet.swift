//
//  QuotePreviewSheet.swift
//  Makaba
//
//  Interactive popover / bottom sheet for previewing quoted posts without losing scroll position.
//

import SwiftUI
import UIKit

public struct QuotePreviewSheet: View {
    public let initialPost: Post
    public let allPosts: [Post]
    public let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Navigation history stack of previewed quotes (supports nested quotes like >>123 -> >>80)
    @State private var postHistory: [Post] = []

    public init(
        post: Post,
        allPosts: [Post] = [],
        onJump: @escaping (Int) -> Void = { _ in }
    ) {
        self.initialPost = post
        self.allPosts = allPosts
        self.onJump = onJump
        self._postHistory = State(initialValue: [post])
    }

    private var currentPost: Post {
        postHistory.last ?? initialPost
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header: Post Number, Author, Badges, Date
                        headerView

                        // Subject if present
                        if !currentPost.displaySubject.isEmpty {
                            Text(currentPost.displaySubject)
                                .font(.headline.weight(.bold))
                                .foregroundColor(.primary)
                        }

                        // Attachments Preview if any
                        if currentPost.hasFiles {
                            attachmentsCarousel
                        }

                        // Formatted Comment Body
                        Text(MakabaHTMLParser.parse(html: currentPost.comment))
                            .font(.body)
                            .textSelection(.enabled)
                            .lineSpacing(4)

                        // If post has referenced quotes, show interactive jump pills
                        if !currentPost.referencedPostNumbers.isEmpty {
                            referencedQuotesView
                        }
                    }
                    .padding(16)
                }

                Divider()

                // Bottom Action Bar: "Jump to post"
                bottomBar
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle("Ответ на >>\(currentPost.num)")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "makaba-quote" || url.scheme == "2ch-quote" {
                    let targetStr = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
                    if let targetNum = Int(targetStr) {
                        if let target = allPosts.first(where: { $0.num == targetNum }) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                postHistory.append(target)
                            }
                            return .handled
                        } else {
                            onJump(targetNum)
                            dismiss()
                            return .handled
                        }
                    }
                }
                return .systemAction
            })
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if postHistory.count > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                _ = postHistory.popLast()
                            }
                        } label: {
                            Label("Назад", systemImage: "chevron.left")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("#\(currentPost.num)")
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundColor(.orange)

            Text(cleanAuthorName(currentPost.name))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(currentPost.isOP ? .orange : .primary)

            if currentPost.isOP {
                Text("OP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange))
            }

            if currentPost.isSage {
                Text("SAGE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }

            Spacer()

            Text(currentPost.date)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var attachmentsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentPost.files) { file in
                    ZStack(alignment: .bottomLeading) {
                        if let thumbURL = file.thumbnailURL {
                            AsyncImage(url: thumbURL) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.15))
                                        .overlay(ProgressView().scaleEffect(0.6))
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
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
                        }

                        // Badge
                        HStack(spacing: 3) {
                            if file.isVideo {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                            }
                            Text(file.formattedSize)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .padding(4)
                    }
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
                }
            }
        }
    }

    private var referencedQuotesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Цитирует:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(currentPost.referencedPostNumbers, id: \.self) { num in
                    Button {
                        if let target = allPosts.first(where: { $0.num == num }) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                postHistory.append(target)
                            }
                        } else {
                            onJump(num)
                            dismiss()
                        }
                    } label: {
                        Text(">>\(num)")
                            .font(.system(size: 11, design: .monospaced).weight(.bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Пост #\(currentPost.num)")
                    .font(.footnote.weight(.semibold))
                Text("Перейти к позиции в треде")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                let targetNum = currentPost.num
                dismiss()
                onJump(targetNum)
            } label: {
                Label("Перейти к посту", systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func cleanAuthorName(_ name: String) -> String {
        let clean = name.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Аноним" : clean
    }
}
