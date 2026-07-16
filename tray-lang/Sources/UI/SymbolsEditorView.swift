import SwiftUI

struct SymbolPair: Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

struct SymbolsEditorView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @State private var selectedProfileID: UUID?

    var body: some View {
        HSplitView {
            ProfileListView(
                textTransformer: appCoordinator.textTransformer,
                selectedProfileID: $selectedProfileID
            )
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            .frame(maxHeight: .infinity)

            Group {
                if let profileID = selectedProfileID,
                   let profileIndex = appCoordinator.textTransformer.profiles.firstIndex(where: { $0.id == profileID }) {
                    ProfileDetailView(
                        profile: Binding(
                            get: { appCoordinator.textTransformer.profiles[profileIndex] },
                            set: { appCoordinator.textTransformer.profiles[profileIndex] = $0 }
                        ),
                        textTransformer: appCoordinator.textTransformer,
                        selectedProfileID: $selectedProfileID
                    )
                } else {
                    ContentUnavailableView(
                        "Select a profile",
                        systemImage: "textformat.abc",
                        description: Text("Choose a conversion profile on the left to view or edit symbols.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedProfileID = appCoordinator.textTransformer.activeProfileID
        }
        .onDisappear {
            appCoordinator.textTransformer.saveProfiles()
        }
    }
}

// MARK: - Profile List

struct ProfileListView: View {
    @ObservedObject var textTransformer: TextTransformer
    @Binding var selectedProfileID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profiles")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("New Empty Profile") {
                        textTransformer.createNewProfile()
                        selectedProfileID = textTransformer.profiles.last?.id
                    }
                    Divider()
                    Text("New From Template")
                    ForEach(ConversionProfile.defaultProfiles()) { template in
                        Button(template.name) {
                            textTransformer.duplicateProfile(template)
                            selectedProfileID = textTransformer.profiles.last?.id
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("Create a new profile")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            List(selection: $selectedProfileID) {
                ForEach(textTransformer.profiles) { profile in
                    HStack {
                        Image(systemName: profile.isEditable ? "pencil.and.scribble" : "lock.fill")
                            .foregroundColor(.secondary)
                        Text(profile.name)
                            .lineLimit(1)
                        Spacer()
                        if profile.id == textTransformer.activeProfileID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .help("This profile is active")
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button("Set as Active") {
                            textTransformer.activeProfileID = profile.id
                        }
                        .disabled(profile.id == textTransformer.activeProfileID)

                        if profile.isEditable {
                            Button("Delete", role: .destructive) {
                                if let index = textTransformer.profiles.firstIndex(of: profile) {
                                    textTransformer.deleteProfile(at: IndexSet(integer: index))
                                    if textTransformer.profiles.isEmpty {
                                        selectedProfileID = nil
                                    } else {
                                        selectedProfileID = textTransformer.profiles.first?.id
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Profile Detail

struct ProfileDetailView: View {
    @Binding var profile: ConversionProfile
    @ObservedObject var textTransformer: TextTransformer
    @Binding var selectedProfileID: UUID?

    @State private var symbolPairs: [SymbolPair] = []
    @State private var searchText = ""

    private var filteredPairs: [SymbolPair] {
        if searchText.isEmpty {
            return symbolPairs
        }
        return symbolPairs.filter {
            $0.from.localizedCaseInsensitiveContains(searchText) ||
            $0.to.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Profile Name", text: $profile.name)
                        .font(.title2)
                        .textFieldStyle(.plain)
                        .disabled(!profile.isEditable)

                    Spacer()

                    Button("Set as Active") {
                        textTransformer.activeProfileID = profile.id
                    }
                    .disabled(profile.id == textTransformer.activeProfileID)

                    Button("Duplicate") {
                        textTransformer.duplicateProfile(profile)
                        selectedProfileID = textTransformer.profiles.last?.id
                    }
                }

                TextField("Search symbols…", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if !profile.isEditable {
                    Text("This is a default profile. Duplicate it to make changes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            List {
                ForEach(filteredPairs) { pair in
                    if let pairIndex = symbolPairs.firstIndex(where: { $0.id == pair.id }) {
                        SymbolEditRowView(
                            from: $symbolPairs[pairIndex].from,
                            to: $symbolPairs[pairIndex].to,
                            onDelete: {
                                symbolPairs.removeAll { $0.id == pair.id }
                            }
                        )
                    }
                }
                .onDelete(perform: profile.isEditable ? deleteSymbol : nil)

                if profile.isEditable {
                    Button("Add Symbol", systemImage: "plus") {
                        symbolPairs.append(SymbolPair(from: "", to: ""))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .disabled(!profile.isEditable)

            if profile.isEditable {
                Divider()
                HStack {
                    Spacer()
                    Button("Apply Changes") {
                        saveChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: updateSymbolPairs)
        .onChange(of: profile.id) { _, _ in updateSymbolPairs() }
    }

    private func deleteSymbol(at offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredPairs[$0].id }
        symbolPairs.removeAll { idsToDelete.contains($0.id) }
    }

    private func saveChanges() {
        let newMapping = Dictionary(
            uniqueKeysWithValues: symbolPairs
                .filter { !$0.from.isEmpty }
                .map { ($0.from, $0.to) }
        )
        profile.mapping = newMapping
        textTransformer.saveProfiles()
    }

    private func updateSymbolPairs() {
        symbolPairs = profile.mapping
            .map { SymbolPair(from: $0.key, to: $0.value) }
            .sorted { $0.from.localizedCaseInsensitiveCompare($1.from) == .orderedAscending }
    }
}
