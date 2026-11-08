//
//  EmojiCaptchaView.swift
//  Makaba
//
//  Interactive 3-step Emoji Captcha challenge resolution with
//  asynchronous SHA-512 Proof of Work computation and token binding.
//

import SwiftUI
import UIKit
import CryptoKit

// MARK: - Captcha Verification State

/// Detailed operational state of the Emoji Captcha lifecycle.
public enum CaptchaVerificationState: Equatable, Sendable {
    case idle
    case loadingChallenge
    case solvingPoW(template: String, limit: Int)
    case loadingImages(powResult: PoWResult)
    case ready(promptImage: UIImage, keyboardImages: [UIImage], round: Int, powResult: PoWResult)
    case submittingClick(index: Int, powResult: PoWResult)
    case verified(token: String, powResult: PoWResult)
    case bypassed(reason: String, type: String)
    case error(message: String)
    case banned(reason: String)
    case cooldown(secondsRemaining: Int)

    public static func == (lhs: CaptchaVerificationState, rhs: CaptchaVerificationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loadingChallenge, .loadingChallenge):
            return true
        case (.solvingPoW(let t1, let l1), .solvingPoW(let t2, let l2)):
            return t1 == t2 && l1 == l2
        case (.loadingImages(let r1), .loadingImages(let r2)):
            return r1 == r2
        case (.ready(_, _, let round1, let r1), .ready(_, _, let round2, let r2)):
            return round1 == round2 && r1 == r2
        case (.submittingClick(let i1, let r1), .submittingClick(let i2, let r2)):
            return i1 == i2 && r1 == r2
        case (.verified(let t1, let r1), .verified(let t2, let r2)):
            return t1 == t2 && r1 == r2
        case (.bypassed(let r1, let t1), .bypassed(let r2, let t2)):
            return r1 == r2 && t1 == t2
        case (.error(let m1), .error(let m2)):
            return m1 == m2
        case (.banned(let r1), .banned(let r2)):
            return r1 == r2
        case (.cooldown(let s1), .cooldown(let s2)):
            return s1 == s2
        default:
            return false
        }
    }
}

// MARK: - Emoji Captcha View Model

@MainActor
public final class EmojiCaptchaViewModel: ObservableObject {
    public let board: String
    public let thread: Int

    @Published public var state: CaptchaVerificationState = .idle
    @Published public var verifiedToken: String? = nil
    @Published public var powNonce: String? = nil
    @Published public var powDurationMs: Double? = nil
    @Published public var captchaType: String = "emoji_captcha"
    @Published public var isSolved: Bool = false
    @Published public var warningMessage: String? = nil
    @Published public var currentRound: Int = 1

    private let apiClient: MakabaAPIClient
    private var currentChallengeID: String? = nil
    private var currentPoWResult: PoWResult? = nil
    private var activeTask: Task<Void, Never>? = nil
    private var cooldownTimerTask: Task<Void, Never>? = nil

    public init(
        board: String,
        thread: Int = 0,
        apiClient: MakabaAPIClient = MakabaAPIClient()
    ) {
        self.board = board
        self.thread = thread
        self.apiClient = apiClient
    }

    deinit {
        activeTask?.cancel()
        cooldownTimerTask?.cancel()
    }

    /// Initiates or restarts the full captcha acquisition and PoW workflow.
    public func startVerification() {
        activeTask?.cancel()
        cooldownTimerTask?.cancel()

        self.verifiedToken = nil
        self.powNonce = nil
        self.powDurationMs = nil
        self.currentPoWResult = nil
        self.currentChallengeID = nil
        self.isSolved = false
        self.currentRound = 1
        self.warningMessage = nil

        activeTask = Task { [weak self] in
            guard let self = self else { return }
            await self.executeVerificationFlow()
        }
    }

    /// Primary multi-stage asynchronous verification pipeline.
    private func executeVerificationFlow() async {
        self.state = .loadingChallenge

        do {
            // Stage 1: Fetch challenge and JWE session token
            let challengeResponse = try await apiClient.fetchCaptcha(board: board, thread: thread)

            if let warning = challengeResponse.warning, !warning.isEmpty {
                self.warningMessage = warning
            }

            // Check moderation ban
            if let banReason = challengeResponse.banned, !banReason.isEmpty {
                self.state = .banned(reason: banReason)
                return
            }

            // Check VIP Passcode bypass
            if challengeResponse.isVIPBypass {
                self.captchaType = "passcode"
                self.isSolved = true
                self.state = .bypassed(reason: "VIP Passcode активен — капча пропущена", type: "passcode")
                return
            }

            // Check Captcha Disabled on board
            if challengeResponse.isCaptchaDisabled {
                self.captchaType = "nocaptcha"
                self.isSolved = true
                self.state = .bypassed(reason: "Капча отключена для данного раздела", type: "nocaptcha")
                return
            }

            // Check Rate-limit cooldown
            if challengeResponse.result == 4 || challengeResponse.result == -1 {
                self.startCooldownTimer(durationSeconds: 180)
                return
            }

            guard let challengeID = challengeResponse.id,
                  let powChallenge = challengeResponse.challenge else {
                throw MakabaAPIError.decodingError("Ответ сервера не содержит идентификатора сессии или PoW-задания.")
            }

            self.currentChallengeID = challengeID
            self.captchaType = "emoji_captcha"

            // Stage 2: Solve SHA-512 Proof of Work on background cooperative task
            self.state = .solvingPoW(template: powChallenge.template, limit: powChallenge.limit)

            let powResult = try await PoWSolver.solveAsync(
                template: powChallenge.template,
                targetHash: powChallenge.hash,
                limit: powChallenge.limit
            )

            self.currentPoWResult = powResult
            self.powNonce = String(powResult.nonce)
            self.powDurationMs = powResult.durationMs

            // Stage 3: Fetch visual puzzle images (prompt banner + 8 keyboard buttons)
            self.state = .loadingImages(powResult: powResult)

            let imagesResponse = try await apiClient.fetchCaptchaImages(id: challengeID)

            guard let promptData = imagesResponse.imageData,
                  let promptImage = UIImage(data: promptData) else {
                throw MakabaAPIError.decodingError("Не удалось декодировать фоновое изображение капчи.")
            }

            let keyboardImages = imagesResponse.keyboardData.compactMap { UIImage(data: $0) }
            guard keyboardImages.count >= 8 else {
                throw MakabaAPIError.decodingError("Клавиатура капчи вернула менее 8 символов (\(keyboardImages.count)).")
            }

            self.currentRound = 1
            self.state = .ready(
                promptImage: promptImage,
                keyboardImages: keyboardImages,
                round: 1,
                powResult: powResult
            )

        } catch is CancellationError {
            // Task cancelled gracefully
        } catch {
            self.state = .error(message: error.localizedDescription)
        }
    }

    /// Submits user's emoji selection (0-indexed button index).
    public func submitEmojiChoice(at index: Int) {
        guard case .ready(_, _, let round, let powResult) = state,
              let challengeID = currentChallengeID else {
            return
        }

        self.state = .submittingClick(index: index, powResult: powResult)

        activeTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                let clickResponse = try await self.apiClient.submitCaptchaClick(
                    tokenID: challengeID,
                    emojiNumber: index
                )

                // Check terminal success
                if clickResponse.isSuccess, let verifiedToken = clickResponse.verifiedToken {
                    self.verifiedToken = verifiedToken
                    self.isSolved = true
                    self.state = .verified(token: verifiedToken, powResult: powResult)
                    return
                }

                // Check intermediate subsequent round
                if clickResponse.hasMoreRounds,
                   let imageBase64 = clickResponse.image,
                   let imgData = Data(base64Encoded: imageBase64),
                   let promptImage = UIImage(data: imgData),
                   let keyboardBase64 = clickResponse.keyboard {

                    let keyboardImages = keyboardBase64.compactMap { b64 in
                        Data(base64Encoded: b64).flatMap { UIImage(data: $0) }
                    }

                    if keyboardImages.count >= 8 {
                        let nextRound = round + 1
                        self.currentRound = nextRound
                        self.state = .ready(
                            promptImage: promptImage,
                            keyboardImages: keyboardImages,
                            round: nextRound,
                            powResult: powResult
                        )
                        return
                    }
                }

                // If neither success nor valid round, server reset challenge or user clicked incorrectly
                self.state = .error(message: "Неверный выбор символа или сессия капчи сброшена сервером. Попробуйте снова.")

            } catch is CancellationError {
                // Task cancelled
            } catch {
                self.state = .error(message: "Ошибка проверки капчи: \(error.localizedDescription)")
            }
        }
    }

    public var resolvedNonce: String? {
        return powNonce
    }

    /// Starts a cooldown countdown when flood-protected by the server.
    private func startCooldownTimer(durationSeconds: Int) {
        cooldownTimerTask?.cancel()
        cooldownTimerTask = Task { [weak self] in
            var remaining = durationSeconds
            while remaining > 0 {
                guard !Task.isCancelled else { break }
                self?.state = .cooldown(secondsRemaining: remaining)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                remaining -= 1
            }
            // Once cooldown finishes, auto-restart verification if task was not cancelled
            if !Task.isCancelled {
                self?.startVerification()
            }
        }
    }

    /// User action to refresh challenge manually.
    public func refresh() {
        startVerification()
    }
}

// MARK: - Emoji Captcha View

public struct EmojiCaptchaView: View {
    @ObservedObject public var viewModel: EmojiCaptchaViewModel

    // Optional external two-way bindings for direct parent form synchronisation
    private var externalVerifiedToken: Binding<String?>?
    private var externalPowNonce: Binding<String?>?
    private var externalCaptchaType: Binding<String?>?
    private var externalIsSolved: Binding<Bool>?

    public init(
        viewModel: EmojiCaptchaViewModel,
        verifiedToken: Binding<String?>? = nil,
        powNonce: Binding<String?>? = nil,
        captchaType: Binding<String?>? = nil,
        isSolved: Binding<Bool>? = nil
    ) {
        self.viewModel = viewModel
        self.externalVerifiedToken = verifiedToken
        self.externalPowNonce = powNonce
        self.externalCaptchaType = captchaType
        self.externalIsSolved = isSolved
    }

    public init(
        board: String,
        thread: Int = 0,
        apiClient: MakabaAPIClient = MakabaAPIClient(),
        verifiedToken: Binding<String?>? = nil,
        powNonce: Binding<String?>? = nil,
        captchaType: Binding<String?>? = nil,
        isSolved: Binding<Bool>? = nil
    ) {
        self.init(
            viewModel: EmojiCaptchaViewModel(board: board, thread: thread, apiClient: apiClient),
            verifiedToken: verifiedToken,
            powNonce: powNonce,
            captchaType: captchaType,
            isSolved: isSolved
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card Header
            headerView

            // Warning Notice (if any)
            if let warning = viewModel.warningMessage {
                warningBanner(warning)
            }

            // PoW Solution Badge (displayed once computed)
            if let powNonce = viewModel.powNonce, let powDuration = viewModel.powDurationMs {
                powSolvedBadge(nonce: powNonce, durationMs: powDuration)
            }

            // Content Area Based on State
            contentView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .onAppear {
            if viewModel.state == .idle {
                viewModel.startVerification()
            }
        }
        .onChange(of: viewModel.verifiedToken) { token in
            externalVerifiedToken?.wrappedValue = token
        }
        .onChange(of: viewModel.powNonce) { nonce in
            externalPowNonce?.wrappedValue = nonce
        }
        .onChange(of: viewModel.captchaType) { cType in
            externalCaptchaType?.wrappedValue = cType
        }
        .onChange(of: viewModel.isSolved) { solved in
            externalIsSolved?.wrappedValue = solved
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "face.smiling.inverse")
                    .foregroundColor(.orange)
                    .font(.system(size: 16, weight: .semibold))

                Text("Проверка: Emoji Captcha")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Refresh Challenge Button
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                viewModel.refresh()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text("Обновить")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)
        }
    }

    // MARK: - PoW Solved Status Badge

    private func powSolvedBadge(nonce: String, durationMs: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)

            Text("PoW Решен: nonce \(nonce) в \(String(format: "%.1f", durationMs))мс")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Warning Banner

    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 14))
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - State-Dependent Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle, .loadingChallenge:
            loadingPlaceholder(title: "Получение капчи...", subtitle: "Запрос сессионного JWE-токена с сервера 2ch.org")

        case .solvingPoW:
            loadingPlaceholder(title: "Вычисление SHA-512 PoW...", subtitle: "Параллельный поиск прообраза в CryptoKit")

        case .loadingImages:
            loadingPlaceholder(title: "Загрузка символов...", subtitle: "Получение графического задания")

        case .ready(let promptImage, let keyboardImages, let round, _):
            interactivePuzzleView(prompt: promptImage, keyboard: keyboardImages, round: round)

        case .submittingClick:
            submittingOverlay

        case .verified(let token, let powResult):
            verifiedSuccessView(token: token, powResult: powResult)

        case .bypassed(let reason, _):
            bypassedView(reason: reason)

        case .error(let message):
            errorView(message: message)

        case .banned(let reason):
            bannedView(reason: reason)

        case .cooldown(let remaining):
            cooldownView(remaining: remaining)
        }
    }

    // MARK: - Interactive Puzzle View

    private func interactivePuzzleView(prompt: UIImage, keyboard: [UIImage], round: Int) -> some View {
        VStack(spacing: 12) {
            // Instruction header
            HStack {
                Text("Шаг \(round). Нажмите на символ, показанный на баннере:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Challenge Prompt Image
            Image(uiImage: prompt)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .padding(4)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            // 8-Button Emoji Grid (2 rows of 4 columns)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<min(keyboard.count, 8), id: \.self) { index in
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        viewModel.submitEmojiChoice(at: index)
                    } label: {
                        Image(uiImage: keyboard[index])
                            .resizable()
                            .scaledToFit()
                            .frame(width: 38, height: 38)
                            .padding(6)
                            .background(Color(UIColor.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(EmojiGridButtonStyle())
                }
            }
        }
    }

    // MARK: - Submitting Overlay

    private var submittingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(1.1)
                .tint(.orange)
            Text("Проверка выбора символа...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Verified Success View

    private func verifiedSuccessView(token: String, powResult: PoWResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Капча успешно пройдена")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)

                Text("Токен: \(token.prefix(20))...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Bypassed View

    private func bypassedView(reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 24))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Проверка не требуется")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)

                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundColor(.red)
                Text("Ошибка капчи")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
            }

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                viewModel.refresh()
            } label: {
                Label("Попробовать снова", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Banned View

    private func bannedView(reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 26))
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Доступ заблокирован модерацией")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)

                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Cooldown View

    private func cooldownView(remaining: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 24))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Таймаут отправки (флуд-защита)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Повторная попытка через \(remaining) сек.")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Loading Placeholder

    private func loadingPlaceholder(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .loadingChallenge, .solvingPoW, .loadingImages, .submittingClick:
            return true
        default:
            return false
        }
    }
}

// MARK: - Emoji Grid Button Style

private struct EmojiGridButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
