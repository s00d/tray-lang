import Foundation

// MARK: - Text Transformer
class TextTransformer: ObservableObject {
    @Published var fromToMapping: [String: String] = KeyboardMapping.defaultMapping
    private var toFromMapping: [String: String] = [:]
    
    init() {
        setupToFromMapping()
    }
    
    // MARK: - Mapping Setup
    private func setupToFromMapping() {
        toFromMapping = KeyboardMapping.createInverseMapping(from: fromToMapping)
    }
    
    // MARK: - Text Transformation
    func transformText(_ text: String) -> String {
        var result = ""
        
        for char in text {
            let charString = String(char)
            
            // Сначала пробуем конвертировать русские в английские
            if let mapped = fromToMapping[charString] {
                print("✅ Конвертируем русский '\(charString)' → английский '\(mapped)'")
                result += mapped
            } else if let mapped = toFromMapping[charString] {
                // Если не нашли в fromToMapping, пробуем английские в русские
                print("✅ Конвертируем английский '\(charString)' → русский '\(mapped)'")
                result += mapped
            } else {
                // Если нет в маппинге - оставляем как есть
                result += charString
            }
        }
        
        return result
    }
    
    // MARK: - Language Detection
    func detectLanguage(_ text: String) -> Bool {
        // В новой логике каждая буква обрабатывается отдельно
        let textChars = Set(text.lowercased().map { String($0) })
        let russianCount = textChars.intersection(fromToMapping.keys).count
        let englishCount = textChars.intersection(toFromMapping.keys).count
        
        return russianCount > englishCount
    }
    
    // MARK: - Mapping Management
    func updateMapping(_ newMapping: [String: String]) {
        fromToMapping = newMapping
        setupToFromMapping()
    }
    
    func loadSymbols() {
        if let savedMapping = UserDefaults.standard.object(forKey: "customSymbols") as? Data {
            do {
                let decoder = JSONDecoder()
                let customMapping = try decoder.decode([String: String].self, from: savedMapping)
                fromToMapping.merge(customMapping) { _, new in new }
                setupToFromMapping()
            } catch {
                print("❌ Ошибка загрузки пользовательских символов: \(error)")
            }
        }
    }
    
    func saveSymbols() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(fromToMapping)
            UserDefaults.standard.set(data, forKey: "customSymbols")
        } catch {
            print("❌ Ошибка сохранения пользовательских символов: \(error)")
        }
    }
} 