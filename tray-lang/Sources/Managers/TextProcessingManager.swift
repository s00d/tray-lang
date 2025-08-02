import Foundation
import AppKit
import ApplicationServices

// MARK: - Text Processing Manager
class TextProcessingManager: ObservableObject {
    private let textTransformer: TextTransformer
    
    init(textTransformer: TextTransformer) {
        self.textTransformer = textTransformer
    }
    
    // MARK: - Text Processing
    func processSelectedText() {
        print("🔄 Выполняем переключение раскладки...")
        
        guard let selectedText = getSelectedText() else {
            print("❌ Не удалось получить выделенный текст")
            return
        }
        
        let transformedText = textTransformer.transformText(selectedText)
        print("🔄 Трансформированный текст: \(transformedText)")
        
        replaceSelectedText(with: transformedText)
    }
    
    // MARK: - Text Retrieval
    private func getSelectedText() -> String? {
        print("🔍 Получаем выделенный текст через Accessibility API...")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ Не удалось получить активное приложение")
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Метод 1: Попытка получить выделенный текст через kAXSelectedTextAttribute
        do {
            if let text = try getSelectedTextViaAttribute(appElement) {
                return text
            }
        } catch {
            print("⚠️ Ошибка при получении текста через Attribute: \(error)")
        }
        
        // Метод 2: Попытка получить текст через kAXValueAttribute
        do {
            if let text = try getSelectedTextViaValue(appElement) {
                return text
            }
        } catch {
            print("⚠️ Ошибка при получении текста через Value: \(error)")
        }
        
        // Метод 3: Попытка получить текст через AppleScript и горячие клавиши
        do {
            if let text = try getSelectedTextViaHotkeys() {
                return text
            }
        } catch {
            print("⚠️ Ошибка при получении текста через Hotkeys: \(error)")
        }
        
        print("❌ Не удалось получить выделенный текст ни одним из методов")
        return nil
    }
    
    private func getSelectedTextViaAttribute(_ appElement: AXUIElement) throws -> String? {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            throw TrayLangError.textRetrievalFailed
        }
        
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            print("📋 Получен текст через kAXSelectedTextAttribute: \(text)")
            return text
        }
        
        return nil
    }
    
    private func getSelectedTextViaValue(_ appElement: AXUIElement) throws -> String? {
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            return nil
        }
        
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &value)
        
        if valueResult == .success, let text = value as? String, !text.isEmpty {
            print("📋 Получен текст через kAXValueAttribute: \(text)")
            return text
        }
        
        return nil
    }
    
    private func getSelectedTextViaHotkeys() throws -> String? {
        print("📋 Пытаемся получить текст через AppleScript...")
        
        // Используем AppleScript для получения выделенного текста с сохранением позиции
        let script = """
        tell application "System Events"
            set originalClipboard to the clipboard
            try
                -- Копируем выделенный текст (Cmd+C)
                key code 8 using {command down}
                delay 0.1
                set selectedText to the clipboard
                -- Восстанавливаем оригинальный буфер обмена
                set the clipboard to originalClipboard
                return selectedText
            on error
                -- Восстанавливаем оригинальный буфер обмена в случае ошибки
                set the clipboard to originalClipboard
                return ""
            end try
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if !output.isEmpty && output != "error" {
                    print("📋 Получен текст через AppleScript: \(output)")
                    return output
                }
            }
        } catch {
            print("❌ Ошибка при выполнении AppleScript: \(error)")
            throw error
        }
        
        return nil
    }
    
    // MARK: - Text Replacement
    private func replaceSelectedText(with newText: String) {
        print("📝 Заменяем выделенный текст на: \(newText)")
        
        // Метод 1: Попытка заменить через улучшенную логику (наиболее надежный)
        if replaceTextWithImprovedLogic(newText) {
            return
        }
        
        // Метод 2: Попытка заменить через Accessibility API (резервный)
        if replaceTextViaAccessibility(newText) {
            return
        }
        
        print("❌ Не удалось заменить текст ни одним из методов")
    }
    
    private func replaceTextWithImprovedLogic(_ newText: String) -> Bool {
        print("🔍 Пытаемся заменить текст с улучшенной логикой...")
        
        // Используем AppleScript для замены текста с более продвинутой обработкой выделения
        let script = """
        tell application "System Events"
            set originalClipboard to the clipboard
            try
                -- Проверяем, есть ли выделенный текст
                key code 8 using {command down}
                delay 0.1
                set selectedText to the clipboard
                
                if selectedText is not equal to originalClipboard then
                    -- Есть выделенный текст, заменяем его
                    set the clipboard to "\(newText)"
                    delay 0.1
                    key code 9 using {command down}
                    delay 0.1
                    set the clipboard to originalClipboard
                    return "success"
                else
                    -- Нет выделенного текста, просто вставляем
                    set the clipboard to "\(newText)"
                    delay 0.1
                    key code 9 using {command down}
                    delay 0.1
                    set the clipboard to originalClipboard
                    return "success"
                end if
            on error
                -- Восстанавливаем оригинальный буфер обмена в случае ошибки
                set the clipboard to originalClipboard
                return "error"
            end try
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output == "success" {
                    print("✅ Текст успешно заменен с улучшенной логикой")
                    return true
                }
            }
        } catch {
            print("❌ Ошибка при выполнении AppleScript: \(error)")
        }
        
        return false
    }
    
    private func replaceTextViaAccessibility(_ newText: String) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ Не удалось получить активное приложение")
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Получаем фокусный элемент
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let focusedElement = focusedElement else {
            print("❌ Не удалось получить фокусный элемент")
            return false
        }
        
        // Пытаемся получить текущий текст для проверки
        var currentText: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXValueAttribute as CFString, &currentText)
        
        if getResult == .success, let text = currentText as? String {
            print("📋 Текущий текст элемента: \(text)")
            
            // Пытаемся получить выделенный текст
            var selectedText: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
            
            if selectedResult == .success, let selected = selectedText as? String, !selected.isEmpty {
                print("📋 Выделенный текст: \(selected)")
                
                // Заменяем выделенный текст на новый
                let setResult = AXUIElementSetAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, newText as CFString)
                
                if setResult == .success {
                    print("✅ Выделенный текст успешно заменен через Accessibility API")
                    return true
                }
            }
        }
        
        print("❌ Не удалось заменить текст через Accessibility API")
        return false
    }
} 