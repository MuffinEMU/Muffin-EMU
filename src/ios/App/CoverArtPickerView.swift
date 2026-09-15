import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The manual escape hatch for a card CoverArtFetcher's automatic fetch never found
/// anything for - homebrew, or an obscure title GameTDB simply doesn't list - opened
/// from a deliberate long-press ("Change Cover Art…" in GameContextMenu). This is
/// NOT a reversal of CoverArtFetcher.swift's "no picker, automatic only" decision:
/// the automatic fetch still runs first, unchanged, for every game; this only ever
/// fires when someone specifically asks for it, for one specific game.
///
/// Whichever of the three paths below produces an image, the result always lands in
/// the exact same place: a `<gameID>_cover.*` file in Documents/Roms, via
/// GameManager.setManualCover() - the file GameManager.findCover() already checks
/// first, above both auto-fetched box art and the console's own icon. No new
/// override mechanism, no new priority list.
struct CoverArtPickerView: View {
    let game: GameMetadata
    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingLegacyPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var errorMessage: String?
    /// Removing the override throws away the image file and immediately dismisses, with
    /// no undo - the same shape as every other destructive action in the app, which all
    /// ask first through a confirmationDialog. This one didn't.
    @State private var showingRemoveConfirmation = false

    // "Try a specific GameTDB ID" state. The fetched image sits here as a preview
    // only - nothing is written to disk until "Use This Cover" is tapped.
    @State private var tdbIdText = ""
    @State private var isFetchingTdb = false
    @State private var tdbFetchAttempted = false
    @State private var tdbPreviewImage: UIImage?
    @State private var tdbFetchedData: Data?
    @State private var tdbFetchedExt: String?

    private var hasOverride: Bool {
        gameManager.hasManualCoverOverride(forGameID: game.id)
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0 -
        // same reasoning as SettingsView.swift's own NavigationView.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                Form {
                    currentCoverSection
                    photosSection
                    filesSection
                    gameTdbSection
                }
            }
            .navigationTitle("Change Cover Art")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .foregroundColor(MuffinTheme.brownDarkest)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image]) { result in
            handleFileImportResult(result)
        }
        #if os(iOS)
        .sheet(isPresented: $showingLegacyPhotoPicker) {
            LegacyPhotoPicker { picked in
                showingLegacyPhotoPicker = false
                // Already a decoded UIImage (UIImagePickerController's own
                // .originalImage) - straight to applyImageData, no need to route
                // through handlePickedImageData's decode-from-raw-bytes step.
                guard let picked, let jpegData = picked.jpegData(compressionQuality: 0.92) else { return }
                applyImageData(jpegData, ext: "jpg")
            }
        }
        #endif
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Remove custom cover?", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Custom Cover", role: .destructive) {
                gameManager.removeManualCover(forGameID: game.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The cover you set is deleted. MuffinEMU goes back to the automatically-found art, or the placeholder if it never found any.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var currentCoverSection: some View {
        Section {
            HStack(spacing: 12) {
                coverThumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.displayTitle ?? game.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(hasOverride ? "Using a custom cover you set." : "Using an automatically-found cover, or the placeholder if none was found.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                }
                Spacer()
            }
            if hasOverride {
                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label("Remove Custom Cover", systemImage: "photo.badge.minus")
                }
            }
        }
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MuffinTheme.muffinTopGradient)
            if let coverPath = game.coverPath, let uiImage = UIImage(contentsOfFile: coverPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(MuffinTheme.sparkleCream)
            }
        }
        .frame(width: 48, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var photosSection: some View {
        Section {
            // PhotosPickerItem/PhotosPicker are iOS 16+ types - not just APIs that need
            // an `if #available` around their call, but types that can't appear as a
            // stored property's TYPE anywhere in a file built against this project's
            // 15.0 deployment target. So the modern path is a whole separate view
            // (ModernPhotoPickerButton below, itself marked @available(iOS 16.0, *))
            // that owns that state internally, rather than a property living here -
            // same shape as NavigationStack vs. NavigationView elsewhere in this
            // codebase, just pushed down one level because this one needs state, not
            // only a call.
            if #available(iOS 16.0, *) {
                ModernPhotoPickerButton(
                    onPicked: { data in handlePickedImageData(data) },
                    onError: { message in errorMessage = message }
                )
            } else {
                Button {
                    showingLegacyPhotoPicker = true
                } label: {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(MuffinSecondaryButtonStyle())
            }
        } header: {
            Text("From Photos")
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        Section {
            Button {
                showingFileImporter = true
            } label: {
                Label("Import a File", systemImage: "folder")
            }
            .buttonStyle(MuffinSecondaryButtonStyle())
        } header: {
            Text("From Files")
        } footer: {
            Text("Pick an image (JPG, PNG, or another common format) from Files, iCloud Drive, or another app.")
        }
    }

    @ViewBuilder
    private var gameTdbSection: some View {
        Section {
            TextField("Game ID, e.g. AGBE01", text: $tdbIdText)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                #endif
                .autocorrectionDisabled()
                .font(.body.monospaced())

            Button {
                fetchFromGameTDB()
            } label: {
                if isFetchingTdb {
                    HStack {
                        ProgressView()
                        Text("Fetching\u{2026}")
                    }
                } else {
                    Text("Fetch")
                }
            }
            .buttonStyle(MuffinSecondaryButtonStyle())
            .disabled(isFetchingTdb || tdbIdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let tdbPreviewImage {
                VStack(alignment: .leading, spacing: 10) {
                    Image(uiImage: tdbPreviewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                        .background(MuffinTheme.muffinTopGradient)
                        .cornerRadius(10)
                    Button {
                        commitTdbFetchedCover()
                    } label: {
                        Text("Use This Cover")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MuffinPrimaryButtonStyle())
                }
            } else if tdbFetchAttempted && !isFetchingTdb {
                Text("No cover art found for that ID.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(MuffinTheme.brownMid)
            }
        } header: {
            Text("Try a Specific GameTDB ID")
        } footer: {
            InfoButton.footer(
                "Find a Game ID on GameTDB's own cover-art pages.",
                title: "GameTDB Game ID",
                text: "This isn't a search - GameTDB doesn't offer one as an API. Instead, browse GameTDB's own Wii U cover-art library at https://www.gametdb.com/WiiU/CoverArt to find your game, then read its Game ID off the page (a 6-character code, e.g. AGBE01) and type it above. \"Fetch\" tries that exact ID against GameTDB's real cover-art service and shows you what it finds before anything is saved."
            )
        }
    }

    // MARK: - Photos / Files (both funnel here)

    /// Shared by ModernPhotoPickerButton's PhotosPicker selection, LegacyPhotoPicker's
    /// UIImagePickerController result, and the .fileImporter result below - whatever
    /// format the source actually is (HEIC from Photos, PNG, whatever Files hands
    /// back), decoding through UIImage and re-encoding as JPEG guarantees the bytes
    /// that reach setManualCover() are always one of the three extensions
    /// findCover() checks, without needing per-source format detection.
    private func handlePickedImageData(_ data: Data) {
        guard let uiImage = UIImage(data: data), let jpegData = uiImage.jpegData(compressionQuality: 0.92) else {
            errorMessage = "That doesn't look like a valid image."
            return
        }
        applyImageData(jpegData, ext: "jpg")
    }

    // MARK: - Files

    private func handleFileImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Couldn't import that file: \(error.localizedDescription)"
        case .success(let url):
            // Security scope only covers this call - same pattern GameManager.importROM
            // already uses for a .fileImporter-picked URL outside our sandbox.
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Couldn't read that file."
                return
            }
            handlePickedImageData(data)
        }
    }

    // MARK: - GameTDB

    private func fetchFromGameTDB() {
        let id = tdbIdText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !id.isEmpty else { return }

        isFetchingTdb = true
        tdbFetchAttempted = false
        tdbPreviewImage = nil
        tdbFetchedData = nil
        tdbFetchedExt = nil

        Task {
            do {
                let found = try await CoverArtFetcher.fetchArt(forGameTdbId: id)
                await MainActor.run {
                    isFetchingTdb = false
                    tdbFetchAttempted = true
                    if let found, let image = UIImage(data: found.data) {
                        tdbPreviewImage = image
                        tdbFetchedData = found.data
                        tdbFetchedExt = found.ext
                    }
                }
            } catch {
                await MainActor.run {
                    isFetchingTdb = false
                    tdbFetchAttempted = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func commitTdbFetchedCover() {
        guard let data = tdbFetchedData, let ext = tdbFetchedExt else { return }
        applyImageData(data, ext: ext)
    }

    // MARK: - Commit

    private func applyImageData(_ data: Data, ext: String) {
        do {
            try gameManager.setManualCover(imageData: data, ext: ext, forGameID: game.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The iOS 16+ "Choose from Photos" button. Its own `@State` holds the
/// PhotosPickerItem selection - PhotosPickerItem is itself an iOS 16+ type, so it
/// cannot be a stored property anywhere in CoverArtPickerView (built against this
/// project's 15.0 deployment target) even behind an `if #available` at the call
/// site; the whole view carrying that state has to be gated instead, which is what
/// CoverArtPickerView.photosSection does by only ever constructing this type inside
/// its own `if #available(iOS 16.0, *)` branch.
@available(iOS 16.0, *)
private struct ModernPhotoPickerButton: View {
    var onPicked: (Data) -> Void
    var onError: (String) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label("Choose from Photos", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(MuffinSecondaryButtonStyle())
        .onChange(of: item) { newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                    await MainActor.run { onError("Couldn't load that photo.") }
                    return
                }
                await MainActor.run { onPicked(data) }
            }
        }
    }
}

#if os(iOS)
/// UIImagePickerController-backed fallback for iOS 15, where PhotosPicker (PhotosUI,
/// iOS 16+) doesn't exist yet - same `if #available(iOS 16.0, *)` gating this
/// codebase already uses for NavigationStack vs. NavigationView (see
/// SettingsView.swift) and .persistentSystemOverlays (see ContentView.swift's
/// HideSystemOverlaysIfAvailable). Neither this nor PhotosPicker needs
/// NSPhotoLibraryUsageDescription or triggers a permission prompt - both run
/// out-of-process, handing the app only the one image picked, a behavior Apple
/// changed UIImagePickerController(sourceType: .photoLibrary) to back in iOS 11 -
/// so there is no separate "access denied" branch to handle here; picking and
/// cancelling are the only two outcomes.
private struct LegacyPhotoPicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}
#endif
