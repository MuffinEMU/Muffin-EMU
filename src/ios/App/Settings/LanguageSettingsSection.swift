// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// The language MuffinEMU's own text is shown in. Each one has a <code>.lproj/Localizable.strings
/// under App/Localization, keyed by the English text.
///
/// iOS picks an app's language when the app starts, from the app's own AppleLanguages if it has one,
/// so a choice here writes that and applies the next time MuffinEMU opens. It's also what iOS
/// Settings > Apps > MuffinEMU > Language changes.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, es, fr, de, it, ptBR = "pt-BR", ptPT = "pt-PT", nl, sv, nb, da, fi, pl, cs, sk, hu, ro, hr
    case el, tr, ru, uk, ca, ar, he, hi, id, ms, th, vi, ja, ko, zhHans = "zh-Hans", zhHant = "zh-Hant"

    var id: String { rawValue }

    /// Each language in its own name, so someone who can't read the current one can still find theirs.
    var nativeName: String {
        switch self {
        case .system: return "Same as this device".localized
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .ptBR: return "Português (Brasil)"
        case .ptPT: return "Português (Portugal)"
        case .nl: return "Nederlands"
        case .sv: return "Svenska"
        case .nb: return "Norsk bokmål"
        case .da: return "Dansk"
        case .fi: return "Suomi"
        case .pl: return "Polski"
        case .cs: return "Čeština"
        case .sk: return "Slovenčina"
        case .hu: return "Magyar"
        case .ro: return "Română"
        case .hr: return "Hrvatski"
        case .el: return "Ελληνικά"
        case .tr: return "Türkçe"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .ca: return "Català"
        case .ar: return "العربية"
        case .he: return "עברית"
        case .hi: return "हिन्दी"
        case .id: return "Bahasa Indonesia"
        case .ms: return "Bahasa Melayu"
        case .th: return "ไทย"
        case .vi: return "Tiếng Việt"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }

    /// Not under "muffin.": Reset settings and a settings import leave the language alone, like the theme.
    static let storageKey = "MuffinAppLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    static var chosen: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// The language this launch is showing, as iOS resolved it from the bundle's localizations.
    static var running: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }

    /// Records the choice and hands it to iOS for the next launch. Same as this device removes the app's
    /// own list, so the device's languages apply again.
    static func choose(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: storageKey)
        if language == .system {
            defaults.removeObject(forKey: appleLanguagesKey)
        } else {
            defaults.set([language.rawValue], forKey: appleLanguagesKey)
        }
    }
}

extension String {
    /// This English text in the app's language, from Localizable.strings; itself when there is no
    /// translation. For text that reaches the screen as a String rather than a SwiftUI string literal
    /// (which SwiftUI looks up on its own). A format string is looked up before it's filled in:
    /// `String(format: "%d games".localized, count)`.
    var localized: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }
}

/// Settings > General > Language.
struct LanguageSettingsSection: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue
    /// What was chosen when this launch started, so the note only shows after a change.
    @State private var atLaunch = AppLanguage.chosen
    @State private var confirmClose = false

    private var choice: Binding<String> {
        Binding(
            get: { languageRaw },
            set: { raw in AppLanguage.choose(AppLanguage(rawValue: raw) ?? .system) })
    }

    var body: some View {
        Section {
            Picker(selection: choice) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.nativeName).tag(language.rawValue)
                }
            } label: {
                Label("Language", systemImage: "globe")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.accentText)

            if AppLanguage(rawValue: languageRaw) != atLaunch {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MuffinEMU switches language the next time it opens.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Close MuffinEMU now") { confirmClose = true }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
        } header: {
            SettingsSectionHeader("Language".localized, icon: "globe", accent: .system)
        } footer: {
            InfoButton.footer(
                String(format: "Now showing: %@.".localized, AppLanguage.running),
                title: "Language".localized,
                text: "Changes the language of MuffinEMU's own menus and Settings. Games keep their own language.\n\nThe translations are machine-made, so some wording may be off. Same as this device follows your iPhone or iPad's languages.".localized)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .confirmationDialog("Close MuffinEMU?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Close") { exit(0) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Open it again from the Home Screen to see the new language.")
        }
    }
}
