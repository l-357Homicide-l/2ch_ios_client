//
//  ThreadMediaGridView.swift
//  Makaba
//
//  All-media grid view displaying images and videos extracted from thread posts.
//

import SwiftUI

public enum MediaFilterType: String, CaseIterable, Identifiable {
    case all = "Все"
    case images = "Картинки"
    case videos = "Видео"

    public var id: String { rawValue }
}

public struct ThreadMediaGridView: View {
    public let mediaFiles: [MediaFile]
    public let onSelectMedia: (MediaFile) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFilter: MediaFilterType = .all
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 3)
    ]

    public init(mediaFiles: [MediaFile], onSelectMedia: @escaping (MediaFile) -> Void) {
        self.mediaFiles = mediaFiles
        self.onSelectMedia = onSelectMedia
    }

    private var filteredFiles: [MediaFile] {
        switch selectedFilter {
        case .all:
            return mediaFiles
        case .images:
            return mediaFiles.filter { !$0.isVideo }
        case .videos:
            return mediaFiles.filter { $0.isVideo }
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Category Filter
                Picker("Фильтр", selection: $selectedFilter) {
                    ForEach(MediaFilterType.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if filteredFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Вложений не найдено")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(filteredFiles) { file in
                                gridCell(file: file)
                                    .onTapGesture {
                                        onSelectMedia(file)
                                        dismiss()
                                    }
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Галерея тредa (\(filteredFiles.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gridCell(file: MediaFile) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbURL = file.thumbnailURL {
                MediaThumbnailView(url: thumbURL, targetSize: CGSize(width: 130, height: 130))
                    .frame(height: 110)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 110)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }

            // Video Format / Duration Badge
            if file.isVideo {
                HStack(spacing: 2) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                    if let dur = file.duration, !dur.isEmpty {
                        Text(dur)
                            .font(.system(size: 9, weight: .bold))
                    } else {
                        Text("WEBM")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(4)
                .padding(4)
            }
        }
    }
}
