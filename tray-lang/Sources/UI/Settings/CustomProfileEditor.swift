import SwiftUI

/// Sheet for creating or editing a custom profile. Nothing is saved until Save.
struct CustomProfileEditor: View {
    @ObservedObject var transformer: TextTransformer
    let isNew: Bool
    private let original: ConversionProfile

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var rows: [Row]
    @State private var selection = Set<Row.ID>()
    @State private var filter = ""
    @State private var sample = ""

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var output: String
    }

    init(transformer: TextTransformer, draft: ConversionProfile, isNew: Bool) {
        self.transformer = transformer
        self.isNew = isNew
        original = draft
        _name = State(initialValue: draft.name)
        _rows = State(initialValue: Self.rows(from: draft.mapping))
    }

    private static func rows(from mapping: [String: String]) -> [Row] {
        mapping
            .map { Row(key: $0.key, output: $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    // MARK: Derived state

    private var mapping: [String: String] {
        Dictionary(rows.filter { !$0.key.isEmpty && !$0.output.isEmpty }.map { ($0.key, $0.output) }, uniquingKeysWith: { _, last in last })
    }

    private var duplicateKeys: Set<String> {
        var seen = Set<String>(), duplicates = Set<String>()
        for row in rows where !row.key.isEmpty {
            if !seen.insert(row.key).inserted { duplicates.insert(row.key) }
        }
        return duplicates
    }

    private var incompleteCount: Int {
        rows.filter { $0.key.isEmpty != $0.output.isEmpty }.count
    }

    private var visibleRows: Binding<[Row]> {
        guard !filter.isEmpty else { return $rows }
        return Binding(
            get: { rows.filter { $0.key.localizedCaseInsensitiveContains(filter) || $0.output.localizedCaseInsensitiveContains(filter) } },
            set: { edited in
                for row in edited {
                    if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
                }
            }
        )
    }

    private var preview: String {
        guard !sample.isEmpty else { return "" }
        let resolved = TextTransformer.ResolvedProfile(forward: mapping, sourceLayoutID: nil, targetLayoutID: nil)
        return TextTransformer.convert(sample, using: resolved).text
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !mapping.isEmpty
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)
                LabeledContent("Start from") {
                    FillFromLayoutMenu(transformer: transformer) { replacement in
                        rows = Self.rows(from: replacement)
                        selection.removeAll()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Keys").font(.headline)
                    Spacer()
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                Table(visibleRows, selection: $selection) {
                    TableColumn("Key") { $row in
                        TextField("e.g. q", text: $row.key)
                            .font(.body.monospaced())
                            .foregroundStyle(duplicateKeys.contains(row.key) ? .orange : .primary)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Becomes") { $row in
                        TextField("e.g. й", text: $row.output)
                            .font(.body.monospaced())
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("") { $row in
                        if duplicateKeys.contains(row.key) {
                            Label("Duplicate key", systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.orange)
                                .help("This key is listed more than once; the last row wins.")
                        }
                    }
                    .width(24)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 200)
                .onDeleteCommand(perform: deleteSelected)

                HStack(spacing: 0) {
                    Button { addRow() } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                        .help("Add a key")
                    Button { deleteSelected() } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                        .help("Remove selected keys")
                        .disabled(selection.isEmpty)
                    Spacer()
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(duplicateKeys.isEmpty && incompleteCount == 0 ? Color.secondary : .orange)
                }
                .buttonStyle(.borderless)

                HStack(alignment: .firstTextBaseline) {
                    TextField("Try it", text: $sample)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(preview.isEmpty ? "—" : preview)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()
            HStack {
                if !isNew {
                    Text("Changes apply when you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 520, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var status: String {
        var parts = ["\(mapping.count) keys"]
        if !duplicateKeys.isEmpty { parts.append("\(duplicateKeys.count) duplicated") }
        if incompleteCount > 0 { parts.append("\(incompleteCount) incomplete, ignored") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func addRow() {
        filter = ""
        let row = Row(key: "", output: "")
        rows.insert(row, at: 0)
        selection = [row.id]
    }

    private func deleteSelected() {
        rows.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func save() {
        var profile = original
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.mapping = mapping
        if isNew {
            transformer.activeProfileID = transformer.addCustomProfile(profile).id
        } else {
            transformer.updateProfile(profile)
        }
        dismiss()
    }
}

/// Replaces the table with the one of a macOS layout (or another profile).
private struct FillFromLayoutMenu: View {
    @ObservedObject var transformer: TextTransformer
    let onPick: ([String: String]) -> Void
    @State private var choosingLayout = false

    var body: some View {
        Menu("Fill From…") {
            ForEach(transformer.builtInProfiles()) { profile in
                Button(profile.isAuto ? "Auto (current input sources)" : profile.name) {
                    onPick(transformer.mapping(of: profile))
                }
            }
            if !transformer.customProfiles.isEmpty {
                Divider()
                ForEach(transformer.customProfiles) { profile in
                    Button(profile.name) { onPick(profile.mapping) }
                }
            }
            Divider()
            Button("Other macOS Layout…") { choosingLayout = true }
            Divider()
            Button("Empty Table") { onPick([:]) }
        }
        .fixedSize()
        .help("Replace the keys below with another table")
        .sheet(isPresented: $choosingLayout) {
            LayoutChooser(title: "Fill From Layout") { layoutID in
                onPick(transformer.mapping(of: .system(target: layoutID)))
            }
        }
    }
}
