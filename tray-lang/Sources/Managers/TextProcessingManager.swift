import Foundation
import AppKit
import ApplicationServices

// НОВЫЙ ENUM для статуса выделения
enum SelectionStatus {
    case selected
    case notSelected
    case unknown // Не удалось определить (например, приложение не отвечает)
}

// MARK: - Text Processing Manager
class TextProcessingManager: ObservableObject {
    private let textTransformer: TextTransformer
    private let keyboardLayoutManager: KeyboardLayoutManager
    
    init(textTransformer: TextTransformer, keyboardLayoutManager: KeyboardLayoutManager) {
        self.textTransformer = textTransformer
        self.keyboardLayoutManager = keyboardLayoutManager
    }
    
    // MARK: - Pre-check
    // ИЗМЕНЕННАЯ функция проверки
    private func checkSelectionStatus() -> SelectionStatus {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("🔍 checkSelectionStatus: Не удалось получить активное приложение.")
            return .unknown
        }
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            print("🔍 checkSelectionStatus: Не удалось получить элемент в фокусе.")
            return .unknown
        }
              
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
              let rangeValue = selectedRange else {
            print("🔍 checkSelectionStatus: Элемент не поддерживает kAXSelectedTextRangeAttribute. Статус неизвестен.")
            return .unknown // Ключевое изменение: если API не поддерживается, мы не знаем статус
        }
              
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            print("🔍 checkSelectionStatus: Не удалось конвертировать диапазон.")
            return .unknown
        }
        
        if range.length > 0 {
            print("🔍 checkSelectionStatus: Текст выделен (длина: \(range.length)).")
            return .selected
        } else {
            print("🔍 checkSelectionStatus: Текст не выделен.")
            return .notSelected
        }
    }
    
    // MARK: - Text Processing
    // ПОЛНОСТЬЮ НОВАЯ ЛОГИКА
    func processSelectedText() {
        let status = checkSelectionStatus()
        
        switch status {
        case .notSelected:
            print("🤷 Текст не выделен. Операция отменена.")
            return
            
        case .selected:
            print("🔄 Текст выделен, запускаем полную цепочку методов...")
            // Запускаем полную цепочку, так как приложение "отзывчивое"
            guard let selectedText = getSelectedText() else {
                print("❌ Не удалось получить выделенный текст, хотя выделение было обнаружено.")
                return
            }
            performTransformation(with: selectedText)
            
        case .unknown:
            print("🤔 Статус выделения неизвестен. Приложение может быть несовместимо с Accessibility API. Пробуем запасной метод...")
            // Приложение "неразговорчивое", пропускаем методы Accessibility и сразу идем к буферу обмена.
            do {
                if let selectedText = try getSelectedTextViaHotkeys() {
                    performTransformation(with: selectedText)
                } else {
                    print("❌ Запасной метод также не смог получить текст.")
                }
            } catch {
                print("❌ Ошибка при выполнении запасного метода: \(error)")
            }
        }
    }
    
    // Вспомогательная функция, чтобы не дублировать код
    private func performTransformation(with text: String) {
        let transformedText = textTransformer.transformText(text)
        print("🔄 Трансформированный текст: \(transformedText)")
        
        if replaceSelectedText(with: transformedText) {
            print("✅ Текст успешно заменен, переключаем язык")
            switchToNextLayout()
        } else {
            print("❌ Не удалось заменить текст")
        }
    }
    
    // MARK: - Text Retrieval
    private func getSelectedText() -> String? {
        print("🔍 === НАЧАЛО ПОЛУЧЕНИЯ ВЫДЕЛЕННОГО ТЕКСТА ===")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ Не удалось получить активное приложение")
            return nil
        }
        
        print("📱 Активное приложение: \(frontmostApp.localizedName ?? "Unknown") (PID: \(frontmostApp.processIdentifier))")
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Метод 1: Попытка получить выделенный текст через kAXSelectedTextAttribute
        print("🔍 Метод 1: kAXSelectedTextAttribute")
        do {
            if let text = try getSelectedTextViaAttribute(appElement) {
                print("✅ Метод 1 УСПЕШЕН: \(text)")
                return text
            }
        } catch {
            print("❌ Метод 1 ПРОВАЛЕН: \(error)")
        }
        
        // Метод 2: Попытка получить текст через kAXValueAttribute
        print("🔍 Метод 2: kAXValueAttribute")
        do {
            if let text = try getSelectedTextViaValue(appElement) {
                print("✅ Метод 2 УСПЕШЕН: \(text)")
                return text
            }
        } catch {
            print("❌ Метод 2 ПРОВАЛЕН: \(error)")
        }
        
        // Метод 3: Попытка получить текст через AppleScript и горячие клавиши
        print("🔍 Метод 3: AppleScript + Hotkeys")
        do {
            if let text = try getSelectedTextViaHotkeys() {
                print("✅ Метод 3 УСПЕШЕН: \(text)")
                return text
            }
        } catch {
            print("❌ Метод 3 ПРОВАЛЕН: \(error)")
        }
        
        print("❌ === ВСЕ МЕТОДЫ ПОЛУЧЕНИЯ ТЕКСТА ПРОВАЛЕНЫ ===")
        return nil
    }
    
    private func getSelectedTextViaAttribute(_ appElement: AXUIElement) throws -> String? {
        print("  🔍 Попытка получить фокусный элемент...")
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            print("  ❌ Не удалось получить фокусный элемент (результат: \(result))")
            throw TrayLangError.textRetrievalFailed
        }
        
        print("  ✅ Фокусный элемент получен")
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        
        print("  📋 Результат получения kAXSelectedTextAttribute: \(textResult)")
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            print("  ✅ Текст получен через kAXSelectedTextAttribute: '\(text)'")
            return text
        } else {
            print("  ❌ Текст не получен (результат: \(textResult), текст: \(selectedText != nil ? "present" : "nil"))")
        }
        
        return nil
    }
    
    private func getSelectedTextViaValue(_ appElement: AXUIElement) throws -> String? {
        print("  🔍 Попытка получить фокусный элемент для Value...")
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            print("  ❌ Не удалось получить фокусный элемент для Value")
            return nil
        }
        
        print("  ✅ Фокусный элемент получен для Value")
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &value)
        
        print("  📋 Результат получения kAXValueAttribute: \(valueResult)")
        
        if valueResult == .success, let text = value as? String, !text.isEmpty {
            print("  ✅ Текст получен через kAXValueAttribute: '\(text)'")
            return text
        } else {
            print("  ❌ Текст не получен через Value (результат: \(valueResult), значение: \(value != nil ? "present" : "nil"))")
        }
        
        return nil
    }
    
    private func getSelectedTextViaHotkeys() throws -> String? {
        print("  🔍 Выполняем копирование через CGEvent и NSPasteboard...")
        
        return getSelectedTextViaPasteboard()
    }
    
    // MARK: - Reliable Pasteboard Methods
    private func getSelectedTextViaPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        
        // 1. Сохраняем текущее состояние буфера обмена
        let originalChangeCount = pasteboard.changeCount
        var originalContent: String? = nil
        if let originalString = pasteboard.string(forType: .string) {
            originalContent = originalString
        }
        
        print("  📋 Сохранен оригинальный буфер обмена (changeCount: \(originalChangeCount))")
        
        // 2. Симулируем Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        guard let cmdCDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            print("  ❌ Не удалось создать события клавиатуры")
            return nil
        }
        
        cmdCDown.flags = .maskCommand
        cmdCUp.flags = .maskCommand
        
        cmdCDown.post(tap: .cghidEventTap)
        cmdCUp.post(tap: .cghidEventTap)
        
        print("  ⌨️ Отправлено событие Cmd+C")
        
        // 3. Ждем изменения буфера обмена (до 0.5 секунды)
        let startTime = Date()
        let timeout: TimeInterval = 0.5
        var newChangeCount = pasteboard.changeCount
        
        while newChangeCount == originalChangeCount && Date().timeIntervalSince(startTime) < timeout {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            newChangeCount = pasteboard.changeCount
        }
        
        // 4. Проверяем, изменился ли буфер обмена
        guard newChangeCount != originalChangeCount else {
            print("  ❌ Буфер обмена не изменился в течение таймаута")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return nil
        }
        
        // 5. Читаем новый текст
        guard let newText = pasteboard.string(forType: .string), !newText.isEmpty else {
            print("  ❌ Не удалось прочитать текст из буфера обмена")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return nil
        }
        
        print("  ✅ Текст получен через NSPasteboard: '\(newText)' (changeCount: \(newChangeCount))")
        
        // 6. Восстанавливаем оригинальный буфер обмена
        restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
        
        return newText
    }
    
    private func restorePasteboard(originalContent: String?, originalChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        
        // Восстанавливаем только если содержимое действительно изменилось
        if let original = originalContent {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
            print("  🔄 Буфер обмена восстановлен")
        } else {
            // Если оригинального содержимого не было, просто очищаем
            if pasteboard.changeCount != originalChangeCount {
                pasteboard.clearContents()
                print("  🔄 Буфер обмена очищен")
            }
        }
    }
    
    // MARK: - Text Replacement
    private func replaceSelectedText(with newText: String) -> Bool {
        print("📝 === НАЧАЛО ЗАМЕНЫ ТЕКСТА: '\(newText)' ===")
        
        // Метод 1: Попытка заменить через Accessibility API (резервный)
        print("🔍 Метод 1: Accessibility API")
        if replaceTextViaAccessibility(newText) {
            print("✅ Метод 1 ЗАМЕНЫ УСПЕШЕН")
            return true
        }
        
        // Метод 2: Попытка заменить через улучшенную логику (наиболее надежный)
        print("🔍 Метод 2: Улучшенная логика с AppleScript")
        if replaceTextWithImprovedLogic(newText) {
            print("✅ Метод 2 ЗАМЕНЫ УСПЕШЕН")
            return true
        }
        
        print("❌ === ВСЕ МЕТОДЫ ЗАМЕНЫ ТЕКСТА ПРОВАЛЕНЫ ===")
        return false
    }
    
    private func switchToNextLayout() {
        print("🔄 Переключаем на следующую раскладку клавиатуры...")
        keyboardLayoutManager.switchToNextLayout()
    }
    
    private func replaceTextWithImprovedLogic(_ newText: String) -> Bool {
        print("  🔍 Выполняем замену текста через CGEvent и NSPasteboard...")
        
        return replaceTextViaPasteboard(newText)
    }
    
    private func replaceTextViaPasteboard(_ newText: String) -> Bool {
        let pasteboard = NSPasteboard.general
        
        // 1. Сохраняем текущее состояние буфера обмена
        let originalChangeCount = pasteboard.changeCount
        var originalContent: String? = nil
        if let originalString = pasteboard.string(forType: .string) {
            originalContent = originalString
        }
        
        print("  📋 Сохранен оригинальный буфер обмена (changeCount: \(originalChangeCount))")
        
        // 2. Помещаем новый текст в буфер обмена
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        
        // 3. Ждем, пока буфер обмена обновится (проверяем changeCount)
        let startTime = Date()
        let timeout: TimeInterval = 0.5
        var newChangeCount = pasteboard.changeCount
        
        while newChangeCount == originalChangeCount && Date().timeIntervalSince(startTime) < timeout {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            newChangeCount = pasteboard.changeCount
        }
        
        // 4. Проверяем, что текст действительно установлен
        guard let pasteboardText = pasteboard.string(forType: .string),
              pasteboardText == newText else {
            print("  ❌ Не удалось установить текст в буфер обмена")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return false
        }
        
        print("  📋 Текст установлен в буфер обмена (changeCount: \(newChangeCount))")
        
        // 5. Симулируем Cmd+V для вставки
        let source = CGEventSource(stateID: .hidSystemState)
        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            print("  ❌ Не удалось создать события клавиатуры")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return false
        }
        
        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand
        
        cmdVDown.post(tap: .cghidEventTap)
        cmdVUp.post(tap: .cghidEventTap)
        
        print("  ⌨️ Отправлено событие Cmd+V")
        
        // 6. Небольшая задержка после вставки
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
        // 7. Восстанавливаем оригинальный буфер обмена
        restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
        
        print("  ✅ Замена текста выполнена успешно")
        return true
    }
    
    private func replaceTextViaAccessibility(_ newText: String) -> Bool {
        print("  🔍 Попытка замены через Accessibility API...")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("  ❌ Не удалось получить активное приложение")
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Получаем фокусный элемент
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            print("  ❌ Не удалось получить фокусный элемент (результат: \(result))")
            return false
        }
        
        print("  ✅ Фокусный элемент получен")
        
        // Пытаемся получить текущий текст для проверки
        var currentText: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &currentText)
        
        print("  📋 Результат получения текущего текста: \(getResult)")
        
        if getResult == .success, let text = currentText as? String {
            print("  📋 Текущий текст элемента: '\(text)'")
            
            // Пытаемся получить выделенный текст
            var selectedText: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
            
            print("  📋 Результат получения выделенного текста: \(selectedResult)")
            
            if selectedResult == .success, let selected = selectedText as? String, !selected.isEmpty {
                print("  📋 Выделенный текст: '\(selected)'")
                
                // Заменяем выделенный текст на новый
                let setResult = AXUIElementSetAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, newText as CFString)
                
                print("  📋 Результат установки нового текста: \(setResult)")
                
                // Проверяем, что замена действительно произошла
                if setResult == .success {
                    // Проверяем результат замены
                    var newCurrentText: CFTypeRef?
                    let verifyResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &newCurrentText)
                    
                    if verifyResult == .success, let newText = newCurrentText as? String {
                        print("  📋 Текст после замены: '\(newText)'")
                        
                        // Проверяем, что текст действительно изменился
                        if newText != text {
                            print("  ✅ Выделенный текст успешно заменен через Accessibility API")
                            return true
                        } else {
                            print("  ❌ Текст не изменился после попытки замены")
                            return false
                        }
                    } else {
                        print("  ❌ Не удалось проверить результат замены (результат: \(verifyResult))")
                        return false
                    }
                } else {
                    print("  ❌ Не удалось установить новый текст (результат: \(setResult))")
                    return false
                }
            } else {
                print("  ❌ Выделенный текст не найден или пуст")
                return false
            }
        } else {
            print("  ❌ Не удалось получить текущий текст (результат: \(getResult))")
            return false
        }
    }
} 
