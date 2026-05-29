import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english = "en"
    case turkish = "tr"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// `nil` means "follow the system" (no `AppleLanguages` override).
    var localeCode: String? {
        self == .system ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "language.system", defaultValue: "System")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .chinese: return "中文"
        }
    }
}
