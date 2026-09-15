import SwiftUI

/// Creates a new Wii U console account (Cafe/Account/Account.h). Ported from MeloCafe's
/// CreateAccountView.swift, extended to collect every field cemu_bridge_account_create()
/// takes (birth date, gender, email, country) up front rather than leaving them to be
/// set one at a time afterward - MeloCafe's own form only asks for persistentId/miiName
/// because its separate AccountInformationFields editor covers the rest post-creation;
/// this app doesn't have that second editor yet, so the create form covers the whole
/// on-disk shape instead.
struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var persistentIdText: String
    @State private var miiName = ""
    @State private var birthDate: Date
    @State private var gender = 0 // 0 male, 1 female - Account's own FFL Mii encoding
    @State private var email = ""
    @State private var country = 0
    @State private var countries: [AccountCountry] = []
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init() {
        _persistentIdText = State(initialValue: String(cemu_bridge_accounts_next_persistent_id(), radix: 16))
        _birthDate = State(initialValue: Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date())
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0 - same
        // reasoning as SettingsView.swift's own NavigationView.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            // The app's row-label font, like every other labelled row in
                            // Settings and the sheets. These were plain body text.
                            Text("Persistent ID")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            TextField("Persistent ID", text: $persistentIdText)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospaced())
                                .keyboardType(.asciiCapable)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        HStack {
                            Text("Mii name")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            TextField("Mii name", text: $miiName)
                                .multilineTextAlignment(.trailing)
                                .focused($nameFocused)
                                .submitLabel(.done)
                            // The field silently truncates at ten characters (the Wii U's
                            // own Mii name limit, enforced below). Typing an eleventh and
                            // watching nothing happen looks like a stuck keyboard; the
                            // counter says what the rule is before it bites.
                            Text("\(miiName.count)/10")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(miiName.count >= 10 ? MuffinTheme.blushPink : MuffinTheme.brownMid)
                                .monospacedDigit()
                                .accessibilityLabel("\(miiName.count) of 10 characters used")
                        }
                        .onChange(of: miiName) { newValue in
                            let trimmedName = String(newValue.prefix(10))
                            if trimmedName != newValue {
                                miiName = trimmedName
                            }
                        }
                    } footer: {
                        Text("The persistent ID is the internal folder name used for your saves. Only change this if you are importing saves from a Wii U with a specific ID.")
                    }

                    Section("Mii details") {
                        DatePicker(selection: $birthDate, in: ...Date(), displayedComponents: .date) {
                            Text("Birthday")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        Picker(selection: $gender) {
                            Text("Male").tag(0)
                            Text("Female").tag(1)
                        } label: {
                            Text("Gender")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .pickerStyle(.segmented)
                        Picker(selection: $country) {
                            ForEach(countries) { entry in
                                Text(entry.name).tag(entry.code)
                            }
                        } label: {
                            Text("Country")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .pickerStyle(.menu)
                        .tint(MuffinTheme.pixelBlue)
                    }

                    Section {
                        TextField("Email (optional)", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Only used if you later link this account to a real NNID/PNID for online play.")
                    }
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
                    // "Create", not "OK" - the confirming action on a creation form should
                    // name what it does, and "OK" next to "Cancel" says nothing about
                    // which one makes an account.
                    Button("Create") {
                        createAccount()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            nameFocused = true
            countries = AccountCountry.loadAll()
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

    private func createAccount() {
        let idString = persistentIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idString.isEmpty else {
            errorMessage = "No persistent id entered!"
            return
        }

        guard !cemu_bridge_accounts_locked() else {
            errorMessage = "Can't create an account while a game is running!"
            return
        }
        guard cemu_bridge_accounts_has_free_slot() else {
            errorMessage = "Maximum account limit reached."
            return
        }
        guard let persistentId = UInt32(idString, radix: 16) else {
            errorMessage = "Enter a valid hexadecimal persistent id."
            return
        }
        let minimumPersistentId = cemu_bridge_accounts_min_persistent_id()
        guard persistentId >= minimumPersistentId else {
            errorMessage = "The persistent id must be greater than \(String(minimumPersistentId, radix: 16))!"
            return
        }

        let existingAccounts = Account.loadAll()
        if let existing = existingAccounts.first(where: { $0.persistentId == persistentId }) {
            errorMessage = "The persistent id \(String(persistentId, radix: 16)) is already in use by account \(existing.displayName)!"
            return
        }

        guard !miiName.isEmpty else {
            errorMessage = "Account name may not be empty!"
            return
        }

        let components = Calendar.current.dateComponents([.year, .month, .day], from: birthDate)
        let created = miiName.withCString { miiNamePtr in
            email.withCString { emailPtr in
                cemu_bridge_account_create(
                    persistentId,
                    miiNamePtr,
                    UInt16(components.year ?? 2000),
                    UInt8(components.month ?? 1),
                    UInt8(components.day ?? 1),
                    Int32(gender),
                    emailPtr,
                    Int32(country)
                )
            }
        }

        guard created else {
            errorMessage = "Couldn't create that account."
            return
        }

        dismiss()
    }
}
