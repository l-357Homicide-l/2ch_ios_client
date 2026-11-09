//
//  TypographySettingsView.swift
//  Makaba
//
//  Typography, text scaling, and post layout density preferences.
//

import SwiftUI

@MainActor
public final class TypographySettingsManager: ObservableObject {
    public static let shared = TypographySettingsManager()

    @Published public var fontSizeMultiplier: Double {
        didSet { UserDefaults.standard.set(fontSizeMultiplier, forKey: "MakabaFontSizeMultiplier") }
    }

    @Published public var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: "MakabaLineSpacing") }
    }

    @Published public var isCompactHeaderEnabled: Bool {
        didSet { UserDefaults.standard.set(isCompactHeaderEnabled, forKey: "MakabaCompactHeader") }
    }

    private init() {
        let savedSize = UserDefaults.standard.double(forKey: "MakabaFontSizeMultiplier")
        self.fontSizeMultiplier = savedSize > 0 ? savedSize : 1.0

        let savedSpacing = UserDefaults.standard.double(forKey: "MakabaLineSpacing")
        self.lineSpacing = savedSpacing > 0 ? savedSpacing : 4.0

        self.isCompactHeaderEnabled = UserDefaults.standard.bool(forKey: "MakabaCompactHeader")
    }
}

public struct TypographySettingsView: View {
    @ObservedObject private var settings = TypographySettingsManager.shared

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Размер шрифта комментариев")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("A")
                            .font(.system(size: 13))
                        Slider(value: $settings.fontSizeMultiplier, in: 0.85...1.4, step: 0.05)
                            .tint(.orange)
                        Text("A")
                            .font(.system(size: 22, weight: .bold))
                    }
                    Text(String(format: "Масштаб: %.0f%%", settings.fontSizeMultiplier * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Межстрочный интервал")) {
                Picker("Интервал строк", selection: $settings.lineSpacing) {
                    Text("Компактный (2pt)").tag(2.0)
                    Text("Стандартный (4pt)").tag(4.0)
                    Text("Комфортный (6pt)").tag(6.0)
                    Text("Просторный (8pt)").tag(8.0)
                }
                .pickerStyle(.menu)
            }

            Section(header: Text("Компактность интерфейса")) {
                Toggle("Компактные заголовки постов", isOn: $settings.isCompactHeaderEnabled)
            }

            Section(header: Text("Предпросмотр")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Аноним")
                            .font(.subheadline.weight(.semibold))
                        Text("№1234567")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.orange)
                        Spacer()
                        Text("10.11.26 01:20")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Пример отображения текста сообщения на доске. Греентекст, цитаты и спойлеры будут адаптироваться под выбранный масштаб.")
                        .font(.system(size: 15 * settings.fontSizeMultiplier))
                        .lineSpacing(CGFloat(settings.lineSpacing))
                        .foregroundColor(.primary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemGroupedBackground)))
            }
        }
        .navigationTitle("Типографика и шрифты")
        .navigationBarTitleDisplayMode(.inline)
    }
}
