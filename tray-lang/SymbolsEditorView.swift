//
//  SymbolsEditorView.swift
//  tray-lang
//
//  Created by s00d on 01.08.2025.
//

import SwiftUI
import AppKit

struct SymbolsEditorView: View {
    @ObservedObject var trayLangManager: TrayLangManager
    @Environment(\.dismiss) private var dismiss
    @State private var newFromChar = ""
    @State private var newToChar = ""
    @State private var editingIndex: Int?
    @State private var editingFromChar = ""
    @State private var editingToChar = ""
    @State private var selectedPreset = "custom"
    
    let presets = [
        ("custom", "Custom"),
        ("russian_english", "Russian ↔ English"),
        ("german_english", "German ↔ English"),
        ("french_english", "French ↔ English"),
        ("spanish_english", "Spanish ↔ English"),
        ("italian_english", "Italian ↔ English"),
        ("portuguese_english", "Portuguese ↔ English"),
        ("swedish_english", "Swedish ↔ English"),
        ("norwegian_english", "Norwegian ↔ English"),
        ("danish_english", "Danish ↔ English"),
        ("finnish_english", "Finnish ↔ English"),
        ("polish_english", "Polish ↔ English"),
        ("czech_english", "Czech ↔ English"),
        ("hungarian_english", "Hungarian ↔ English"),
        ("turkish_english", "Turkish ↔ English"),
        ("greek_english", "Greek ↔ English"),
        ("cyrillic_english", "Cyrillic ↔ Latin")
    ]
    
    let presetMappings = [
        "russian_english": [
            // Строчные буквы
            ("й", "q"), ("ц", "w"), ("у", "e"), ("к", "r"), ("е", "t"), ("н", "y"), ("г", "u"), ("ш", "i"), ("щ", "o"), ("з", "p"),
            ("ф", "a"), ("ы", "s"), ("в", "d"), ("а", "f"), ("п", "g"), ("р", "h"), ("о", "j"), ("л", "k"), ("д", "l"),
            ("я", "z"), ("ч", "x"), ("с", "c"), ("м", "v"), ("и", "b"), ("т", "n"),
            // Заглавные буквы
            ("Й", "Q"), ("Ц", "W"), ("У", "E"), ("К", "R"), ("Е", "T"), ("Н", "Y"), ("Г", "U"), ("Ш", "I"), ("Щ", "O"), ("З", "P"),
            ("Ф", "A"), ("Ы", "S"), ("В", "D"), ("А", "F"), ("П", "G"), ("Р", "H"), ("О", "J"), ("Л", "K"), ("Д", "L"),
            ("Я", "Z"), ("Ч", "X"), ("С", "C"), ("М", "V"), ("И", "B"), ("Т", "N"),
            // Специальные символы
            ("ё", "`"), ("ъ", "'"), ("э", "["), ("х", "]"), ("ж", ";"), ("ь", "m"), ("б", ","), ("ю", "."),
            ("Ё", "~"), ("Ъ", "\""), ("Э", "{"), ("Х", "}"), ("Ж", ":"), ("Ь", "M"), ("Б", "<"), ("Ю", ">"),
            // Цифры и символы
            ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5", "5"), ("6", "6"), ("7", "7"), ("8", "8"), ("9", "9"), ("0", "0"),
            ("-", "-"), ("=", "="), ("[", "["), ("]", "]"), ("\\", "\\"), ("'", "'"), (",", ","), (".", "."), ("/", "/"),
            ("!", "!"), ("@", "@"), ("#", "#"), ("$", "$"), ("%", "%"), ("^", "^"), ("&", "&"), ("*", "*"), ("(", "("), (")", ")"),
            ("_", "_"), ("+", "+"), ("{", "{"), ("}", "}"), ("|", "|"), ("\"", "\""), ("<", "<"), (">", ">"), ("?", "?"),
            ("~", "~"), ("`", "`"), ("№", "#")
        ],
        "german_english": [
            ("ä", "a"), ("ö", "o"), ("ü", "u"), ("ß", "s"),
            ("Ä", "A"), ("Ö", "O"), ("Ü", "U")
        ],
        "french_english": [
            ("à", "a"), ("â", "a"), ("ä", "a"), ("ç", "c"), ("é", "e"),
            ("è", "e"), ("ê", "e"), ("ë", "e"), ("î", "i"), ("ï", "i"),
            ("ô", "o"), ("ù", "u"), ("û", "u"), ("ü", "u"), ("ÿ", "y"),
            ("À", "A"), ("Â", "A"), ("Ä", "A"), ("Ç", "C"), ("É", "E"),
            ("È", "E"), ("Ê", "E"), ("Ë", "E"), ("Î", "I"), ("Ï", "I"),
            ("Ô", "O"), ("Ù", "U"), ("Û", "U"), ("Ü", "U"), ("Ÿ", "Y")
        ],
        "spanish_english": [
            ("á", "a"), ("é", "e"), ("í", "i"), ("ñ", "n"), ("ó", "o"),
            ("ú", "u"), ("ü", "u"),
            ("Á", "A"), ("É", "E"), ("Í", "I"), ("Ñ", "N"), ("Ó", "O"),
            ("Ú", "U"), ("Ü", "U")
        ],
        "italian_english": [
            ("à", "a"), ("è", "e"), ("é", "e"), ("ì", "i"), ("í", "i"),
            ("ò", "o"), ("ó", "o"), ("ù", "u"), ("ú", "u"),
            ("À", "A"), ("È", "E"), ("É", "E"), ("Ì", "I"), ("Í", "I"),
            ("Ò", "O"), ("Ó", "O"), ("Ù", "U"), ("Ú", "U")
        ],
        "portuguese_english": [
            ("á", "a"), ("à", "a"), ("â", "a"), ("ã", "a"), ("ç", "c"),
            ("é", "e"), ("ê", "e"), ("í", "i"), ("ó", "o"), ("ô", "o"),
            ("õ", "o"), ("ú", "u"),
            ("Á", "A"), ("À", "A"), ("Â", "A"), ("Ã", "A"), ("Ç", "C"),
            ("É", "E"), ("Ê", "E"), ("Í", "I"), ("Ó", "O"), ("Ô", "O"),
            ("Õ", "O"), ("Ú", "U")
        ],
        "swedish_english": [
            ("å", "a"), ("ä", "a"), ("ö", "o"),
            ("Å", "A"), ("Ä", "A"), ("Ö", "O")
        ],
        "norwegian_english": [
            ("å", "a"), ("æ", "a"), ("ø", "o"),
            ("Å", "A"), ("Æ", "A"), ("Ø", "O")
        ],
        "danish_english": [
            ("å", "a"), ("æ", "a"), ("ø", "o"),
            ("Å", "A"), ("Æ", "A"), ("Ø", "O")
        ],
        "finnish_english": [
            ("ä", "a"), ("ö", "o"), ("å", "a"),
            ("Ä", "A"), ("Ö", "O"), ("Å", "A")
        ],
        "polish_english": [
            ("ą", "a"), ("ć", "c"), ("ę", "e"), ("ł", "l"), ("ń", "n"),
            ("ó", "o"), ("ś", "s"), ("ź", "z"), ("ż", "z"),
            ("Ą", "A"), ("Ć", "C"), ("Ę", "E"), ("Ł", "L"), ("Ń", "N"),
            ("Ó", "O"), ("Ś", "S"), ("Ź", "Z"), ("Ż", "Z")
        ],
        "czech_english": [
            ("á", "a"), ("č", "c"), ("ď", "d"), ("é", "e"), ("ě", "e"),
            ("í", "i"), ("ň", "n"), ("ó", "o"), ("ř", "r"), ("š", "s"),
            ("ť", "t"), ("ú", "u"), ("ů", "u"), ("ý", "y"), ("ž", "z"),
            ("Á", "A"), ("Č", "C"), ("Ď", "D"), ("É", "E"), ("Ě", "E"),
            ("Í", "I"), ("Ň", "N"), ("Ó", "O"), ("Ř", "R"), ("Š", "S"),
            ("Ť", "T"), ("Ú", "U"), ("Ů", "U"), ("Ý", "Y"), ("Ž", "Z")
        ],
        "hungarian_english": [
            ("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ö", "o"),
            ("ő", "o"), ("ú", "u"), ("ü", "u"), ("ű", "u"),
            ("Á", "A"), ("É", "E"), ("Í", "I"), ("Ó", "O"), ("Ö", "O"),
            ("Ő", "O"), ("Ú", "U"), ("Ü", "U"), ("Ű", "U")
        ],
        "turkish_english": [
            ("ç", "c"), ("ğ", "g"), ("ı", "i"), ("ö", "o"), ("ş", "s"),
            ("ü", "u"),
            ("Ç", "C"), ("Ğ", "G"), ("I", "I"), ("Ö", "O"), ("Ş", "S"),
            ("Ü", "U")
        ],
        "greek_english": [
            ("α", "a"), ("β", "b"), ("γ", "g"), ("δ", "d"), ("ε", "e"),
            ("ζ", "z"), ("η", "h"), ("θ", "t"), ("ι", "i"), ("κ", "k"),
            ("λ", "l"), ("μ", "m"), ("ν", "n"), ("ξ", "x"), ("ο", "o"),
            ("π", "p"), ("ρ", "r"), ("σ", "s"), ("τ", "t"), ("υ", "u"),
            ("φ", "f"), ("χ", "c"), ("ψ", "p"), ("ω", "o"),
            ("Α", "A"), ("Β", "B"), ("Γ", "G"), ("Δ", "D"), ("Ε", "E"),
            ("Ζ", "Z"), ("Η", "H"), ("Θ", "T"), ("Ι", "I"), ("Κ", "K"),
            ("Λ", "L"), ("Μ", "M"), ("Ν", "N"), ("Ξ", "X"), ("Ο", "O"),
            ("Π", "P"), ("Ρ", "R"), ("Σ", "S"), ("Τ", "T"), ("Υ", "U"),
            ("Φ", "F"), ("Χ", "C"), ("Ψ", "P"), ("Ω", "O")
        ],
        "cyrillic_english": [
            // Строчные буквы
            ("й", "q"), ("ц", "w"), ("у", "e"), ("к", "r"), ("е", "t"), ("н", "y"), ("г", "u"), ("ш", "i"), ("щ", "o"), ("з", "p"),
            ("ф", "a"), ("ы", "s"), ("в", "d"), ("а", "f"), ("п", "g"), ("р", "h"), ("о", "j"), ("л", "k"), ("д", "l"),
            ("я", "z"), ("ч", "x"), ("с", "c"), ("м", "v"), ("и", "b"), ("т", "n"),
            // Заглавные буквы
            ("Й", "Q"), ("Ц", "W"), ("У", "E"), ("К", "R"), ("Е", "T"), ("Н", "Y"), ("Г", "U"), ("Ш", "I"), ("Щ", "O"), ("З", "P"),
            ("Ф", "A"), ("Ы", "S"), ("В", "D"), ("А", "F"), ("П", "G"), ("Р", "H"), ("О", "J"), ("Л", "K"), ("Д", "L"),
            ("Я", "Z"), ("Ч", "X"), ("С", "C"), ("М", "V"), ("И", "B"), ("Т", "N"),
            // Специальные символы
            ("ё", "`"), ("ъ", "'"), ("э", "["), ("х", "]"), ("ж", ";"), ("ь", "m"), ("б", ","), ("ю", "."),
            ("Ё", "~"), ("Ъ", "\""), ("Э", "{"), ("Х", "}"), ("Ж", ":"), ("Ь", "M"), ("Б", "<"), ("Ю", ">"),
            // Цифры и символы
            ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5", "5"), ("6", "6"), ("7", "7"), ("8", "8"), ("9", "9"), ("0", "0"),
            ("-", "-"), ("=", "="), ("[", "["), ("]", "]"), ("\\", "\\"), ("'", "'"), (",", ","), (".", "."), ("/", "/"),
            ("!", "!"), ("@", "@"), ("#", "#"), ("$", "$"), ("%", "%"), ("^", "^"), ("&", "&"), ("*", "*"), ("(", "("), (")", ")"),
            ("_", "_"), ("+", "+"), ("{", "{"), ("}", "}"), ("|", "|"), ("\"", "\""), ("<", "<"), (">", ">"), ("?", "?"),
            ("~", "~"), ("`", "`"), ("№", "#")
        ]
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Symbols Editor")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("✕") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            // Ready-made symbol blocks
            VStack(alignment: .leading, spacing: 8) {
                Text("Ready-made blocks:")
                    .font(.headline)
                
                Picker("Select block", selection: $selectedPreset) {
                    ForEach(presets, id: \.0) { preset in
                        Text(preset.1).tag(preset.0)
                    }
                }
                .pickerStyle(.menu)
                
                if selectedPreset != "custom" {
                    Button("Add selected block") {
                        addPresetMappings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Adding symbols
            VStack(alignment: .leading, spacing: 12) {
                Text("Add symbol mapping:")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Symbol", text: $newFromChar)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Symbol", text: $newToChar)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("")
                            .font(.caption)
                            .foregroundColor(.clear)
                        Button("Add") {
                            if !newFromChar.isEmpty && !newToChar.isEmpty {
                                let lowerFrom = newFromChar.lowercased()
                                let lowerTo = newToChar.lowercased()
                                trayLangManager.addSymbolMapping(from: lowerFrom, to: lowerTo)
                                newFromChar = ""
                                newToChar = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newFromChar.isEmpty || newToChar.isEmpty)
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Symbol list
            VStack(alignment: .leading, spacing: 8) {
                Text("Current symbol mappings:")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(trayLangManager.fromToMapping.keys.sorted()), id: \.self) { from in
                            if let to = trayLangManager.fromToMapping[from] {
                                if editingIndex == Array(trayLangManager.fromToMapping.keys.sorted()).firstIndex(of: from) {
                                    // Editing mode
                                    HStack {
                                        TextField("From", text: $editingFromChar)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        
                                        Text("→")
                                            .font(.body)
                                        
                                        TextField("To", text: $editingToChar)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        
                                        Spacer()
                                        
                                        Button("✓") {
                                            if !editingFromChar.isEmpty && !editingToChar.isEmpty {
                                                let lowerFrom = editingFromChar.lowercased()
                                                let lowerTo = editingToChar.lowercased()
                                                trayLangManager.updateSymbolMapping(from: lowerFrom, to: lowerTo)
                                                editingIndex = nil
                                                editingFromChar = ""
                                                editingToChar = ""
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.green)
                                        
                                        Button("✗") {
                                            editingIndex = nil
                                            editingFromChar = ""
                                            editingToChar = ""
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.red)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                } else {
                                    // Display mode
                                    HStack {
                                        Text("\(from) → \(to)")
                                            .font(.body)
                                        
                                        Spacer()
                                        
                                        Button("✏️") {
                                            editingIndex = Array(trayLangManager.fromToMapping.keys.sorted()).firstIndex(of: from)
                                            editingFromChar = from
                                            editingToChar = to
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button("🗑️") {
                                            trayLangManager.removeSymbolMapping(from: from)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Close button
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400, height: 500)
    }
    
    private func addPresetMappings() {
        guard selectedPreset != "custom" else { return }
        
        if let mappings = presetMappings[selectedPreset] {
            for (from, to) in mappings {
                let lowerFrom = from.lowercased()
                let lowerTo = to.lowercased()
                trayLangManager.addSymbolMapping(from: lowerFrom, to: lowerTo)
            }
        }
    }
} 