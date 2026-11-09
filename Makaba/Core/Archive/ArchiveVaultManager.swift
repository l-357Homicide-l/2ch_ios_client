//
//  ArchiveVaultManager.swift
//  Makaba
//
//  Offline 404 Thread Vault preserving expired or user-archived imageboard threads.
//

import Foundation

public struct VaultThreadItem: Identifiable, Sendable {
    public var id: String { "\(board)_\(threadNum)" }
    public let board: String
    public let threadNum: Int
    public let title: String
    public let postsCount: Int
    public let savedAt: Date
    public let sizeOnDiskBytes: Int64
}

/// Actor-isolated thread-safe manager for offline thread preservation and 404 recovery.
public actor ArchiveVaultManager {
    public static let shared = ArchiveVaultManager()

    private let fileManager = FileManager.default
    private let vaultDirectoryURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.vaultDirectoryURL = appSupport.appendingPathComponent("Makaba/Vault", isDirectory: true)

        if !fileManager.fileExists(atPath: vaultDirectoryURL.path) {
            try? fileManager.createDirectory(at: vaultDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func threadFileURL(board: String, threadNum: Int) -> URL {
        let boardDir = vaultDirectoryURL.appendingPathComponent(board.lowercased(), isDirectory: true)
        if !fileManager.fileExists(atPath: boardDir.path) {
            try? fileManager.createDirectory(at: boardDir, withIntermediateDirectories: true)
        }
        return boardDir.appendingPathComponent("\(threadNum).json")
    }

    /// Saves a full thread response into the offline vault.
    public func saveThread(board: String, threadNum: Int, response: ThreadResponse) async throws {
        let fileURL = threadFileURL(board: board, threadNum: threadNum)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(response)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Loads a saved thread from the offline vault if present.
    public func loadThread(board: String, threadNum: Int) -> ThreadResponse? {
        let fileURL = threadFileURL(board: board, threadNum: threadNum)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(ThreadResponse.self, from: data)
    }

    /// Checks whether a thread exists in the offline vault.
    public func hasThread(board: String, threadNum: Int) -> Bool {
        let fileURL = threadFileURL(board: board, threadNum: threadNum)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Lists all archived threads across all boards currently in the vault.
    public func listArchivedThreads() -> [VaultThreadItem] {
        guard let boardDirs = try? fileManager.contentsOfDirectory(
            at: vaultDirectoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var items: [VaultThreadItem] = []

        for boardDir in boardDirs where boardDir.hasDirectoryPath {
            let board = boardDir.lastPathComponent
            guard let threadFiles = try? fileManager.contentsOfDirectory(
                at: boardDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for threadFile in threadFiles where threadFile.pathExtension == "json" {
                let filename = threadFile.deletingPathExtension().lastPathComponent
                guard let threadNum = Int(filename) else { continue }

                let values = try? threadFile.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                let date = values?.contentModificationDate ?? Date()

                var title = "Тред #\(threadNum)"
                var count = 0
                if let data = try? Data(contentsOf: threadFile),
                   let decoded = try? JSONDecoder().decode(ThreadResponse.self, from: data) {
                    count = decoded.posts.count
                    if let first = decoded.posts.first {
                        let plain = MakabaHTMLParser.toPlainText(html: first.comment)
                        title = first.displaySubject.isEmpty ? (plain.isEmpty ? "Тред #\(threadNum)" : String(plain.prefix(40))) : first.displaySubject
                    }
                }

                items.append(VaultThreadItem(
                    board: board,
                    threadNum: threadNum,
                    title: title,
                    postsCount: count,
                    savedAt: date,
                    sizeOnDiskBytes: size
                ))
            }
        }

        return items.sorted { $0.savedAt > $1.savedAt }
    }

    /// Deletes a preserved thread from the vault.
    public func deleteThread(board: String, threadNum: Int) {
        let fileURL = threadFileURL(board: board, threadNum: threadNum)
        try? fileManager.removeItem(at: fileURL)
    }
}
