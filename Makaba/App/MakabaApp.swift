//
//  MakabaApp.swift
//  Makaba
//
//  Main application entry point for the Makaba iOS client.
//

import SwiftUI

@main
struct MakabaApp: App {
    // MARK: - Shared State Containers
    @StateObject private var apiClient = MakabaAPIClient.shared
    @StateObject private var favoritesManager = FavoritesManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiClient)
                .environmentObject(favoritesManager)
        }
    }
}
