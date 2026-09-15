import SwiftUI

/// Wii U console accounts (Cafe/Account/Account.h) - a real, already-working desktop Cemu
/// feature (the same account.dat files desktop Cemu creates, lists and boots under) that
/// had no iOS surface at all before this. Ported from MeloCafe's AccountSettingsView,
/// split into two sections (this one and NetworkServiceSettingsSection below) to match
/// this app's one-struct-per-Section settings layout - see ShaderSettingsSections.swift
/// for the same split applied to a different feature.
struct AccountSettingsSection: View {
    @State private var accounts: [Account] = []
    @State private var activePersistentId: UInt32 = 0
    @State private var locked = false
    @State private var showingCreateAccount = false
    @State private var accountToDelete: Account?
    @State private var errorMessage: String?

    private var activeAccount: Account? {
        accounts.first { $0.persistentId == activePersistentId }
    }

    var body: some View {
        Section {
            Picker("Active account", selection: Binding(
                get: { activePersistentId },
                set: { newValue in
                    activePersistentId = newValue
                    cemu_bridge_set_active_account_persistent_id(newValue)
                }
            )) {
                ForEach(accounts) { account in
                    Text(account.displayNameWithId).tag(account.persistentId)
                }
            }
            .pickerStyle(.menu)
            .tint(MuffinTheme.pixelBlue)
            .disabled(locked || accounts.isEmpty)

            HStack {
                Button("Create") { showingCreateAccount = true }
                    .disabled(locked || !cemu_bridge_accounts_has_free_slot())
                Spacer()
                Button("Delete", role: .destructive) { accountToDelete = activeAccount }
                    .disabled(locked || accounts.count <= 1 || activeAccount == nil)
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Account")
        } footer: {
            if let activeAccount, !activeAccount.isValidOnline {
                InfoButton.footer(
                    "This account has no cached NNID/PNID login, so it can't play online yet.",
                    title: "Account",
                    text: "This account has no cached NNID/PNID login, so it can't play online yet regardless of which Network Service is selected below - that requires signing in on a real console and dumping its account.dat here, which is outside what this app does.")
            }
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear(perform: reload)
        .refreshable { reload() }
        .sheet(isPresented: $showingCreateAccount, onDismiss: reload) {
            CreateAccountView()
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let account = accountToDelete, !cemu_bridge_account_delete(account.persistentId) {
                    errorMessage = "Couldn't delete that account."
                }
                accountToDelete = nil
                reload()
            }
            Button("Cancel", role: .cancel) { accountToDelete = nil }
        } message: {
            if let account = accountToDelete {
                Text("Are you sure you want to delete \(account.displayName) (\(account.persistentIdHex))?")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        cemu_bridge_accounts_refresh()
        accounts = Account.loadAll()
        activePersistentId = cemu_bridge_active_account_persistent_id()
        locked = cemu_bridge_accounts_locked()
    }
}

/// The active account's Network Service - which online backend it connects through, kept
/// separate from AccountSettingsSection above because it's a per-account setting rather
/// than an account-management action, the same distinction MeloCafe draws between its own
/// "Account" and "Network Service" sections.
struct NetworkServiceSettingsSection: View {
    @State private var activePersistentId: UInt32 = 0
    @State private var activeAccountName: String?
    @State private var selectedService: NetworkService = .offline
    @State private var locked = false
    @State private var customAvailable = false

    var body: some View {
        Section {
            ForEach(NetworkService.allCases) { service in
                Button {
                    cemu_bridge_set_network_service(activePersistentId, service.bridgeValue)
                    selectedService = service
                } label: {
                    HStack {
                        Text(service.string)
                        Spacer()
                        if selectedService == service {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(locked || activeAccountName == nil || (service == .custom && !customAvailable))
            }
        } header: {
            Text("Network Service\(activeAccountName.map { " (\($0))" } ?? "")")
        } footer: {
            InfoButton.footer(
                selectedService.accountHelp,
                title: "Network Service",
                text: "Nintendo and Pretendo both connect this account to real online multiplayer against other players. Pretendo is a community-run reimplementation of Nintendo's original Wii U servers, kept running now that Nintendo's own have been shut down - its server addresses are already built into MuffinEMU, so there's nothing else to configure.\n\nCustom has no configuration screen in this app: it only becomes available once you've placed a hand-written network_services.xml (the same file desktop Cemu reads) in the mlc folder yourself.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear(perform: reload)
        .refreshable { reload() }
    }

    private func reload() {
        activePersistentId = cemu_bridge_active_account_persistent_id()
        let accounts = Account.loadAll()
        activeAccountName = accounts.first { $0.persistentId == activePersistentId }?.displayName
        selectedService = NetworkService(cemu_bridge_network_service(activePersistentId))
        locked = cemu_bridge_accounts_locked()
        customAvailable = cemu_bridge_custom_network_service_available()
    }
}
