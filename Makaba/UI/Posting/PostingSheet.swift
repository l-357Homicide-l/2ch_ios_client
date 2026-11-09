//
//  PostingSheet.swift
//  Makaba
//
//  Production posting sheet for replying to threads and creating new threads
//  with markup helpers, sage toggle, file attachments, and embedded Emoji Captcha.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Combine

// MARK: - Attached Media Item

/// Represents a media file queued for multipart upload.
public struct PostingAttachmentItem: Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let mimeType: String
    public let data: Data
    public let isVideo: Bool
    public let fileSizeFormatted: String

    public init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        data: Data,
        isVideo: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.isVideo = isVideo
        self.fileSizeFormatted = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    public var asPostFileAttachment: PostFileAttachment {
        PostFileAttachment(fileName: fileName, mimeType: mimeType, data: data)
    }
}

// MARK: - Posting View Model

@MainActor
public final class PostingViewModel: ObservableObject {
    public static let defaultMaxFileSizeBytes: Int = 20 * 1024 * 1024 // 20 MB per file
    public static let maxAttachmentsCount: Int = 4

    public let board: String
    public let threadNum: Int? // nil or 0 for new thread creation
    public let replyToPostNum: Int?
    public let threadTitle: String?
    public let boardModel: Board?

    // Dynamic Board Limits
    public var maxCommentLimit: Int {
        boardModel?.maxComment ?? 15000
    }
    public var maxFileSizeBytes: Int {
        if let limitKB = boardModel?.maxFilesSize, limitKB > 0 {
            return limitKB * 1024
        }
        return Self.defaultMaxFileSizeBytes
    }

    // Form Fields
    @Published public var subject: String = "" {
        didSet { saveDraft() }
    }
    @Published public var comment: String = "" {
        didSet { saveDraft() }
    }
    @Published public var name: String = "" {
        didSet { saveDraft() }
    }
    @Published public var email: String = "" {
        didSet { saveDraft() }
    }
    @Published public var isSage: Bool = false
    @Published public var isOPMark: Bool = false
    @Published public var attachments: [PostingAttachmentItem] = []

    // Captcha ViewModel (Single Source of Truth)
    @Published public var captchaViewModel: EmojiCaptchaViewModel

    public var verifiedCaptchaToken: String? {
        captchaViewModel.verifiedToken
    }
    public var powNonce: String? {
        captchaViewModel.resolvedNonce ?? captchaViewModel.powNonce
    }
    public var captchaType: String? {
        captchaViewModel.captchaType
    }
    public var isCaptchaSolved: Bool {
        captchaViewModel.isSolved
    }
    public var isCaptchaExpired: Bool {
        captchaViewModel.tokenExpiresInSeconds == 0
    }

    // State & UI feedback
    @Published public var isSubmitting: Bool = false
    @Published public var submissionSuccess: PostingResponse? = nil
    @Published public var errorMessage: String? = nil
    @Published public var showAdvancedOptions: Bool = false

    private let apiClient: MakabaAPIClient
    private var cancellables = Set<AnyCancellable>()

    private var draftKey: String {
        "MakabaDraft_\(board)_\(threadNum ?? 0)"
    }

    public init(
        board: String,
        threadNum: Int? = nil,
        replyToPostNum: Int? = nil,
        threadTitle: String? = nil,
        boardModel: Board? = nil,
        apiClient: MakabaAPIClient = .shared
    ) {
        self.board = board
        self.threadNum = threadNum
        self.replyToPostNum = replyToPostNum
        self.threadTitle = threadTitle
        self.boardModel = boardModel
        self.apiClient = apiClient

        let captchaVM = EmojiCaptchaViewModel(
            board: board,
            thread: threadNum ?? 0,
            apiClient: apiClient
        )
        self.captchaViewModel = captchaVM

        // Restore draft or pre-fill quote
        loadDraft()
        if self.comment.isEmpty, let replyNum = replyToPostNum {
            self.comment = ">>\(replyNum)\n"
        }

    }

    // MARK: - Draft Management

    private var draftSaveTask: Task<Void, Never>?

    public func saveDraft() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self = self else { return }
            self.persistDraftNow()
        }
    }

    public func persistDraftNow() {
        guard !comment.isEmpty || !subject.isEmpty else { return }
        let dict: [String: String] = [
            "comment": comment,
            "subject": subject,
            "name": name,
            "email": email
        ]
        UserDefaults.standard.set(dict, forKey: draftKey)
    }

    public func loadDraft() {
        guard let dict = UserDefaults.standard.dictionary(forKey: draftKey) as? [String: String] else { return }
        if let savedComment = dict["comment"], !savedComment.isEmpty {
            self.comment = savedComment
        }
        if let savedSubject = dict["subject"], !savedSubject.isEmpty {
            self.subject = savedSubject
        }
        if let savedName = dict["name"], !savedName.isEmpty {
            self.name = savedName
        }
        if let savedEmail = dict["email"], !savedEmail.isEmpty {
            self.email = savedEmail
        }
    }

    public func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    /// Whether this sheet is creating a new thread rather than replying.
    public var isNewThread: Bool {
        return threadNum == nil || threadNum == 0
    }

    /// Whether all validation criteria are met for submission.
    public var isFormValid: Bool {
        let hasContent = !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        guard hasContent else { return false }
        guard comment.count <= maxCommentLimit else { return false }
        guard isCaptchaSolved || captchaViewModel.isSolved else { return false }
        guard attachments.count <= Self.maxAttachmentsCount else { return false }
        let totalBytes = attachments.reduce(0) { $0 + $1.data.count }
        if totalBytes > maxFileSizeBytes { return false }
        for att in attachments {
            if att.data.count > maxFileSizeBytes { return false }
        }
        return true
    }

    /// Localized validation hint when submission is attempted without meeting criteria.
    public var validationErrorMessage: String? {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && attachments.isEmpty {
            return "Введите текст сообщения или прикрепите хотя бы один файл."
        }
        if comment.count > maxCommentLimit {
            return "Длина сообщения превышает лимит (\(maxCommentLimit) символов)."
        }
        if !isCaptchaSolved && !captchaViewModel.isSolved {
            return "Пройдите проверку капчи перед отправкой."
        }
        if attachments.count > Self.maxAttachmentsCount {
            return "Максимальное количество прикрепленных файлов — 4."
        }
        let totalBytes = attachments.reduce(0) { $0 + $1.data.count }
        if totalBytes > maxFileSizeBytes {
            return "Суммарный размер файлов (\(totalBytes / (1024 * 1024)) МБ) превышает допустимый лимит (\(maxFileSizeBytes / (1024 * 1024)) МБ)."
        }
        for att in attachments {
            if att.data.count > maxFileSizeBytes {
                return "Файл «\(att.fileName)» превышает лимит \(maxFileSizeBytes / (1024 * 1024)) МБ."
            }
        }
        return nil
    }

    /// Appends a new attachment respecting the maximum 4 files and file size limits.
    @discardableResult
    public func addAttachment(_ item: PostingAttachmentItem) -> Bool {
        guard attachments.count < Self.maxAttachmentsCount else {
            self.errorMessage = "Максимальное количество прикрепленных файлов — 4."
            return false
        }
        guard item.data.count <= maxFileSizeBytes else {
            self.errorMessage = "Файл «\(item.fileName)» превышает допустимый лимит (\(item.fileSizeFormatted))."
            return false
        }
        let totalBytes = attachments.reduce(0) { $0 + $1.data.count } + item.data.count
        guard totalBytes <= maxFileSizeBytes else {
            self.errorMessage = "Суммарный размер файлов превышает допустимый лимит (\(maxFileSizeBytes / (1024 * 1024)) МБ)."
            return false
        }
        attachments.append(item)
        self.errorMessage = nil
        return true
    }

    /// Removes an attachment by UUID.
    public func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    /// Submits the post payload via RFC 7578 multipart/form-data.
    public func submitPost() async -> PostingResponse? {
        guard isFormValid else {
            self.errorMessage = validationErrorMessage
            return nil
        }

        self.isSubmitting = true
        self.errorMessage = nil

        let effectiveEmail = isSage ? "sage" : (email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email)

        // Read verified token, nonce, and captcha type directly from captchaViewModel
        let effectiveCaptchaToken = captchaViewModel.verifiedToken ?? verifiedCaptchaToken
        let effectiveChallenge = captchaViewModel.resolvedNonce ?? captchaViewModel.powNonce ?? powNonce
        let rawCaptchaType = captchaViewModel.captchaType
        let effectiveCaptchaType = rawCaptchaType.isEmpty ? (captchaType ?? "emoji_captcha") : rawCaptchaType

        let payload = PostPayload(
            board: board,
            thread: threadNum ?? 0,
            comment: comment.isEmpty ? nil : comment,
            challenge: effectiveChallenge,
            captchaType: effectiveCaptchaType,
            emojiCaptchaID: effectiveCaptchaToken,
            usercode: apiClient.passcodeToken,
            email: effectiveEmail,
            sage: isSage,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subject,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name,
            opMark: isOPMark,
            files: attachments.map { $0.asPostFileAttachment }
        )

        do {
            let result = try await apiClient.submitPost(payload: payload)

            // If server returned non-throwing result with error code -5 (captcha error / expired)
            if !result.isSuccess, let code = result.error?.code, code == -5 {
                self.captchaViewModel.refresh()
                self.errorMessage = result.errorMessage ?? "Ошибка капчи (код -5). Пройдите капчу заново."
                self.isSubmitting = false
                return nil
            }

            self.submissionSuccess = result
            if let postNum = result.targetID {
                UserPostTracker.shared.recordOwnPost(board: board, num: postNum)
            }
            self.clearDraft()
            await apiClient.invalidateThreadCache(board: board, threadNum: threadNum ?? (result.targetID ?? 0))
            await apiClient.invalidateCatalogCache(board: board)
            self.isSubmitting = false
            return result
        } catch let apiError as MakabaAPIError {
            self.isSubmitting = false
            self.errorMessage = apiError.localizedDescription

            if case .serverError(let code, _) = apiError, code == -5 {
                // Captcha error or expired: reset solved state and refresh captcha
                self.captchaViewModel.refresh()
            }
            return nil
        } catch {
            self.isSubmitting = false
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Submits the post payload via RFC 7578 multipart/form-data.
    public func submit() async -> PostingResponse? {
        await submitPost()
    }
}

// MARK: - Posting Sheet View

public struct PostingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PostingViewModel

    public var onPostSuccess: ((PostingResponse) -> Void)?

    // File picking states
    @State private var selectedPhotosItems: [PhotosPickerItem] = []
    @State private var isFileImporterPresented: Bool = false
    @FocusState private var isCommentFocused: Bool

    public init(
        board: String,
        threadNum: Int? = nil,
        replyToPostNum: Int? = nil,
        threadTitle: String? = nil,
        boardModel: Board? = nil,
        apiClient: MakabaAPIClient = .shared,
        onPostSuccess: ((PostingResponse) -> Void)? = nil
    ) {
        self._viewModel = StateObject(
            wrappedValue: PostingViewModel(
                board: board,
                threadNum: threadNum,
                replyToPostNum: replyToPostNum,
                threadTitle: threadTitle,
                boardModel: boardModel,
                apiClient: apiClient
            )
        )
        self.onPostSuccess = onPostSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header Info Banner
                        targetHeaderView

                        // Subject Field (Primary when creating thread, optional when replying)
                        if viewModel.isNewThread || viewModel.showAdvancedOptions {
                            subjectField
                        }

                        // Comment Editor & Formatting Helpers
                        commentEditorSection

                        // Embedded Emoji Captcha Section (Positioned right under comment so user sees and solves it immediately)
                        captchaSection

                        // Media Attachments Section
                        attachmentsSection

                        // Quick Options: Sage & OP Mark & Advanced Toggle
                        togglesSection

                        // Advanced Metadata (Name, Custom Email)
                        if viewModel.showAdvancedOptions {
                            advancedFieldsSection
                        }

                        // Error message banner
                        if let error = viewModel.errorMessage {
                            errorMessageView(error)
                        }

                        // Bottom Submit Button
                        submitButtonView
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // Submitting Progress Overlay
                if viewModel.isSubmitting {
                    submittingProgressOverlay
                }

                // Success Modal Notification
                if let success = viewModel.submissionSuccess {
                    successOverlay(success: success)
                }
            }
            .navigationTitle(viewModel.isNewThread ? "Новый тред" : "Ответ в тред")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .disabled(viewModel.isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        triggerSubmit()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isSubmitting)
                    .opacity(viewModel.isFormValid ? 1.0 : 0.6)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image, .movie, .video],
                allowsMultipleSelection: true
            ) { result in
                handleFileImporterResult(result)
            }
            .onValueChange(of: selectedPhotosItems) { newItems in
                handlePhotosSelection(newItems)
            }
            .task {
                if viewModel.captchaViewModel.state == .idle {
                    viewModel.captchaViewModel.startVerification()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSubmitting)
    }

    // MARK: - Header Info View

    private var targetHeaderView: some View {
        HStack(spacing: 8) {
            Text("/\(viewModel.board)/")
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if viewModel.isNewThread {
                Text("Создание нового треда")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            } else if let threadNum = viewModel.threadNum {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Тред #\(threadNum)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    if let title = viewModel.threadTitle {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    // MARK: - Subject Field

    private var subjectField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Тема")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            TextField(viewModel.isNewThread ? "Тема треда (до 64 символов)" : "Тема (опционально)", text: $viewModel.subject)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Comment Editor Section

    private var commentEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Formatting Toolbar
            formattingToolbar

            // TextEditor with Custom Placeholder
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.comment)
                    .focused($isCommentFocused)
                    .frame(minHeight: 120, maxHeight: 220)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                if viewModel.comment.isEmpty {
                    Text("Текст сообщения...")
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            // Character Counter
            HStack {
                Spacer()
                Text("\(viewModel.comment.count) / 15000")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(viewModel.comment.count > 15000 ? .red : .secondary)
            }
        }
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                markupButton(label: ">", hint: "Цитата") {
                    insertMarkupPrefix("> ")
                }

                markupButton(label: ">>", hint: "Ссылка") {
                    if let replyNum = viewModel.replyToPostNum {
                        insertMarkupText(">>\(replyNum) ")
                    } else {
                        insertMarkupText(">>")
                    }
                }

                markupButton(label: "%%", hint: "Спойлер") {
                    wrapSelection("%%", "%%")
                }

                markupButton(label: "**B**", hint: "Жирный") {
                    wrapSelection("**", "**")
                }

                markupButton(label: "*I*", hint: "Курсив") {
                    wrapSelection("*", "*")
                }

                markupButton(label: "_U_", hint: "Подчеркивание") {
                    wrapSelection("_", "_")
                }

                markupButton(label: "~S~", hint: "Зачеркивание") {
                    wrapSelection("<s>", "</s>")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func markupButton(label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(hint)
    }

    private func insertMarkupPrefix(_ prefix: String) {
        if viewModel.comment.isEmpty || viewModel.comment.hasSuffix("\n") {
            viewModel.comment += prefix
        } else {
            viewModel.comment += "\n\(prefix)"
        }
    }

    private func insertMarkupText(_ text: String) {
        viewModel.comment += text
    }

    private func wrapSelection(_ leading: String, _ trailing: String) {
        if viewModel.comment.isEmpty {
            viewModel.comment = "\(leading)\(trailing)"
        } else {
            let needsSpace = !viewModel.comment.hasSuffix(" ") && !viewModel.comment.hasSuffix("\n")
            viewModel.comment += (needsSpace ? " " : "") + "\(leading)\(trailing)"
        }
    }

    // MARK: - Media Attachments Section

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Прикрепленные файлы (\(viewModel.attachments.count)/4)", systemImage: "paperclip")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Photos Picker Launcher
                PhotosPicker(
                    selection: $selectedPhotosItems,
                    maxSelectionCount: 4 - viewModel.attachments.count,
                    matching: .any(of: [.images, .videos])
                ) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Медиатека")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                }
                .disabled(viewModel.attachments.count >= 4)

                // Files / iCloud Drive Launcher
                Button {
                    isFileImporterPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Файл")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                }
                .disabled(viewModel.attachments.count >= 4)
            }

            if !viewModel.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.attachments) { item in
                            attachmentCard(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func attachmentCard(_ item: PostingAttachmentItem) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                // Preview thumbnail or video placeholder
                Group {
                    if item.isVideo {
                        ZStack {
                            Color.black.opacity(0.85)
                            Image(systemName: "video.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    } else if let uiImage = UIImage(data: item.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay(Image(systemName: "doc.fill").foregroundColor(.secondary))
                    }
                }
                .frame(width: 88, height: 88)
                .clipped()
                .cornerRadius(8)

                // Filename and size
                Text(item.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 88, alignment: .leading)

                Text(item.fileSizeFormatted)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            // Remove attachment button
            Button {
                viewModel.removeAttachment(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .offset(x: 4, y: -4)
        }
    }

    // MARK: - Options & Toggles Section

    private var togglesSection: some View {
        VStack(spacing: 10) {
            HStack {
                // Sage Toggle
                Toggle(isOn: $viewModel.isSage) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.right.circle.fill")
                            .foregroundColor(viewModel.isSage ? .red : .secondary)
                        Text("Sage")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(viewModel.isSage ? .red : .primary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .red))

                Spacer(minLength: 20)

                // OP Mark Toggle (if replying)
                if !viewModel.isNewThread {
                    Toggle(isOn: $viewModel.isOPMark) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .foregroundColor(viewModel.isOPMark ? .orange : .secondary)
                            Text("OP")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                }
            }

            // Toggle Advanced Metadata
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showAdvancedOptions.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.showAdvancedOptions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(viewModel.showAdvancedOptions ? "Скрыть доп. параметры" : "Дополнительные параметры (имя, email)")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    // MARK: - Advanced Fields Section

    private var advancedFieldsSection: some View {
        VStack(spacing: 10) {
            TextField("Имя (по умолчанию Аноним)", text: $viewModel.name)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

            TextField("Email / Спецтеги", text: $viewModel.email)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding(10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .disabled(viewModel.isSage) // Sage overrides email field
        }
    }

    // MARK: - Captcha Section

    private var captchaSection: some View {
        EmojiCaptchaView(
            viewModel: viewModel.captchaViewModel
        )
    }

    // MARK: - Error Message View

    private func errorMessageView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Bottom Submit Button

    private var submitButtonView: some View {
        Button {
            triggerSubmit()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }

                Text(viewModel.isSubmitting ? "Отправка..." : (viewModel.isNewThread ? "Создать тред" : "Отправить ответ"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(.white)
            .background(viewModel.isFormValid ? Color.orange : Color.orange.opacity(0.65))
            .cornerRadius(12)
            .shadow(color: viewModel.isFormValid ? Color.orange.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .disabled(viewModel.isSubmitting)
    }

    // MARK: - Submitting Progress Overlay

    private var submittingProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Отправка сообщения на 2ch.org...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.95))
            .cornerRadius(16)
            .shadow(radius: 12)
        }
    }

    // MARK: - Success Modal Overlay

    private func successOverlay(success: PostingResponse) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.green)

                Text(viewModel.isNewThread ? "Тред успешно создан!" : "Ответ опубликован!")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                if let targetID = success.targetID {
                    Text("Номер сообщения: #\(targetID)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Text("Закрытие...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(28)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(18)
            .shadow(radius: 16)
        }
        .onAppear {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onPostSuccess?(success)
                dismiss()
            }
        }
    }

    // MARK: - Actions & Media Import Handlers

    private func triggerSubmit() {
        if !viewModel.isFormValid {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.warning)
            viewModel.errorMessage = viewModel.validationErrorMessage
            return
        }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        Task {
            if let result = await viewModel.submit() {
                // Handled in success overlay
            } else {
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
            }
        }
    }

    private static func sanitizeAndConvertMedia(rawData: Data, isVideo: Bool, rawExtension: String) -> (data: Data, ext: String, mime: String) {
        return MediaTranscoder.sanitizeMedia(rawData: rawData, isVideo: isVideo, rawExtension: rawExtension)
    }

    private func handlePhotosSelection(_ items: [PhotosPickerItem]) {
        Task.detached(priority: .userInitiated) {
            for item in items {
                let hasCapacity = await MainActor.run {
                    viewModel.attachments.count < PostingViewModel.maxAttachmentsCount
                }
                guard hasCapacity else { break }

                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let uti = item.supportedContentTypes.first
                let isVideo = uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true
                let rawExt = uti?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")

                // Sanitize media, convert HEIC to JPEG, strip GPS/EXIF
                let (sanitizedData, ext, mime) = Self.sanitizeAndConvertMedia(
                    rawData: data,
                    isVideo: isVideo,
                    rawExtension: rawExt
                )

                let count = await MainActor.run { viewModel.attachments.count }
                let fileName = "photo_\(Int(Date().timeIntervalSince1970))_\(count + 1).\(ext)"

                let attachment = PostingAttachmentItem(
                    fileName: fileName,
                    mimeType: mime,
                    data: sanitizedData,
                    isVideo: isVideo
                )

                await MainActor.run {
                    _ = viewModel.addAttachment(attachment)
                }
            }
            // Clear picker items to avoid re-importing on subsequent opens
            await MainActor.run {
                self.selectedPhotosItems.removeAll()
            }
        }
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task.detached(priority: .userInitiated) {
                for url in urls {
                    let hasCapacity = await MainActor.run {
                        viewModel.attachments.count < PostingViewModel.maxAttachmentsCount
                    }
                    guard hasCapacity else { break }

                    guard url.startAccessingSecurityScopedResource() else { continue }

                    let fileData: Data?
                    do {
                        fileData = try Data(contentsOf: url)
                    } catch {
                        fileData = nil
                    }
                    url.stopAccessingSecurityScopedResource()

                    guard let data = fileData else { continue }

                    let rawExt = url.pathExtension.lowercased()
                    let isVideo = ["mp4", "webm", "mov", "m4v"].contains(rawExt)

                    // Sanitize media, convert HEIC to JPEG, strip GPS/EXIF
                    let (sanitizedData, ext, mime) = Self.sanitizeAndConvertMedia(
                        rawData: data,
                        isVideo: isVideo,
                        rawExtension: rawExt
                    )

                    let fileName = url.deletingPathExtension().lastPathComponent + ".\(ext)"

                    let attachment = PostingAttachmentItem(
                        fileName: fileName,
                        mimeType: mime,
                        data: sanitizedData,
                        isVideo: isVideo
                    )

                    await MainActor.run {
                        _ = viewModel.addAttachment(attachment)
                    }
                }
            }
        case .failure(let error):
            viewModel.errorMessage = "Ошибка импорта файла: \(error.localizedDescription)"
        }
    }
}
