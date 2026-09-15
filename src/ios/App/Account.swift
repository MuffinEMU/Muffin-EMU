import Foundation

/// A real Wii U console account (Cafe/Account/Account.h) - the same account.dat file
/// desktop Cemu creates under mlc/usr/save/system/act/. Ported from MeloCafe's
/// Account.swift; the only change is the initializer, which parses one 0x1F-delimited
/// record from cemu_bridge_accounts_list() instead of an Obj-C dictionary - the same
/// wire shape GraphicPacksView.swift already reads from cemu_bridge_graphic_packs_list().
struct Account: Identifiable, Hashable {
    let persistentId: UInt32
    var miiName: String
    var birthYear: UInt16
    var birthMonth: UInt8
    var birthDay: UInt8
    var gender: Int
    var email: String
    var country: Int
    var isValidOnline: Bool

    var id: UInt32 { persistentId }
    var persistentIdHex: String { String(persistentId, radix: 16) }
    var displayName: String { miiName.isEmpty ? "default" : miiName }
    var displayNameWithId: String { "\(displayName) (\(persistentIdHex))" }

    /// `fields` is one record from cemu_bridge_accounts_list() already split on 0x1F -
    /// see that function's doc comment in CemuBridge.h for the exact field order.
    init?(fields: [Substring]) {
        guard fields.count >= 9, let persistentId = UInt32(fields[0], radix: 16) else {
            return nil
        }

        self.persistentId = persistentId
        self.miiName = String(fields[1])
        self.birthYear = UInt16(fields[2]) ?? 0
        self.birthMonth = UInt8(fields[3]) ?? 0
        self.birthDay = UInt8(fields[4]) ?? 0
        self.gender = Int(fields[5]) ?? 0
        self.email = String(fields[6])
        self.country = Int(fields[7]) ?? 0
        self.isValidOnline = fields[8] == "1"
    }

    /// Parses the full cemu_bridge_accounts_list() string into accounts, in the order
    /// the engine returned them. Call cemu_bridge_accounts_refresh() first if the list on
    /// disk may have changed.
    static func loadAll() -> [Account] {
        let raw = String(cString: cemu_bridge_accounts_list())
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\u{1E}").compactMap { record in
            Account(fields: record.split(separator: "\u{1F}", omittingEmptySubsequences: false))
        }
    }
}

/// A real Wii U country code (NCrypto's own list, the one desktop Cemu's account editor
/// uses) - ported from MeloCafe's AccountCountry with the same record-parsing adjustment
/// as Account above.
struct AccountCountry: Identifiable, Hashable {
    let code: Int
    let name: String

    var id: Int { code }

    init?(fields: [Substring]) {
        guard fields.count >= 2, let code = Int(fields[0]) else { return nil }

        self.code = code
        self.name = fields[1].isEmpty ? "\(code)" : String(fields[1])
    }

    /// Parses cemu_bridge_countries_list() the same way Account.loadAll() parses accounts.
    static func loadAll() -> [AccountCountry] {
        let raw = String(cString: cemu_bridge_countries_list())
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\u{1E}").compactMap { record in
            AccountCountry(fields: record.split(separator: "\u{1F}", omittingEmptySubsequences: false))
        }
    }
}
