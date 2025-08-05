import Foundation
import AppKit
import ApplicationServices

// MARK: - Text Processing Manager
class TextProcessingManager: ObservableObject {
    private let textTransformer: TextTransformer
    private let keyboardLayoutManager: KeyboardLayoutManager
    
    init(textTransformer: TextTransformer, keyboardLayoutManager: KeyboardLayoutManager) {
        self.textTransformer = textTransformer
        self.keyboardLayoutManager = keyboardLayoutManager
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
        print("  🔍 Выполняем AppleScript для получения текста...")
        
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
                    print("  ✅ Текст получен через AppleScript: '\(output)'")
                    return output
                } else {
                    print("  ❌ AppleScript вернул пустой результат или ошибку: '\(output)'")
                }
            }
        } catch {
            print("  ❌ Ошибка при выполнении AppleScript: \(error)")
            throw error
        }
        
        return nil
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
        print("  🔍 Выполняем AppleScript для замены текста...")
        
        // Используем AppleScript для замены текста с оптимизированной логикой
        let script = """
        tell application "System Events"
            set originalClipboard to the clipboard
            try
                -- Копируем выделенный текст
                key code 8 using {command down}
                delay 0.1
                set selectedText to the clipboard
                
                -- Помещаем новый текст в буфер обмена
                set the clipboard to "\(newText)"
                delay 0.1
                
                -- Вставляем новый текст
                key code 9 using {command down}
                delay 0.1
                
                -- Восстанавливаем оригинальный буфер обмена
                set the clipboard to originalClipboard
                return "success"
            on error errMsg
                -- Восстанавливаем оригинальный буфер обмена в случае ошибки
                set the clipboard to originalClipboard
                return "error: " & errMsg
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
                if output.hasPrefix("success") {
                    print("  ✅ AppleScript успешно выполнен")
                    return true
                } else {
                    print("  ❌ AppleScript вернул ошибку: '\(output)'")
                }
            }
        } catch {
            print("  ❌ Ошибка при выполнении AppleScript: \(error)")
        }
        
        return false
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
