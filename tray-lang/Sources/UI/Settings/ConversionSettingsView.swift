import SwiftUI
import AppKit

struct ConversionSettingsView: View {
    @ObservedObject var transformer: TextTransformer

    @State private var sample = "ghbdtn vbh — руддщ цщкдв"
    /// Draft shown in the editor sheet; `isNew` drafts are added on Save, never before.
    @State private var editing: EditorDraft?
    @State private var profilePendingDelete: ConversionProfile?
    @State private var choosingLayout = false

    struct EditorDraft: Identifiable {
        var profile: ConversionProfile
        let isNew: Bool
        var id: String { profile.id }
    }

    private var active: ConversionProfile { transformer.activeProfile }
    private var resolved: TextTransformer.ResolvedProfile? { transformer.resolvedProfile(for: active) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Profile") {
                    ProfileMenu(transformer: transformer, onOtherLayout: { choosingLayout = true }, onNewCustom: startNewProfile)
                }
                LabeledContent("Converts") {
                    Text(pairDescription)
                        .foregroundStyle(resolved == nil ? .orange : .secondary)
                }
            } footer: {
                Text(footerText)
            }

            Section("Try It") {
                TextField("Type or paste text in the wrong layout", text: $sample, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...5)
                HStack(alignment: .firstTextBaseline) {
                    Text(result.isEmpty ? " " : result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    }
                    .controlSize(.small)
                    .disabled(result.isEmpty)
                }
            }

            if let resolved, !active.isEditable {
                Section {
                    KeyboardPreview(sourceLayoutID: resolved.sourceLayoutID, targetLayoutID: resolved.targetLayoutID)
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Big character: what the key types on \(layoutName(resolved.targetLayoutID)). Small: on \(layoutName(resolved.sourceLayoutID)). Highlighted keys are converted.")
                }
            }

            Section {
                if transformer.customProfiles.isEmpty {
                    Text("Need a different table? Start from any macOS layout and change only the keys you need.")
                        .foregroundStyle(.secondary)
                }
                ForEach(transformer.customProfiles) { profile in
                    HStack {
                        Image(systemName: profile.id == transformer.activeProfileID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(profile.id == transformer.activeProfileID ? Color.accentColor : .secondary)
                            .onTapGesture { transformer.activeProfileID = profile.id }
                            .help("Use this profile")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                            Text("\(profile.mapping.count) key pairs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") { editing = EditorDraft(profile: profile, isNew: false) }
                            .controlSize(.small)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Use") { transformer.activeProfileID = profile.id }
                        Button("Edit…") { editing = EditorDraft(profile: profile, isNew: false) }
                        Button("Duplicate") { transformer.duplicateProfile(profile) }
                        Divider()
                        Button("Delete…", role: .destructive) { profilePendingDelete = profile }
                    }
                }
            } header: {
                HStack {
                    Text("Custom Profiles")
                    Spacer()
                    Button("New…", action: startNewProfile)
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $choosingLayout) {
            LayoutChooser(title: "Convert Between ABC and…") { layoutID in
                transformer.activeProfileID = ConversionProfile.system(target: layoutID).id
            }
        }
        .sheet(item: $editing) { draft in
            CustomProfileEditor(transformer: transformer, draft: draft.profile, isNew: draft.isNew)
        }
        .confirmationDialog(
            "Delete “\(profilePendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { profilePendingDelete != nil }, set: { if !$0 { profilePendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let profile = profilePendingDelete { transformer.deleteProfile(id: profile.id) }
            }
        } message: {
            Text("If it is in use, conversion switches back to Auto.")
        }
    }

    private var result: String { transformer.transformText(sample) }

    private func startNewProfile() {
        // Start from what the user converts with now; the editor can refill it from any layout.
        let base = transformer.mapping(of: active)
        editing = EditorDraft(profile: .custom(name: "My Custom Profile", mapping: base), isNew: true)
    }

    private func layoutName(_ id: String?) -> String {
        id.flatMap(SystemKeyboardLayouts.localizedName(ofLayoutID:)) ?? id ?? "?"
    }

    private var pairDescription: String {
        guard let resolved else { return active.isAuto ? "Enable a second input source" : "Nothing — the table is empty" }
        if active.isEditable { return "Custom table (\(active.mapping.count) keys)" }
        return "\(layoutName(resolved.sourceLayoutID)) ⇄ \(layoutName(resolved.targetLayoutID))"
    }

    private var footerText: String {
        if active.isAuto {
            return "Auto pairs your latin layout with the first other layout in System Settings › Keyboard › Input Sources, and follows changes there."
        }
        if active.isEditable {
            return "Letters flip to the other side; punctuation follows the word it's in."
        }
        return "Key tables come straight from macOS, so they match what your keyboard types."
    }
}

// MARK: - Profile menu

/// Picker-style menu: Auto, the user's layouts, common macOS layouts, all layouts, custom profiles.
private struct ProfileMenu: View {
    @ObservedObject var transformer: TextTransformer
    let onOtherLayout: () -> Void
    let onNewCustom: () -> Void

    var body: some View {
        let builtIns = transformer.builtInProfiles()
        let enabled = Set(SystemKeyboardLayouts.enabledLayoutIDs())
        Menu(title) {
            Picker("Profile", selection: $transformer.activeProfileID) {
                Text("Auto").tag(ConversionProfile.autoID)
                Section("Your Input Sources") {
                    ForEach(builtIns.filter { $0.targetLayoutID.map(enabled.contains) == true }) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                Section("Common Layouts") {
                    ForEach(builtIns.filter { !$0.isAuto && $0.targetLayoutID.map(enabled.contains) != true }) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                if !transformer.customProfiles.isEmpty {
                    Section("Custom") {
                        ForEach(transformer.customProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                }
            }
            .pickerStyle(.inline)

            Divider()
            Button("Other macOS Layout…", action: onOtherLayout)
            Button("New Custom Profile…", action: onNewCustom)
        }
        .fixedSize()
    }

    private var title: String {
        let profile = transformer.activeProfile
        return profile.isAuto ? "Auto" : profile.name
    }
}

// MARK: - Keyboard preview

/// The keyboard with both layouts printed on each key, so it is obvious what a key turns into.
struct KeyboardPreview: View {
    let sourceLayoutID: String?
    let targetLayoutID: String?
    @State private var shifted = false

    private static let rows: [(keys: [UInt16], indent: CGFloat)] = {
        let codes = SystemKeyboardLayouts.printableKeyCodes
        return [(Array(codes[0..<13]), 0), (Array(codes[13..<26]), 14), (Array(codes[26..<37]), 20), (Array(codes[37..<47]), 32)]
    }()

    var body: some View {
        let source = SystemKeyboardLayouts.keyTable(layoutID: sourceLayoutID ?? SystemKeyboardLayouts.abcLayoutID) ?? [:]
        let target = targetLayoutID.flatMap(SystemKeyboardLayouts.keyTable(layoutID:)) ?? [:]
        VStack(alignment: .leading, spacing: 8) {
            Picker("Layer", selection: $shifted) {
                Text("Normal").tag(false)
                Text("⇧ Shift").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Self.rows.indices, id: \.self) { index in
                    let row = Self.rows[index]
                    HStack(spacing: 3) {
                        ForEach(row.keys, id: \.self) { code in
                            KeyCap(source: output(source[code]), target: output(target[code]))
                        }
                    }
                    .padding(.leading, row.indent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    private func output(_ key: SystemKeyboardLayouts.KeyOutput?) -> String {
        (shifted ? key?.shifted : key?.plain) ?? ""
    }
}

private struct KeyCap: View {
    let source: String
    let target: String

    private var changes: Bool { !target.isEmpty && target != source }

    var body: some View {
        VStack(spacing: 0) {
            Text(target.isEmpty ? " " : target)
                .font(.system(size: 14, weight: .medium))
            Text(source.isEmpty ? " " : source)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(changes ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
        )
        .help(changes ? "\(source) → \(target)" : "Same on both layouts")
    }
}

// MARK: - Layout chooser

/// Every installed macOS layout, searchable. A lazy List: hundreds of rows, only visible ones are built.
struct LayoutChooser: View {
    let title: String
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @State private var layouts: [(id: String, name: String)] = []

    private var filtered: [(id: String, name: String)] {
        query.isEmpty ? layouts : layouts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.top, .horizontal], 16)
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(16)
            List(filtered, id: \.id, selection: $selection) { layout in
                Text(layout.name).tag(layout.id)
            }
            .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
                choose(ids.first)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose") { choose(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding(16)
        }
        .frame(width: 380, height: 480)
        .onAppear { layouts = SystemKeyboardLayouts.allInstalledLayouts() }
    }

    private func choose(_ id: String?) {
        guard let id else { return }
        onChoose(id)
        dismiss()
    }
}
