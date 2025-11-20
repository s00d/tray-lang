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
    // Функция для безопасного получения атрибута с таймаутом
    private func getAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        
        // Устанавливаем короткий таймаут (0.1 сек) для предотвращения зависаний
        AXUIElementSetMessagingTimeout(element, 0.1)
        
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        
        if error == .success {
            return result
        }
        return nil
    }
    
    // ИЗМЕНЕННАЯ функция проверки с таймаутами
    private func checkSelectionStatus() -> SelectionStatus {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            debugLog("🔍 checkSelectionStatus: Не удалось получить активное приложение.")
            return .unknown
        }
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        guard let focusedElementRef = getAXAttribute(appElement, kAXFocusedUIElementAttribute as String) else {
            debugLog("🔍 checkSelectionStatus: Не удалось получить элемент в фокусе.")
            return .unknown
        }
        let focusedElement = focusedElementRef as! AXUIElement
              
        guard let selectedRange = getAXAttribute(focusedElement, kAXSelectedTextRangeAttribute as String) else {
            debugLog("🔍 checkSelectionStatus: Элемент не поддерживает kAXSelectedTextRangeAttribute. Статус неизвестен.")
            return .unknown // Ключевое изменение: если API не поддерживается, мы не знаем статус
        }
        let rangeValue = selectedRange as! AXValue
              
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            debugLog("🔍 checkSelectionStatus: Не удалось конвертировать диапазон.")
            return .unknown
        }
        
        if range.length > 0 {
            debugLog("🔍 checkSelectionStatus: Текст выделен (длина: \(range.length)).")
            return .selected
        } else {
            debugLog("🔍 checkSelectionStatus: Текст не выделен.")
            return .notSelected
        }
    }
    
    // MARK: - Text Processing
    // ПОЛНОСТЬЮ НОВАЯ ЛОГИКА
    func processSelectedText() {
        let status = checkSelectionStatus()
        
        switch status {
        case .notSelected:
            debugLog("🤷 Текст не выделен. Операция отменена.")
            return
            
        case .selected:
            debugLog("🔄 Текст выделен, запускаем полную цепочку методов...")
            // Запускаем полную цепочку, так как приложение "отзывчивое"
            guard let selectedText = getSelectedText() else {
                debugLog("❌ Не удалось получить выделенный текст, хотя выделение было обнаружено.")
                return
            }
            performTransformation(with: selectedText)
            
        case .unknown:
            debugLog("🤔 Статус выделения неизвестен. Приложение может быть несовместимо с Accessibility API. Пробуем запасной метод...")
            // Приложение "неразговорчивое", пропускаем методы Accessibility и сразу идем к буферу обмена.
            do {
                if let selectedText = try getSelectedTextViaHotkeys() {
                    performTransformation(with: selectedText)
                } else {
                    debugLog("❌ Запасной метод также не смог получить текст.")
                }
            } catch {
                debugLog("❌ Ошибка при выполнении запасного метода: \(error)")
            }
        }
    }
    
    // Вспомогательная функция, чтобы не дублировать код
    private func performTransformation(with text: String) {
        let transformedText = textTransformer.transformText(text)
        debugLog("🔄 Трансформированный текст: \(transformedText)")
        
        if replaceSelectedText(with: transformedText) {
            debugLog("✅ Текст успешно заменен, переключаем язык")
            switchToNextLayout()
        } else {
            debugLog("❌ Не удалось заменить текст")
        }
    }
    
    // MARK: - Text Retrieval
    private func getSelectedText() -> String? {
        debugLog("🔍 === НАЧАЛО ПОЛУЧЕНИЯ ВЫДЕЛЕННОГО ТЕКСТА ===")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            debugLog("❌ Не удалось получить активное приложение")
            return nil
        }
        
        debugLog("📱 Активное приложение: \(frontmostApp.localizedName ?? "Unknown") (PID: \(frontmostApp.processIdentifier))")
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Метод 1: Попытка получить выделенный текст через kAXSelectedTextAttribute
        debugLog("🔍 Метод 1: kAXSelectedTextAttribute")
        do {
            if let text = try getSelectedTextViaAttribute(appElement) {
                debugLog("✅ Метод 1 УСПЕШЕН: \(text)")
                return text
            }
        } catch {
            debugLog("❌ Метод 1 ПРОВАЛЕН: \(error)")
        }
        
        // Метод 2: Попытка получить текст через kAXValueAttribute
        debugLog("🔍 Метод 2: kAXValueAttribute")
        do {
            if let text = try getSelectedTextViaValue(appElement) {
                debugLog("✅ Метод 2 УСПЕШЕН: \(text)")
                return text
            }
        } catch {
            debugLog("❌ Метод 2 ПРОВАЛЕН: \(error)")
        }
        
        // Метод 3: Попытка получить текст через AppleScript и горячие клавиши
        debugLog("🔍 Метод 3: AppleScript + Hotkeys")
        do {
            if let text = try getSelectedTextViaHotkeys() {
                debugLog("✅ Метод 3 УСПЕШЕН: \(text)")
                return text
            }
        } catch {
            debugLog("❌ Метод 3 ПРОВАЛЕН: \(error)")
        }
        
        debugLog("❌ === ВСЕ МЕТОДЫ ПОЛУЧЕНИЯ ТЕКСТА ПРОВАЛЕНЫ ===")
        return nil
    }
    
    private func getSelectedTextViaAttribute(_ appElement: AXUIElement) throws -> String? {
        debugLog("  🔍 Попытка получить фокусный элемент...")
        
        guard let focusedElementRef = getAXAttribute(appElement, kAXFocusedUIElementAttribute as String) else {
            debugLog("  ❌ Не удалось получить фокусный элемент")
            throw TrayLangError.textRetrievalFailed
        }
        let focusedElement = focusedElementRef as! AXUIElement
        
        debugLog("  ✅ Фокусный элемент получен")
        
        guard let selectedText = getAXAttribute(focusedElement, kAXSelectedTextAttribute as String) as? String, !selectedText.isEmpty else {
            debugLog("  ❌ Текст не получен")
            return nil
        }
        
        debugLog("  ✅ Текст получен через kAXSelectedTextAttribute: '\(selectedText)'")
        return selectedText
    }
    
    private func getSelectedTextViaValue(_ appElement: AXUIElement) throws -> String? {
        debugLog("  🔍 Попытка получить фокусный элемент для Value...")
        
        guard let focusedElementRef = getAXAttribute(appElement, kAXFocusedUIElementAttribute as String) else {
            debugLog("  ❌ Не удалось получить фокусный элемент для Value")
            return nil
        }
        let focusedElement = focusedElementRef as! AXUIElement
        
        debugLog("  ✅ Фокусный элемент получен для Value")
        
        guard let text = getAXAttribute(focusedElement, kAXValueAttribute as String) as? String, !text.isEmpty else {
            debugLog("  ❌ Текст не получен через Value")
            return nil
        }
        
        debugLog("  ✅ Текст получен через kAXValueAttribute: '\(text)'")
        return text
    }
    
    private func getSelectedTextViaHotkeys() throws -> String? {
        debugLog("  🔍 Выполняем копирование через CGEvent и NSPasteboard...")
        
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
        
        debugLog("  📋 Сохранен оригинальный буфер обмена (changeCount: \(originalChangeCount))")
        
        // 2. Симулируем Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        guard let cmdCDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            debugLog("  ❌ Не удалось создать события клавиатуры")
            return nil
        }
        
        cmdCDown.flags = .maskCommand
        cmdCUp.flags = .maskCommand
        
        cmdCDown.post(tap: .cghidEventTap)
        cmdCUp.post(tap: .cghidEventTap)
        
        debugLog("  ⌨️ Отправлено событие Cmd+C")
        
        // 3. Ждем изменения буфера обмена с оптимизированным ожиданием
        guard PasteboardHelper.waitForPasteboardChange(originalCount: originalChangeCount, timeout: 0.3) else {
            debugLog("  ❌ Буфер обмена не изменился в течение таймаута")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return nil
        }
        
        // 5. Читаем новый текст
        guard let newText = pasteboard.string(forType: .string), !newText.isEmpty else {
            debugLog("  ❌ Не удалось прочитать текст из буфера обмена")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return nil
        }
        
        debugLog("  ✅ Текст получен через NSPasteboard: '\(newText)'")
        
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
            debugLog("  🔄 Буфер обмена восстановлен")
        } else {
            // Если оригинального содержимого не было, просто очищаем
            if pasteboard.changeCount != originalChangeCount {
                pasteboard.clearContents()
                debugLog("  🔄 Буфер обмена очищен")
            }
        }
    }
    
    // MARK: - Text Replacement
    private func replaceSelectedText(with newText: String) -> Bool {
        debugLog("📝 === НАЧАЛО ЗАМЕНЫ ТЕКСТА: '\(newText)' ===")
        
        // Метод 1: Попытка заменить через Accessibility API (резервный)
        debugLog("🔍 Метод 1: Accessibility API")
        if replaceTextViaAccessibility(newText) {
            debugLog("✅ Метод 1 ЗАМЕНЫ УСПЕШЕН")
            return true
        }
        
        // Метод 2: Попытка заменить через улучшенную логику (наиболее надежный)
        debugLog("🔍 Метод 2: Улучшенная логика с AppleScript")
        if replaceTextWithImprovedLogic(newText) {
            debugLog("✅ Метод 2 ЗАМЕНЫ УСПЕШЕН")
            return true
        }
        
        debugLog("❌ === ВСЕ МЕТОДЫ ЗАМЕНЫ ТЕКСТА ПРОВАЛЕНЫ ===")
        return false
    }
    
    private func switchToNextLayout() {
        debugLog("🔄 Переключаем на следующую раскладку клавиатуры...")
        keyboardLayoutManager.switchToNextLayout()
    }
    
    private func replaceTextWithImprovedLogic(_ newText: String) -> Bool {
        debugLog("  🔍 Выполняем замену текста через CGEvent и NSPasteboard...")
        
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
        
        debugLog("  📋 Сохранен оригинальный буфер обмена (changeCount: \(originalChangeCount))")
        
        // 2. Помещаем новый текст в буфер обмена
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        
        // 3. Ждем, пока буфер обмена обновится с оптимизированным ожиданием
        guard PasteboardHelper.waitForPasteboardChange(originalCount: originalChangeCount, timeout: 0.3) else {
            debugLog("  ❌ Буфер обмена не обновился в течение таймаута")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return false
        }
        
        // 4. Проверяем, что текст действительно установлен
        guard let pasteboardText = pasteboard.string(forType: .string),
              pasteboardText == newText else {
            debugLog("  ❌ Не удалось установить текст в буфер обмена")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return false
        }
        
        debugLog("  📋 Текст установлен в буфер обмена")
        
        // 5. Симулируем Cmd+V для вставки
        let source = CGEventSource(stateID: .hidSystemState)
        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            debugLog("  ❌ Не удалось создать события клавиатуры")
            restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
            return false
        }
        
        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand
        
        cmdVDown.post(tap: .cghidEventTap)
        cmdVUp.post(tap: .cghidEventTap)
        
        debugLog("  ⌨️ Отправлено событие Cmd+V")
        
        // 6. Небольшая задержка после вставки
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
        // 7. Восстанавливаем оригинальный буфер обмена
        restorePasteboard(originalContent: originalContent, originalChangeCount: originalChangeCount)
        
        debugLog("  ✅ Замена текста выполнена успешно")
        return true
    }
    
    private func replaceTextViaAccessibility(_ newText: String) -> Bool {
        debugLog("  🔍 Попытка замены через Accessibility API...")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            debugLog("  ❌ Не удалось получить активное приложение")
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Получаем фокусный элемент с таймаутом
        guard let focusedElementRef = getAXAttribute(appElement, kAXFocusedUIElementAttribute as String) else {
            debugLog("  ❌ Не удалось получить фокусный элемент")
            return false
        }
        let focusedElement = focusedElementRef as! AXUIElement
        
        debugLog("  ✅ Фокусный элемент получен")
        
        // Пытаемся получить текущий текст для проверки
        guard let currentText = getAXAttribute(focusedElement, kAXValueAttribute as String) as? String else {
            debugLog("  ❌ Не удалось получить текущий текст")
            return false
        }
        
        debugLog("  📋 Текущий текст элемента: '\(currentText)'")
        
        // Пытаемся получить выделенный текст
        guard let selectedText = getAXAttribute(focusedElement, kAXSelectedTextAttribute as String) as? String, !selectedText.isEmpty else {
            debugLog("  ❌ Выделенный текст не найден или пуст")
            return false
        }
        
        debugLog("  📋 Выделенный текст: '\(selectedText)'")
        
        // Заменяем выделенный текст на новый
        AXUIElementSetMessagingTimeout(focusedElement, 0.1)
        let setResult = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, newText as CFString)
        
        debugLog("  📋 Результат установки нового текста: \(setResult)")
        
        // Проверяем, что замена действительно произошла
        if setResult == .success {
            // Проверяем результат замены
            guard let newCurrentText = getAXAttribute(focusedElement, kAXValueAttribute as String) as? String else {
                debugLog("  ❌ Не удалось проверить результат замены")
                return false
            }
            
            debugLog("  📋 Текст после замены: '\(newCurrentText)'")
            
            // Проверяем, что текст действительно изменился
            if newCurrentText != currentText {
                debugLog("  ✅ Выделенный текст успешно заменен через Accessibility API")
                return true
            } else {
                debugLog("  ❌ Текст не изменился после попытки замены")
                return false
            }
        } else {
            debugLog("  ❌ Не удалось установить новый текст (результат: \(setResult))")
            return false
        }
    }
} 
