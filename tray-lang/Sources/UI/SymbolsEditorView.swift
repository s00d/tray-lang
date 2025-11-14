import SwiftUI

// Вспомогательная структура для работы с List
struct SymbolPair: Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

struct SymbolsEditorView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProfileID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // -- Верхняя панель --
            HStack {
                Text("Conversion Profiles")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button("Done") {
                    // Перед закрытием сохраняем все несохраненные изменения
                    appCoordinator.textTransformer.saveProfiles()
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(height: 55)
            
            Divider()
            
            NavigationSplitView {
                // -- Левая панель (Список профилей) --
                ProfileListView(
                    textTransformer: appCoordinator.textTransformer,
                    selectedProfileID: $selectedProfileID
                )
                .navigationSplitViewColumnWidth(250)
            } detail: {
                // -- Правая панель (Редактор) --
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
                    Text("Select a profile to view or edit.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            selectedProfileID = appCoordinator.textTransformer.activeProfileID
        }
    }
}

// MARK: - Profile List (Левая панель)
struct ProfileListView: View {
    @ObservedObject var textTransformer: TextTransformer
    @Binding var selectedProfileID: UUID?
    
    var body: some View {
        List(selection: $selectedProfileID) {
            ForEach(textTransformer.profiles) { profile in
                HStack {
                    Image(systemName: profile.isEditable ? "pencil.and.scribble" : "lock.fill")
                        .foregroundColor(.secondary)
                    Text(profile.name)
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
        .toolbar {
            ToolbarItem {
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
                    Label("Add Profile", systemImage: "plus")
                }
                .help("Create a new profile")
            }
        }
    }
}

// MARK: - Profile Detail (Правая панель)
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
        // Используем VStack с spacing: 0 для полного контроля над компоновкой
        VStack(alignment: .leading, spacing: 0) {
            
            // --- 1. КОМПАКТНАЯ ШАПКА ---
            VStack(alignment: .leading, spacing: 12) {
                // Строка с названием и кнопками действий
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
                
                // Строка поиска
                TextField("Search symbols...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !profile.isEditable {
                    Text("This is a default profile. Duplicate it to make changes.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor)) // Фон, чтобы отделить от списка
            
            Divider()

            // --- 2. СПИСОК СИМВОЛОВ, ЗАНИМАЮЩИЙ ВСЕ МЕСТО ---
            // List теперь не имеет лишних отступов и занимает все доступное пространство
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
                .onDelete(perform: profile.isEditable ? deleteSymbol : nil) // Свайп для удаления
                
                if profile.isEditable {
                    Button("Add Symbol", systemImage: "plus") {
                        symbolPairs.append(SymbolPair(from: "", to: ""))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .disabled(!profile.isEditable)
            
            // --- 3. ФУТЕР ТОЛЬКО С ОДНОЙ КНОПКОЙ (если нужно) ---
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
        // textTransformer.updateProfile(profile) - не нужно, так как работаем с Binding
        // Но нужно сохранить все профили в UserDefaults
        textTransformer.saveProfiles()
    }
    
    private func updateSymbolPairs() {
        symbolPairs = profile.mapping
            .map { SymbolPair(from: $0.key, to: $0.value) }
            .sorted { $0.from.localizedCaseInsensitiveCompare($1.from) == .orderedAscending }
    }
}
