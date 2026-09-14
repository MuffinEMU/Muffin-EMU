//
//  ConfigManager+Accounts.swift
//  MeloCafe
//
//  Created by Stossy11 on 29/4/2026.
//

extension ConfigManager {
    func reloadAccounts() {
        config.refreshAccounts()

        let raw = config.accounts() as? [[String: Any]] ?? []
        accounts = raw.compactMap(Account.init)

        let countryRaw = config.countries as? [[String: Any]] ?? []
        accountCountries = countryRaw.compactMap(AccountCountry.init)
        accountControlsLocked = config.isTitleRunning
        customNetworkServiceAvailable = config.canUseCustomNetworkService

        let configuredPersistentId = config.activeAccountPersistentId
        if accounts.contains(where: { $0.persistentId == configuredPersistentId }) {
            activeAccountPersistentId = configuredPersistentId
        } else if let firstAccount = accounts.first {
            setActiveAccount(firstAccount.persistentId)
        } else {
            activeAccountPersistentId = configuredPersistentId
        }
    }

    func setActiveAccount(_ pid: UInt32) {
        config.activeAccountPersistentId = pid
        activeAccountPersistentId = pid
    }

    var activeAccount: Account? {
        accounts.first { $0.persistentId == activeAccountPersistentId }
    }

    var minimumAccountPersistentId: UInt32 {
        config.minimumAccountPersistentId
    }

    var nextAccountPersistentId: UInt32 {
        config.nextAccountPersistentId
    }

    var hasFreeAccountSlots: Bool {
        config.hasFreeAccountSlots
    }

    var canDeleteSelectedAccount: Bool {
        accounts.count > 1 && !accountControlsLocked && activeAccount != nil
    }

    var canCreateAccount: Bool {
        hasFreeAccountSlots && !accountControlsLocked
    }

    var selectableNetworkServices: [NetworkService] {
        NetworkService.allCases.filter { service in
            service != .custom || customNetworkServiceAvailable
        }
    }

    func accountExists(persistentId: UInt32) -> Bool {
        config.accountExists(forPersistentId: persistentId)
    }

    func isOnlineFullyValid(for persistentId: UInt32) -> Bool {
        config.isOnlineFullyValid(forPersistentId: persistentId)
    }

    func onlineStatus(for persistentId: UInt32) -> String {
        config.onlineStatus(forPersistentId: persistentId)
    }

    func onlineValidationDetails(for persistentId: UInt32) -> String {
        config.onlineValidationDetails(forPersistentId: persistentId)
    }

    @discardableResult
    func createAccount(persistentId: UInt32, miiName: String) -> String? {
        if let error = config.createAccount(withPersistentId: persistentId, miiName: miiName) {
            return error
        }

        reloadAccounts()
        setActiveAccount(persistentId)
        return nil
    }

    @discardableResult
    func deleteAccount(persistentId: UInt32) -> String? {
        if let error = config.deleteAccount(withPersistentId: persistentId) {
            return error
        }

        reloadAccounts()
        if !accounts.contains(where: { $0.persistentId == activeAccountPersistentId }),
           let firstAccount = accounts.first {
            setActiveAccount(firstAccount.persistentId)
        }
        return nil
    }

    @discardableResult
    func setMiiName(_ name: String, for pid: UInt32) -> Bool {
        let ok = config.setMiiName(name, forPersistentId: pid)
        if ok { reloadAccounts() }
        return ok
    }

    @discardableResult
    func setGender(_ gender: Int, for pid: UInt32) -> Bool {
        let ok = config.setGender(Int32(gender), forPersistentId: pid)
        if ok { reloadAccounts() }
        return ok
    }

    @discardableResult
    func setEmail(_ email: String, for pid: UInt32) -> Bool {
        let ok = config.setEmail(email, forPersistentId: pid)
        if ok { reloadAccounts() }
        return ok
    }

    @discardableResult
    func setCountry(_ country: Int, for pid: UInt32) -> Bool {
        let ok = config.setCountry(Int32(country), forPersistentId: pid)
        if ok { reloadAccounts() }
        return ok
    }

    @discardableResult
    func setBirthDate(
        year: UInt16,
        month: UInt8,
        day: UInt8,
        for pid: UInt32
    ) -> Bool {
        let ok = config.setBirthYear(
            year,
            month: month,
            day: day,
            forPersistentId: pid
        )

        if ok { reloadAccounts() }
        return ok
    }
}
