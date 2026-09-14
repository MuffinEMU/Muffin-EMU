//
//  CreateAccountView.swift
//  MeloCafe
//
//  Created by Stossy11 on 10/9/2026.
//

import SwiftUI

struct CreateAccountView: View {
    @StateObject private var configManager = ConfigManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var persistentIdText: String
    @State private var miiName = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool
    
    init() {
        _persistentIdText = State(initialValue: String(ConfigManager.shared.nextAccountPersistentId, radix: 16))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("PersistentId")
                        TextField("PersistentId", text: $persistentIdText)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospaced())
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Mii name")
                        TextField("Mii name", text: $miiName)
                            .multilineTextAlignment(.trailing)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { createAccount() }
                    }
                        .onChange(of: miiName) { newValue in
                            let trimmedName = String(newValue.prefix(10))
                            if trimmedName != newValue {
                                miiName = trimmedName
                            }
                        }
                } footer: {
                    Text("The persistent id is the internal folder name used for your saves. Only change this if you are importing saves from a Wii U with a specific id.")
                }
            }
            .navigationTitle("Create new account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        createAccount()
                    }
                }
            }
        }
        .frame(idealWidth: 440, idealHeight: 320)
        .onAppear { nameFocused = true }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func createAccount() {
        let idString = persistentIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idString.isEmpty else {
            errorMessage = "No persistent id entered!"
            return
        }
        
        guard configManager.canCreateAccount else {
            errorMessage = configManager.accountControlsLocked ? "Can't create an account while a game is running!" : "Maximum account limit reached."
            return
        }
        guard let persistentId = UInt32(idString, radix: 16) else {
            errorMessage = "Enter a valid hexadecimal persistent id."
            return
        }
        guard persistentId >= configManager.minimumAccountPersistentId else {
            errorMessage = "The persistent id must be greater than \(String(configManager.minimumAccountPersistentId, radix: 16))!"
            return
        }
        
        if configManager.accountExists(persistentId: persistentId) {
            let accountName = configManager.accounts
                .first(where: { $0.persistentId == persistentId })?
                .displayName ?? "unknown"
            errorMessage = "The persistent id \(String(persistentId, radix: 16)) is already in use by account \(accountName)!"
            return
        }
        
        guard !miiName.isEmpty else {
            errorMessage = "Account name may not be empty!"
            return
        }
        
        if let error = configManager.createAccount(persistentId: persistentId, miiName: miiName) {
            errorMessage = error
            return
        }
        
        dismiss()
    }
}
