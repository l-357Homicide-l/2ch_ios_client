//
//  MediaGalleryView.swift
//  Makaba
//
//  Full-resolution media viewer with gesture zooming, pagination, metadata overlay,
//  save-to-photos, and WebM video player container hook for Milestone 4.
//

import SwiftUI
import Photos
import UIKit

public struct MediaGalleryView: View {
    public let files: [MediaFile]
    public let initialIndex: Int

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int
    @State private var showOverlay: Bool = true
    @State private var saveAlertMessage: String? = nil
    @State private var isShowingSaveAlert: Bool = false
    @State private var isSavingMedia: Bool = false
    @State private var activeImageSaver: ImageSaver? = nil

    public init(files: [MediaFile], initialIndex: Int = 0) {
        self.files = files
        self.initialIndex = min(max(0, initialIndex), max(0, files.count - 1))
        self._currentIndex = State(initialValue: min(max(0, initialIndex), max(0, files.count - 1)))
    }

    private var currentFile: MediaFile? {
        guard currentIndex >= 0 && currentIndex < files.count else { return nil }
        return files[currentIndex]
    }

    public var body: some View {
        ZStack {
            // Immersive black backdrop
            Color.black.ignoresSafeArea()

            // Paging Carousel
            TabView(selection: $currentIndex) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    MediaItemView(
                        file: file,
                        isActive: index == currentIndex,
                        onSingleTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showOverlay.toggle()
                            }
                        },
                        onDismissGesture: {
                            dismiss()
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear {
                currentIndex = initialIndex
            }

            // Metadata & Controls Overlay
            if showOverlay {
                VStack {
                    topOverlayBar
                    Spacer()
                    bottomOverlayBar
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .statusBarHidden(!showOverlay)
        .alert("Сохранение медиа", isPresented: $isShowingSaveAlert) {
            Button("ОК", role: .cancel) { }
        } message: {
            Text(saveAlertMessage ?? "")
        }
    }

    // MARK: - Overlay Bars

    private var topOverlayBar: some View {
        HStack(alignment: .center) {
            // Dismiss Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.leading, 16)

            Spacer()

            // Index Indicator (e.g. "3 из 15")
            if !files.isEmpty {
                Text("\(currentIndex + 1) из \(files.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
            }

            Spacer()

            // Save & Share Actions
            HStack(spacing: 16) {
                if let file = currentFile {
                    // Save to Photos (images and videos)
                    if file.isImage || file.isVideo {
                        Button {
                            if file.isVideo {
                                saveVideoToPhotos(file: file)
                            } else {
                                saveImageToPhotos(file: file)
                            }
                        } label: {
                            if isSavingMedia {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "arrow.down.to.line.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .disabled(isSavingMedia)
                    }

                    // Share Link
                    if let url = file.fullURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var bottomOverlayBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let file = currentFile {
                // File Name
                Text(file.displayname ?? file.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Technical Metadata: Dimensions, Size, Type
                HStack(spacing: 12) {
                    Label("\(file.width) × \(file.height)", systemImage: "aspectratio")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    Label(file.formattedSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))

                    if file.isVideo {
                        Label(file.duration ?? "WebM Video", systemImage: "video.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Save to Photos Action

    private func saveImageToPhotos(file: MediaFile) {
        guard let url = file.fullURL else {
            saveAlertMessage = "Неверный URL изображения."
            isShowingSaveAlert = true
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    await MainActor.run {
                        self.saveAlertMessage = "Не удалось декодировать изображение."
                        self.isShowingSaveAlert = true
                    }
                    return
                }

                let saver = ImageSaver { success, error in
                    Task { @MainActor in
                        if success {
                            self.saveAlertMessage = "Изображение успешно сохранено в Фото."
                        } else {
                            self.saveAlertMessage = "Ошибка сохранения: \(error?.localizedDescription ?? "Доступ запрещен")"
                        }
                        self.isShowingSaveAlert = true
                        self.activeImageSaver = nil
                    }
                }
                await MainActor.run {
                    self.activeImageSaver = saver
                }
                saver.saveImage(image)
            } catch {
                await MainActor.run {
                    self.saveAlertMessage = "Ошибка загрузки: \(error.localizedDescription)"
                    self.isShowingSaveAlert = true
                }
            }
        }
    }

    // MARK: - Save Video to Photos Action

    private func saveVideoToPhotos(file: MediaFile) {
        guard let url = file.fullURL else {
            saveAlertMessage = "Неверный URL видеофайла."
            isShowingSaveAlert = true
            return
        }

        isSavingMedia = true

        Task {
            do {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    await MainActor.run {
                        self.saveAlertMessage = "Доступ к Фото запрещен. Разрешите доступ в Настройках iOS."
                        self.isShowingSaveAlert = true
                        self.isSavingMedia = false
                    }
                    return
                }

                let (tempDownloadURL, _) = try await URLSession.shared.download(from: url)
                let tempDir = FileManager.default.temporaryDirectory
                let targetURL = tempDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: targetURL)
                try FileManager.default.moveItem(at: tempDownloadURL, to: targetURL)

                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: targetURL)
                }

                await MainActor.run {
                    self.saveAlertMessage = "Видео успешно сохранено в Фото."
                    self.isShowingSaveAlert = true
                    self.isSavingMedia = false
                }
            } catch {
                // Fallback for WebM on iOS: save to App Documents / Downloads
                let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
                let downloadsDir = docDir.appendingPathComponent("Downloads", isDirectory: true)
                try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
                let localDest = downloadsDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: localDest)

                if let (tempDownloadURL, _) = try? await URLSession.shared.download(from: url) {
                    try? FileManager.default.moveItem(at: tempDownloadURL, to: localDest)
                    await MainActor.run {
                        self.saveAlertMessage = "Видео сохранено в папку 'Файлы / Makaba / Downloads' (системная галерея iOS не поддерживает raw WebM напрямую)."
                        self.isShowingSaveAlert = true
                        self.isSavingMedia = false
                    }
                } else {
                    await MainActor.run {
                        self.saveAlertMessage = "Ошибка сохранения видео: \(error.localizedDescription)"
                        self.isShowingSaveAlert = true
                        self.isSavingMedia = false
                    }
                }
            }
        }
    }
}

// MARK: - Media Item View (Image / Video Switcher)

public struct MediaItemView: View {
    public let file: MediaFile
    public let isActive: Bool
    public let onSingleTap: () -> Void
    public let onDismissGesture: () -> Void

    @State private var isNSFWRevealed: Bool
    @State private var dismissOffset: CGFloat = 0
    @State private var isZoomed: Bool = false

    public init(
        file: MediaFile,
        isActive: Bool = true,
        onSingleTap: @escaping () -> Void,
        onDismissGesture: @escaping () -> Void
    ) {
        self.file = file
        self.isActive = isActive
        self.onSingleTap = onSingleTap
        self.onDismissGesture = onDismissGesture
        self._isNSFWRevealed = State(initialValue: file.nsfw != 1)
    }

    public var body: some View {
        ZStack {
            Group {
                if file.isVideo {
                    if let fullURL = file.fullURL {
                        WebMPlayerView(
                            url: fullURL,
                            autoPlay: true,
                            isLooping: true,
                            thumbnailURL: file.thumbnailURL,
                            title: file.displayname ?? file.name,
                            bottomInset: 72,
                            isActive: isActive && isNSFWRevealed,
                            onSingleTap: onSingleTap
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 44))
                                .foregroundColor(.orange)
                            Text("Неверный URL видеофайла")
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    ZoomableImageView(
                        file: file,
                        isZoomed: $isZoomed,
                        onSingleTap: onSingleTap,
                        onDismissGesture: onDismissGesture
                    )
                }
            }
            .blur(radius: (file.nsfw == 1 && !isNSFWRevealed) ? 28 : 0)
            .offset(y: dismissOffset)
            .gesture(
                isZoomed ? nil :
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let dy = value.translation.height
                        let dx = value.translation.width
                        // Track predominantly vertical swipe (both UP and DOWN)
                        if abs(dy) > abs(dx) {
                            dismissOffset = dy
                        }
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        let dx = value.translation.width
                        if abs(dy) > abs(dx) && (abs(dy) > 100 || abs(value.predictedEndTranslation.height) > 220) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dismissOffset = dy > 0 ? 1000 : -1000
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onDismissGesture()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dismissOffset = 0
                            }
                        }
                    }
            )

            // Fullscreen NSFW Shield
            if file.nsfw == 1 && !isNSFWRevealed {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)

                    Text("Деликатный контент (18+)")
                        .font(.headline)
                        .foregroundColor(.white)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isNSFWRevealed = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                            Text("Показать медиафайл")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(24)
            }
        }
    }
}

// MARK: - Zoomable Image View

public struct ZoomableImageView: View {
    public let file: MediaFile
    @Binding public var isZoomed: Bool
    public let onSingleTap: () -> Void
    public let onDismissGesture: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    public init(
        file: MediaFile,
        isZoomed: Binding<Bool> = .constant(false),
        onSingleTap: @escaping () -> Void,
        onDismissGesture: @escaping () -> Void = {}
    ) {
        self.file = file
        self._isZoomed = isZoomed
        self.onSingleTap = onSingleTap
        self.onDismissGesture = onDismissGesture
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let fullURL = file.fullURL {
                    AsyncImage(url: fullURL) { phase in
                        switch phase {
                        case .empty:
                            // Fallback to thumbnail while loading full resolution
                            if let thumbURL = file.thumbnailURL {
                                AsyncImage(url: thumbURL) { thumbPhase in
                                    if let thumbImage = thumbPhase.image {
                                        thumbImage
                                            .resizable()
                                            .scaledToFit()
                                    }
                                }
                            }
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                        case .success(let image):
                            applyGestures(
                                to: image
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(scale)
                                    .offset(offset),
                                proxy: proxy
                            )
                            .onTapGesture(count: 2) {
                                handleDoubleTap()
                            }
                            .onTapGesture(count: 1) {
                                onSingleTap()
                            }
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 36))
                                    .foregroundColor(.orange)
                                Text("Не удалось загрузить изображение")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Gestures & Bounding

    @ViewBuilder
    private func applyGestures<V: View>(to content: V, proxy: GeometryProxy) -> some View {
        if scale > 1.0 {
            content
                .highPriorityGesture(dragGesture(proxy: proxy))
                .gesture(magnificationGesture(proxy: proxy))
        } else {
            // When not zoomed, do not attach any drag gesture so horizontal paging is unhindered
            content
                .gesture(magnificationGesture(proxy: proxy))
        }
    }

    private func magnificationGesture(proxy: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = min(max(newScale, 1.0), 5.0)
                isZoomed = scale > 1.01
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    withAnimation(.spring()) {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                    isZoomed = false
                } else {
                    let maxOffsetX = max(0, (proxy.size.width * (scale - 1)) / 2)
                    let maxOffsetY = max(0, (proxy.size.height * (scale - 1)) / 2)
                    withAnimation(.spring()) {
                        offset = CGSize(
                            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
                            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
                        )
                        lastOffset = offset
                    }
                    isZoomed = true
                }
                lastScale = scale
            }
    }

    private func dragGesture(proxy: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1.0 {
                    let maxOffsetX = max(0, (proxy.size.width * (scale - 1)) / 2)
                    let maxOffsetY = max(0, (proxy.size.height * (scale - 1)) / 2)
                    let targetX = lastOffset.width + value.translation.width
                    let targetY = lastOffset.height + value.translation.height
                    offset = CGSize(
                        width: min(max(targetX, -maxOffsetX), maxOffsetX),
                        height: min(max(targetY, -maxOffsetY), maxOffsetY)
                    )
                } else if value.translation.height > 60 {
                    // Swipe down to dismiss
                    offset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if scale > 1.0 {
                    let maxOffsetX = max(0, (proxy.size.width * (scale - 1)) / 2)
                    let maxOffsetY = max(0, (proxy.size.height * (scale - 1)) / 2)
                    let targetX = lastOffset.width + value.translation.width
                    let targetY = lastOffset.height + value.translation.height
                    withAnimation(.spring()) {
                        offset = CGSize(
                            width: min(max(targetX, -maxOffsetX), maxOffsetX),
                            height: min(max(targetY, -maxOffsetY), maxOffsetY)
                        )
                        lastOffset = offset
                    }
                } else {
                    if value.translation.height > 120 {
                        onDismissGesture()
                    } else {
                        withAnimation(.spring()) {
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }
            }
    }

    private func handleDoubleTap() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if scale > 1.0 {
                scale = 1.0
                offset = .zero
                lastScale = 1.0
                lastOffset = .zero
                isZoomed = false
            } else {
                scale = 2.5
                lastScale = 2.5
                isZoomed = true
            }
        }
    }
}

// MARK: - Legacy Video Player Placeholder Hook

@available(*, deprecated, message: "Use WebMPlayerView instead")
public struct VideoPlayerContainerPlaceholder: View {
    public let file: MediaFile
    public let onSingleTap: () -> Void

    @State private var isPlayingPlaceholder: Bool = false

    public var body: some View {
        ZStack {
            // Video Thumbnail
            if let thumbURL = file.thumbnailURL {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "video.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Video Overlay Container Hook
            VStack(spacing: 16) {
                // Large Play Button
                Button {
                    isPlayingPlaceholder.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.9))
                            .frame(width: 72, height: 72)
                            .shadow(radius: 8)

                        Image(systemName: isPlayingPlaceholder ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .offset(x: isPlayingPlaceholder ? 0 : 2)
                    }
                }

                // Video Format & Milestone 4 Integration Badge
                VStack(spacing: 4) {
                    Text(file.type == .webm ? "WebM Video (VP9 / Opus)" : "MP4 Video")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    if let duration = file.duration {
                        Text("Длительность: \(duration)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Text("Интегрированный плеер готов к Milestone 4")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.75))
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSingleTap()
        }
    }
}

// MARK: - Image Saver Helper

private final class ImageSaver: NSObject {
    private static var activeSavers = Set<ImageSaver>()
    private let completion: (Bool, Error?) -> Void

    init(completion: @escaping (Bool, Error?) -> Void) {
        self.completion = completion
        super.init()
    }

    func saveImage(_ image: UIImage) {
        Self.activeSavers.insert(self)
        UIImageWriteToSavedPhotosAlbum(
            image,
            self,
            #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }

    @objc private func saveCompleted(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        completion(error == nil, error)
        Self.activeSavers.remove(self)
    }
}
