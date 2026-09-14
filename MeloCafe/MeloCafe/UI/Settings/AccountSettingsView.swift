//
//  AccountEditorView.swift
//  MeloCafe
//
//  Created by Stossy11 on 14/9/2026.
//

import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var showingCreateAccount = false
    @State private var accountToDelete: Account?
    @State private var errorMessage: String?
    @State private var onlineDetails: String?
    @State private var informationExpanded = false
    @State private var onlineValid = false
    @State private var onlineStatus = "No account selected"

    var body: some View {
        Form {
            Section("Account") {
                Picker("Active account", selection: Binding(
                    get: { configManager.activeAccountPersistentId },
                    set: { configManager.setActiveAccount($0) }
                )) {
                    ForEach(configManager.accounts) { account in
                        Text(account.displayNameWithId).tag(account.persistentId)
                    }
                }
                .pickerStyle(.menu)
                .disabled(configManager.accountControlsLocked || configManager.accounts.isEmpty)

                HStack {
                    Button("Create") { showingCreateAccount = true }
                        .disabled(!configManager.canCreateAccount)
                        .sheet(isPresented: $showingCreateAccount) {
                            CreateAccountView()
                        }
                    Spacer()
                    Button("Delete", role: .destructive) { accountToDelete = configManager.activeAccount }
                        .disabled(!configManager.canDeleteSelectedAccount)
                }
                .buttonStyle(.borderless)
            }

            Section {
                ForEach(NetworkService.allCases) { service in
                    Button {
                        configManager.networkService.wrappedValue = service
                    } label: {
                        HStack {
                            Text(service.accountTitle)
                            Spacer()
                            if (onlineValid ? configManager.networkService.wrappedValue : .offline) == service {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!onlineValid || configManager.accountControlsLocked ||
                              (service == .custom && !configManager.customNetworkServiceAvailable))
                    .accessibilityHint(service.accountHelp)
                }
            } header: {
                Text("Network Service\(configManager.activeAccount.map { " (\($0.displayName))" } ?? "")")
            } footer: {
                Text((onlineValid ? configManager.networkService.wrappedValue : .offline).accountHelp)
            }

            Section("Online play requirements") {
                Button {
                    if let account = configManager.activeAccount {
                        onlineDetails = configManager.onlineValidationDetails(for: account.persistentId)
                    }
                } label: {
                    Label {
                        Text(onlineStatus).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: onlineValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(onlineValid ? .green : .red)
                    }
                }
                .disabled(configManager.activeAccount == nil)
                Link("Online play tutorial", destination: URL(string: "https://cemu.info/online-guide")!)
            }

            Section {
                DisclosureGroup("Account information", isExpanded: $informationExpanded) {
                    if let account = configManager.activeAccount {
                        AccountInformationFields(account: account)
                            .id(account.persistentId)
                            .padding(.vertical, 8)
                    } else {
                        Text("No account selected").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            configManager.reloadAccounts()
            refreshOnlineStatus()
        }
        .onChange(of: configManager.activeAccountPersistentId) { _ in refreshOnlineStatus() }
        .onChange(of: configManager.accounts) { _ in refreshOnlineStatus() }
        .alert("Confirmation", isPresented: Binding(
            get: { accountToDelete != nil },
            set: { if !$0 { accountToDelete = nil } }
        )) {
            Button("Yes", role: .destructive) {
                if let account = accountToDelete {
                    errorMessage = configManager.deleteAccount(persistentId: account.persistentId)
                }
                accountToDelete = nil
            }
            Button("No", role: .cancel) { accountToDelete = nil }
        } message: {
            if let account = accountToDelete {
                Text("Are you sure you want to delete the account \(account.displayName) with id \(account.persistentIdHex)?")
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
        .alert("Online Status", isPresented: Binding(
            get: { onlineDetails != nil },
            set: { if !$0 { onlineDetails = nil } }
        )) {
            Button("OK", role: .cancel) { onlineDetails = nil }
        } message: {
            Text(onlineDetails ?? "")
        }
    }

    private func refreshOnlineStatus() {
        guard let account = configManager.activeAccount else {
            onlineValid = false
            onlineStatus = "No account selected"
            return
        }
        onlineValid = configManager.isOnlineFullyValid(for: account.persistentId)
        onlineStatus = configManager.onlineStatus(for: account.persistentId)
    }
}

private extension NetworkService {
    var accountTitle: String {
        switch self {
        case .offline: return "Offline"
        case .nintendo: return "Nintendo"
        case .pretendo: return "Pretendo"
        case .custom: return "Custom"
        }
    }

    var accountHelp: String {
        switch self {
        case .offline: return "Online functionality disabled for this account"
        case .nintendo: return "Connect to the official Nintendo Network Service"
        case .pretendo: return "Connect to the Pretendo Network Service"
        case .custom: return "Connect to a custom Network Service (configured via network_services.xml)"
        }
    }
}
