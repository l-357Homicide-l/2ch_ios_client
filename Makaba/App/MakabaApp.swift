//
//  MakabaApp.swift
//  Makaba
//
//  Main application entry point for the Makaba iOS client.
//

import SwiftUI

// Conform MakabaAPIClient to ObservableObject for SwiftUI environment injection
extension MakabaAPIClient: ObservableObject {}

@main
struct MakabaApp: App {
    // MARK: - Shared State Containers
    @StateObject private var apiClient = MakabaAPIClient()
    @StateObject private var favoritesManager = FavoritesManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiClient)
                .environmentObject(favoritesManager)
        }
    }
}
