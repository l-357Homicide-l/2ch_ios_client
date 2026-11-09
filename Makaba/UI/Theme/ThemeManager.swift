//
//  ThemeManager.swift
//  Makaba
//
//  Display themes management including True Black OLED palette for Super Retina displays.
//

import SwiftUI

public enum AppThemeMode: String, CaseIterable, Identifiable {
    case system = "Системная"
    case light = "Светлая"
    case dark = "Тёмная"
    case trueBlack = "OLED Чёрная"

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .trueBlack: return .dark
        }
    }
}

public enum AccentThemeColor: String, CaseIterable, Identifiable {
    case classicOrange = "Классический Оранжевый"
    case cyberGreen = "Кибер-Зелёный"
    case neonCyan = "Неоновый Голубой"
    case deepPurple = "Фиолетовый"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .classicOrange: return Color(red: 1.0, green: 0.45, blue: 0.0)
        case .cyberGreen: return Color(red: 0.1, green: 0.85, blue: 0.3)
        case .neonCyan: return Color(red: 0.0, green: 0.75, blue: 1.0)
        case .deepPurple: return Color(red: 0.7, green: 0.3, blue: 0.95)
        }
    }
}

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    @Published public var themeMode: AppThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "MakabaThemeMode")
        }
    }

    @Published public var accentColor: AccentThemeColor {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: "MakabaAccentColor")
        }
    }

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: "MakabaThemeMode")
        self.themeMode = AppThemeMode(rawValue: savedTheme ?? "") ?? .system

        let savedAccent = UserDefaults.standard.string(forKey: "MakabaAccentColor")
        self.accentColor = AccentThemeColor(rawValue: savedAccent ?? "") ?? .classicOrange
    }

    public var backgroundColor: Color {
        switch themeMode {
        case .trueBlack:
            return Color.black
        default:
            return Color(UIColor.systemBackground)
        }
    }

    public var secondaryBackgroundColor: Color {
        switch themeMode {
        case .trueBlack:
            return Color(red: 0.08, green: 0.08, blue: 0.08)
        default:
            return Color(UIColor.secondarySystemGroupedBackground)
        }
    }
}
