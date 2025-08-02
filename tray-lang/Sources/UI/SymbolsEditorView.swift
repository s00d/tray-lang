//
//  SymbolsEditorView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI

struct SymbolsEditorView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var mapping: [(String, String)] = []
    @State private var selectedLanguage = "Russian (QWERTY → ЙЦУКЕН)"
    @State private var showingTemplateConfirmation = false
    @State private var pendingTemplateLanguage: String?
    
    let languageTemplates: [String: [(String, String)]] = [
        "Russian (QWERTY → ЙЦУКЕН)": [
            // Строчные буквы
            ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"), ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
            ("a", "ф"), ("s", "ы"), ("d", "в"), ("f", "а"), ("g", "п"), ("h", "р"), ("j", "о"), ("k", "л"), ("l", "д"), (";", "ж"),
            ("z", "я"), ("x", "ч"), ("c", "с"), ("v", "м"), ("b", "и"), ("n", "т"), ("m", "ь"), (",", "б"), (".", "ю"), ("/", "."),
            // Заглавные буквы
            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"), ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("A", "Ф"), ("S", "Ы"), ("D", "В"), ("F", "А"), ("G", "П"), ("H", "Р"), ("J", "О"), ("K", "Л"), ("L", "Д"), (":", "Ж"),
            ("Z", "Я"), ("X", "Ч"), ("C", "С"), ("V", "М"), ("B", "И"), ("N", "Т"), ("M", "Ь"), ("<", "Б"), (">", "Ю"), ("?", ","),
            // Цифры и символы
            ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5", "5"), ("6", "6"), ("7", "7"), ("8", "8"), ("9", "9"), ("0", "0"),
            ("`", "ё"), ("~", "Ё"), ("[", "х"), ("]", "ъ"), ("\\", "/"), ("{", "Х"), ("}", "Ъ"), ("|", "/"),
            ("'", "э"), ("\"", "Э"), ("-", "-"), ("=", "="), ("_", "_"), ("+", "+")
        ],
        "Ukrainian (QWERTY → ЙЦУКЕН)": [
            // Строчные буквы
            ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"), ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
            ("a", "ф"), ("s", "і"), ("d", "в"), ("f", "а"), ("g", "п"), ("h", "р"), ("j", "о"), ("k", "л"), ("l", "д"), (";", "ж"),
            ("z", "я"), ("x", "ч"), ("c", "с"), ("v", "м"), ("b", "и"), ("n", "т"), ("m", "ь"), (",", "б"), (".", "ю"), ("/", "."),
            // Заглавные буквы
            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"), ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("A", "Ф"), ("S", "І"), ("D", "В"), ("F", "А"), ("G", "П"), ("H", "Р"), ("J", "О"), ("K", "Л"), ("L", "Д"), (":", "Ж"),
            ("Z", "Я"), ("X", "Ч"), ("C", "С"), ("V", "М"), ("B", "И"), ("N", "Т"), ("M", "Ь"), ("<", "Б"), (">", "Ю"), ("?", ","),
            // Дополнительные украинские буквы
            ("`", "ґ"), ("~", "Ґ"), ("'", "є"), ("\"", "Є"), ("[", "ї"), ("]", "ї"), ("{", "Ї"), ("}", "Ї")
        ],
        "German (QWERTY → QWERTZ)": [
            ("y", "z"), ("z", "y"), ("Y", "Z"), ("Z", "Y"),
            ("ä", "ä"), ("ö", "ö"), ("ü", "ü"), ("ß", "ß"),
            ("Ä", "Ä"), ("Ö", "Ö"), ("Ü", "Ü")
        ],
        "French (QWERTY → AZERTY)": [
            ("q", "a"), ("w", "z"), ("a", "q"), ("z", "w"),
            ("Q", "A"), ("W", "Z"), ("A", "Q"), ("Z", "W"),
            (";", "m"), ("m", ";"), (":", "M"), ("M", ":"),
            ("à", "à"), ("â", "â"), ("ä", "ä"), ("ç", "ç"), ("é", "é"), ("è", "è"),
            ("ê", "ê"), ("ë", "ë"), ("î", "î"), ("ï", "ï"), ("ô", "ô"), ("ù", "ù"),
            ("û", "û"), ("ü", "ü"), ("ÿ", "ÿ")
        ],
        "Spanish (QWERTY → Spanish)": [
            ("á", "á"), ("é", "é"), ("í", "í"), ("ñ", "ñ"), ("ó", "ó"), ("ú", "ú"),
            ("ü", "ü"), ("¿", "¿"), ("¡", "¡"),
            ("Á", "Á"), ("É", "É"), ("Í", "Í"), ("Ñ", "Ñ"), ("Ó", "Ó"), ("Ú", "Ú"),
            ("Ü", "Ü")
        ],
        "Italian (QWERTY → Italian)": [
            ("à", "à"), ("è", "è"), ("é", "é"), ("ì", "ì"), ("ò", "ò"), ("ù", "ù"),
            ("À", "À"), ("È", "È"), ("É", "É"), ("Ì", "Ì"), ("Ò", "Ò"), ("Ù", "Ù")
        ],
        "Polish (QWERTY → Polish)": [
            ("ą", "ą"), ("ć", "ć"), ("ę", "ę"), ("ł", "ł"), ("ń", "ń"), ("ó", "ó"),
            ("ś", "ś"), ("ź", "ź"), ("ż", "ż"),
            ("Ą", "Ą"), ("Ć", "Ć"), ("Ę", "Ę"), ("Ł", "Ł"), ("Ń", "Ń"), ("Ó", "Ó"),
            ("Ś", "Ś"), ("Ź", "Ź"), ("Ż", "Ż")
        ],
        "Czech (QWERTY → Czech)": [
            ("á", "á"), ("č", "č"), ("ď", "ď"), ("é", "é"), ("ě", "ě"), ("í", "í"),
            ("ň", "ň"), ("ó", "ó"), ("ř", "ř"), ("š", "š"), ("ť", "ť"), ("ú", "ú"),
            ("ů", "ů"), ("ý", "ý"), ("ž", "ž"),
            ("Á", "Á"), ("Č", "Č"), ("Ď", "Ď"), ("É", "É"), ("Ě", "Ě"), ("Í", "Í"),
            ("Ň", "Ň"), ("Ó", "Ó"), ("Ř", "Ř"), ("Š", "Š"), ("Ť", "Ť"), ("Ú", "Ú"),
            ("Ů", "Ů"), ("Ý", "Ý"), ("Ž", "Ž")
        ],
        "Hungarian (QWERTY → Hungarian)": [
            ("á", "á"), ("é", "é"), ("í", "í"), ("ó", "ó"), ("ö", "ö"), ("ő", "ő"),
            ("ú", "ú"), ("ü", "ü"), ("ű", "ű"),
            ("Á", "Á"), ("É", "É"), ("Í", "Í"), ("Ó", "Ó"), ("Ö", "Ö"), ("Ő", "Ő"),
            ("Ú", "Ú"), ("Ü", "Ü"), ("Ű", "Ű")
        ],
        "Turkish (QWERTY → Turkish)": [
            ("ç", "ç"), ("ğ", "ğ"), ("ı", "ı"), ("ö", "ö"), ("ş", "ş"), ("ü", "ü"),
            ("Ç", "Ç"), ("Ğ", "Ğ"), ("I", "I"), ("İ", "İ"), ("Ö", "Ö"), ("Ş", "Ş"),
            ("Ü", "Ü")
        ]
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Symbols Editor")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("✕") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()
            Divider()
            
            VStack(spacing: 20) {
                // Template selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Array(languageTemplates.keys.sorted()), id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .onChange(of: selectedLanguage) { oldValue, newLanguage in
                        if newLanguage != "Russian (QWERTY → ЙЦУКЕН)" && !mapping.isEmpty {
                            pendingTemplateLanguage = newLanguage
                            showingTemplateConfirmation = true
                        }
                    }
                }
                .padding(.horizontal)
                
                // Symbols grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("Symbol Mappings")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150))], spacing: 12) {
                            ForEach(Array(mapping.enumerated()), id: \.offset) { index, pair in
                                EditableSymbolView(
                                    fromSymbol: pair.0,
                                    toSymbol: pair.1,
                                    onFromChanged: { newFrom in
                                        mapping[index] = (newFrom, pair.1)
                                    },
                                    onToChanged: { newTo in
                                        mapping[index] = (pair.0, newTo)
                                    },
                                    onDelete: {
                                        mapping.remove(at: index)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 300)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical)
            
            Divider()
            
            HStack {
                Button("Add symbol") {
                    mapping.append(("", ""))
                }
                .buttonStyle(.bordered)
                
                Button("Reset") {
                    mapping = KeyboardMapping.defaultMapping.map { ($0.key, $0.value) }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    let newMapping = Dictionary(uniqueKeysWithValues: mapping)
                    appCoordinator.textTransformer.updateMapping(newMapping)
                    appCoordinator.textTransformer.saveSymbols()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showingTemplateConfirmation) {
            if let language = pendingTemplateLanguage,
               let template = languageTemplates[language] {
                TemplateConfirmationView(
                    language: language,
                    template: template,
                    onConfirm: {
                        mapping = template
                        selectedLanguage = language
                        showingTemplateConfirmation = false
                        pendingTemplateLanguage = nil
                    },
                    onCancel: {
                        selectedLanguage = "Russian (QWERTY → ЙЦУКЕН)"
                        showingTemplateConfirmation = false
                        pendingTemplateLanguage = nil
                    }
                )
            }
        }
        .onAppear {
            let currentMapping = appCoordinator.textTransformer.fromToMapping
            mapping = currentMapping.map { ($0.key, $0.value) }
        }
    }
}

struct TemplateConfirmationView: View {
    let language: String
    let template: [(String, String)]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Apply Template")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("✕") { onCancel() }
                    .buttonStyle(.plain)
            }
            .padding()
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("This will replace all current symbol mappings with the \(language) template.")
                    .font(.body)
                
                Text("Template contains \(template.count) symbols:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                        ForEach(template.prefix(20), id: \.0) { from, to in
                            HStack(spacing: 4) {
                                Text(from)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                                
                                Text("→")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(to)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                
                if template.count > 20 {
                    Text("... and \(template.count - 20) more symbols")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Apply Template") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}

struct EditableSymbolView: View {
    let fromSymbol: String
    let toSymbol: String
    let onFromChanged: (String) -> Void
    let onToChanged: (String) -> Void
    let onDelete: () -> Void
    
    @State private var tempFromSymbol: String
    @State private var tempToSymbol: String
    
    init(fromSymbol: String, toSymbol: String, onFromChanged: @escaping (String) -> Void, onToChanged: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.fromSymbol = fromSymbol
        self.toSymbol = toSymbol
        self.onFromChanged = onFromChanged
        self.onToChanged = onToChanged
        self.onDelete = onDelete
        self._tempFromSymbol = State(initialValue: fromSymbol)
        self._tempToSymbol = State(initialValue: toSymbol)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                // From symbol - всегда редактируемое поле
                TextField("", text: $tempFromSymbol)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                    .textFieldStyle(.plain)
                    .onChange(of: tempFromSymbol) { _, newValue in
                        if newValue != fromSymbol {
                            onFromChanged(newValue)
                        }
                    }
                
                Text("→")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                // To symbol - всегда редактируемое поле
                TextField("", text: $tempToSymbol)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    .textFieldStyle(.plain)
                    .onChange(of: tempToSymbol) { _, newValue in
                        if newValue != toSymbol {
                            onToChanged(newValue)
                        }
                    }
                
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onChange(of: fromSymbol) { _, newValue in
            tempFromSymbol = newValue
        }
        .onChange(of: toSymbol) { _, newValue in
            tempToSymbol = newValue
        }
    }
} 