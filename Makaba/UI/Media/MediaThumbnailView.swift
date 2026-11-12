//
//  MediaThumbnailView.swift
//  Makaba
//
//  High-performance cached thumbnail view replacing AsyncImage.
//

import SwiftUI
import UIKit

/// High-performance asynchronously loaded and downsampled thumbnail view with two-tier cache.
public struct MediaThumbnailView: View {
    public let url: URL?
    public let targetSize: CGSize?
    public let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasFailed = false

    public init(
        url: URL?,
        targetSize: CGSize? = nil,
        contentMode: ContentMode = .fill
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        // Instant synchronous memory check on init to eliminate blank flash on reuse
        if let url = url, let cached = ImageCacheManager.shared.memoryImage(for: url) {
            _image = State(initialValue: cached)
        }
    }

    public var body: some View {
        Color.clear
            .overlay {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if hasFailed {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        )
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.7)
                        )
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: url) {
                await loadImage()
            }
    }

    private func loadImage() async {
        guard let url = url else {
            hasFailed = true
            return
        }

        if image != nil { return }

        isLoading = true
        hasFailed = false

        if let loaded = await ImageCacheManager.shared.image(for: url, targetSize: targetSize) {
            withAnimation(.easeOut(duration: 0.15)) {
                self.image = loaded
                self.isLoading = false
            }
        } else {
            self.hasFailed = true
            self.isLoading = false
        }
    }
}
