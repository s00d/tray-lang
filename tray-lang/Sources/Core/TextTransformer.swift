import Foundation

// MARK: - Text Transformer
class TextTransformer: ObservableObject {
    @Published var profiles: [ConversionProfile] = []
    @Published var activeProfileID: UUID? {
        didSet {
            // Сохраняем ID активного профиля при его изменении
            if let id = activeProfileID {
                UserDefaults.standard.set(id.uuidString, forKey: "activeProfileID")
            }
            updateActiveMapping()
        }
    }
    
    // Обратная совместимость: для существующего кода
    @Published var fromToMapping: [String: String] = KeyboardMapping.defaultMapping
    private var toFromMapping: [String: String] = [:]
    
    init() {
        loadProfiles()
        updateActiveMapping()
    }
    
    // Получаем текущий активный профиль
    var activeProfile: ConversionProfile? {
        profiles.first { $0.id == activeProfileID }
    }
    
    // MARK: - Mapping Setup
    private func setupToFromMapping() {
        toFromMapping = KeyboardMapping.createInverseMapping(from: fromToMapping)
    }
    
    private func updateActiveMapping() {
        if let mapping = activeProfile?.mapping {
            self.fromToMapping = mapping
            setupToFromMapping()
        } else {
            // Fallback на default mapping
            self.fromToMapping = KeyboardMapping.defaultMapping
            setupToFromMapping()
        }
    }
    
    // MARK: - Text Transformation
    func transformText(_ text: String) -> String {
        guard !toFromMapping.isEmpty, activeProfile != nil else { return text }
        
        var result = ""
        for char in text {
            let charString = String(char)
            
            // Сначала пробуем конвертировать через активный профиль
            if let mapped = activeProfile?.mapping[charString] {
                result += mapped
            } else if let mapped = toFromMapping[charString] {
                // Если не нашли в активном профиле, пробуем обратный маппинг
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
    
    // MARK: - Mapping Management (обратная совместимость)
    func updateMapping(_ newMapping: [String: String]) {
        // Обновляем активный профиль, если он редактируемый
        if var active = activeProfile, active.isEditable {
            active.mapping = newMapping
            updateProfile(active)
        } else {
            // Если профиль не редактируемый, создаем новый на его основе
            if let active = activeProfile {
                addProfile(name: "\(active.name) (Custom)", basedOn: active)
                if let newProfile = profiles.last {
                    var updated = newProfile
                    updated.mapping = newMapping
                    updateProfile(updated)
                    activeProfileID = newProfile.id
                }
            }
        }
    }
    
    // MARK: - Profile Management
    
    func loadProfiles() {
        // Проверяем, есть ли уже сохраненные профили
        if let data = UserDefaults.standard.data(forKey: "userProfiles") {
            if let decoded = try? JSONDecoder().decode([ConversionProfile].self, from: data) {
                profiles = decoded
            } else {
                // Если декодирование не удалось, загружаем стандартные
                profiles = ConversionProfile.defaultProfiles()
            }
        } else {
            // Если сохраненных профилей нет, загружаем стандартные
            profiles = ConversionProfile.defaultProfiles()
            
            // МИГРАЦИЯ: Проверяем старые данные и создаем профиль из них
            migrateOldData()
        }
        
        // Если после загрузки профилей нет, создаем стандартные
        if profiles.isEmpty {
            profiles = ConversionProfile.defaultProfiles()
        }
        
        // --- НОВАЯ ЛОГИКА ВЫБОРА ПРОФИЛЯ ПО УМОЛЧАНИЮ ---
        var defaultProfileSet = false
        
        // 1. Пытаемся загрузить сохраненный ID активного профиля
        if let idString = UserDefaults.standard.string(forKey: "activeProfileID"),
           let id = UUID(uuidString: idString),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
            defaultProfileSet = true
        }
        
        // 2. Если не получилось (нет сохраненного или он некорректен), ищем русский профиль
        if !defaultProfileSet {
            if let russianProfile = profiles.first(where: { $0.name == "Russian (QWERTY ↔ ЙЦУКЕН)" }) {
                activeProfileID = russianProfile.id
                defaultProfileSet = true
                print("✅ Активным профилем по умолчанию установлен 'Russian (QWERTY ↔ ЙЦУКЕН)'")
            }
        }
        
        // 3. Если и его нет (маловероятно), просто берем первый попавшийся
        if !defaultProfileSet {
            activeProfileID = profiles.first?.id
        }
        
        // Убедимся, что при загрузке маппинг обновляется
        updateActiveMapping()
    }
    
    // МИГРАЦИЯ: Преобразуем старые данные в профиль
    private func migrateOldData() {
        if let savedMapping = UserDefaults.standard.object(forKey: "customSymbols") as? Data {
            do {
                let decoder = JSONDecoder()
                let customMapping = try decoder.decode([String: String].self, from: savedMapping)
                
                // Создаем профиль из старых данных
                let migratedProfile = ConversionProfile(
                    name: "Migrated Custom Profile",
                    isEditable: true,
                    mapping: customMapping
                )
                profiles.append(migratedProfile)
                activeProfileID = migratedProfile.id
                
                // Удаляем старые данные после миграции
                UserDefaults.standard.removeObject(forKey: "customSymbols")
                print("✅ Migrated old custom symbols to profile: \(migratedProfile.name)")
            } catch {
                print("❌ Error migrating old symbols: \(error)")
            }
        }
    }
    
    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "userProfiles")
        }
    }
    
    func addProfile(name: String, basedOn template: ConversionProfile) {
        var newProfile = template
        newProfile.id = UUID()
        newProfile.name = name
        newProfile.isEditable = true
        profiles.append(newProfile)
        saveProfiles()
    }
    
    func deleteProfile(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        saveProfiles()
        
        // Если удалили активный профиль, делаем активным первый
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles.first?.id
        }
    }
    
    func updateProfile(_ profile: ConversionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
            
            // Если обновили активный профиль, пересчитываем маппинг
            if profile.id == activeProfileID {
                updateActiveMapping()
            }
        }
    }
    
    func createNewProfile() {
        // Создаем имя по умолчанию, проверяя, что оно уникально
        var newName = "My Custom Profile"
        var counter = 1
        while profiles.contains(where: { $0.name == newName }) {
            counter += 1
            newName = "My Custom Profile \(counter)"
        }
        
        let newProfile = ConversionProfile(name: newName, isEditable: true, mapping: [:])
        profiles.append(newProfile)
        // Опционально: сразу делаем его активным
        activeProfileID = newProfile.id
        saveProfiles()
    }
    
    func duplicateProfile(_ profile: ConversionProfile) {
        var newName = "\(profile.name) (copy)"
        var counter = 1
        while profiles.contains(where: { $0.name == newName }) {
            counter += 1
            newName = "\(profile.name) (copy \(counter))"
        }
        
        var duplicatedProfile = profile
        duplicatedProfile.id = UUID()
        duplicatedProfile.name = newName
        duplicatedProfile.isEditable = true // Дубликат всегда можно редактировать
        
        profiles.append(duplicatedProfile)
        // Опционально: сразу делаем активным дубликат
        activeProfileID = duplicatedProfile.id
        saveProfiles()
    }
    
    // Обратная совместимость: для старого кода
    func loadSymbols() {
        // Теперь просто загружаем профили
        loadProfiles()
    }
    
    func saveSymbols() {
        // Сохраняем профили
        saveProfiles()
    }
} 