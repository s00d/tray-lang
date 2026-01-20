import Foundation
import AppKit
import ApplicationServices

class TextProcessingManager: ObservableObject {
    private let textTransformer: TextTransformer
    private let keyboardLayoutManager: KeyboardLayoutManager
    
    // Список терминалов
    private let terminalBundleIDs = [
        "com.apple.Terminal",           // Apple Terminal
        "com.googlecode.iterm2",        // iTerm2
        "co.zeit.hyper",                // Hyper
        "org.alacritty",                // Alacritty
        "io.alacritty",                 // Alacritty (alt)
        "net.kovidgoyal.kitty",         // Kitty
        "dev.warp.Warp-Stable",         // Warp
        "com.github.wez.wezterm",       // WezTerm
        "com.microsoft.VSCode",         // VS Code (терминал часто имеет тот же bundleID)
        "com.googlecode.iterm2-nightly" // iTerm2 Nightly
    ]
    
    init(textTransformer: TextTransformer, keyboardLayoutManager: KeyboardLayoutManager) {
        self.textTransformer = textTransformer
        self.keyboardLayoutManager = keyboardLayoutManager
    }
    
    // MARK: - Main Logic
    func processSelectedText() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmostApp.bundleIdentifier else { return }
        
        debugLog("🚀 APP: \(frontmostApp.localizedName ?? "?") | Bundle ID: \(bundleID)")
        
        // 1. ЛОГИКА ДЛЯ ТЕРМИНАЛОВ
        if terminalBundleIDs.contains(bundleID) {
            handleTerminalProcessing(app: frontmostApp)
            return
        }
        
        // 2. СТАНДАРТНАЯ ЛОГИКА
        attemptAccessibilityStrategy()
    }
    
    // MARK: - Terminal Logic
    
    private func handleTerminalProcessing(app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Получаем текст через AX API
        guard let focused = getAXAttribute(appElement, kAXFocusedUIElementAttribute as String) as! AXUIElement?,
              let fullText = getAXAttribute(focused, kAXValueAttribute as String) as? String,
              !fullText.isEmpty else {
            debugLog("❌ Терминал: Не удалось прочитать текст через Accessibility")
            return
        }
        
        let lines = fullText.components(separatedBy: .newlines)
        guard let lastLine = lines.reversed().first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
        
        let commandText = extractCommandFromPrompt(lastLine)
        if commandText.isEmpty { return }
        
        let transformedText = textTransformer.transformText(commandText)
        if transformedText == commandText { return }
        
        debugLog("🔄 Терминал: '\(commandText)' -> '\(transformedText)'")
        
        // Очистка и вставка
        clearTerminalLine(length: commandText.count)
        replaceTextForTerminal(transformedText)
        switchToNextLayout()
    }
    
    private func extractCommandFromPrompt(_ line: String) -> String {
        var clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Удаляем левый промпт
        let prompts = ["$ ", "% ", "> ", "# ", "ζ ", ": ", "➜ ", "❯ ", "$", "%", ">", "#", "ζ"]
        for p in prompts {
            if let range = clean.range(of: p, options: .backwards) {
                clean = String(clean[range.upperBound...])
                break
            }
        }
        
        // Удаляем правый промпт (git, время и т.д.)
        let rightPromptPattern = "\\s{2,}(\\[.*?\\]|\\(.*?\\)|<.*?>|\\d{2}:\\d{2}(:\\d{2})?|[✔✘]).*?$"
        if let range = clean.range(of: rightPromptPattern, options: .regularExpression) {
            clean.removeSubrange(range)
        }
        
        let result = clean.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? line.trimmingCharacters(in: .whitespaces) : result
    }
    
    private func clearTerminalLine(length: Int) {
        let safeLength = min(length, 300)
        // Ctrl+E (End)
        sendCtrlKey(14)
        usleep(20000)
        
        // Backspace
        for _ in 0..<(safeLength + 2) {
            sendKey(51)
            usleep(1000)
        }
        usleep(50000)
    }
    
    // MARK: - Pasteboard Strategies
    
    /// Вставка для терминалов (без восстановления истории)
    private func replaceTextForTerminal(_ newText: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(newText, forType: .string)
        performCmdV()
    }
    
    /// Основная стратегия замены с восстановлением буфера
    private func replaceTextViaPasteboardStrategy(_ newText: String) {
        let pasteboard = NSPasteboard.general
        
        // 1. Сохраняем старые данные (deep copy)
        // Используем пустой массив, если буфер пуст
        let oldItems = pasteboard.pasteboardItems?.map { $0.manualDeepCopy() } ?? []
        
        // 2. Записываем новый текст
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .init("org.nspasteboard.TransientType")], owner: nil)
        pasteboard.setString(newText, forType: .string)
        
        // 3. Вставка (Cmd+V)
        performCmdV()
        
        // 4. Восстановление буфера
        // К сожалению, здесь нельзя использовать маркерную стратегию, так как мы не можем "прочитать"
        // состояние приложения, чтобы узнать, закончило ли оно вставку.
        // Но так как этап копирования (GET) теперь работает быстро, общий лаг уменьшится.
        // 0.5 сек обычно достаточно для Electron приложений.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            debugLog("📋 Restoring clipboard...")
            pasteboard.clearContents()
            if !oldItems.isEmpty {
                pasteboard.writeObjects(oldItems)
            }
        }
    }
    
    // MARK: - Standard Logic
    
    private func attemptAccessibilityStrategy() {
        // 1. Пробуем Accessibility (самый быстрый и надежный метод для нативных приложений)
        if let selectedText = getSelectedText() {
            debugLog("✅ Text retrieved via Accessibility")
            processTextAndReplace(selectedText, useAccessibilityReplace: true)
            return
        }
        
        // 2. Если AX не сработал (Chrome, Electron, Java), используем Маркерную Стратегию через буфер
        debugLog("ℹ️ Accessibility failed, trying Marker Strategy via Clipboard")
        
        do {
            if let text = try getSelectedTextViaMarkerStrategy() {
                debugLog("✅ Text retrieved via Marker Strategy")
                processTextAndReplace(text, useAccessibilityReplace: false)
            } else {
                debugLog("⚠️ No text selected or app blocked Cmd+C")
            }
        } catch {
            debugLog("❌ Marker Strategy error: \(error)")
        }
    }
    
    private func processTextAndReplace(_ text: String, useAccessibilityReplace: Bool) {
        debugLog("📝 Processing text: '\(text.prefix(30))...' (length: \(text.count))")
        
        // Очистка не нужна для обычного текста, но если вдруг попали в терминал без bundleID
        let cleanText = cleanTerminalInput(text)
        debugLog("🧹 After cleanup: '\(cleanText.prefix(30))...' (length: \(cleanText.count))")
        
        let transformed = textTransformer.transformText(cleanText)
        debugLog("🔄 After transform: '\(transformed.prefix(30))...' (length: \(transformed.count))")
        
        if transformed == cleanText {
            debugLog("ℹ️ Text unchanged after transformation, skipping")
            return
        }
        
        if useAccessibilityReplace {
            // Пробуем заменить через AX API
            debugLog("🔧 Attempting Accessibility replace...")
            if replaceTextViaAccessibility(transformed) {
                debugLog("✅ Accessibility replace returned success")
                
                // КРИТИЧНО: Проверяем, действительно ли замена сработала
                // Chromium-браузеры (Brave, Chrome, Edge) лгут - возвращают success, но не заменяют
                usleep(20000) // 20ms для обновления
                
                if let verifiedText = getSelectedText() {
                    debugLog("🔍 Verification: got '\(verifiedText.prefix(20))...'")
                    
                    // Если текст действительно заменился - отлично!
                    if verifiedText == transformed {
                        debugLog("✅ Verification PASSED: text actually replaced")
                        switchToNextLayout()
                        return
                    }
                    
                    // Если текст НЕ заменился - AX API соврало!
                    debugLog("⚠️ Verification FAILED: AX lied, text not replaced")
                    debugLog("   Expected: '\(transformed.prefix(20))...'")
                    debugLog("   Got:      '\(verifiedText.prefix(20))...'")
                } else {
                    debugLog("⚠️ Verification impossible: can't read text back")
                }
                
                debugLog("📋 Falling back to Pasteboard strategy")
            } else {
                debugLog("⚠️ AX Replace returned failure")
            }
        }
        
        // Fallback на вставку через буфер
        debugLog("📋 Using Pasteboard strategy...")
        replaceTextViaPasteboardStrategy(transformed)
        switchToNextLayout()
    }
    
    // MARK: - Marker Strategy (The "Magic" Part)
    
    /// Получает выделенный текст, используя уникальный маркер.
    /// 1. Ставит в буфер UUID.
    /// 2. Жмет Cmd+C.
    /// 3. Ждет, пока буфер НЕ станет равен UUID.
    /// Это гарантирует, что приложение обработало нажатие.
    private func getSelectedTextViaMarkerStrategy() throws -> String? {
        let pasteboard = NSPasteboard.general
        
        // 1. Сохраняем текущий буфер, чтобы восстановить его, если выделения НЕТ
        let oldItems = pasteboard.pasteboardItems?.map { $0.manualDeepCopy() } ?? []
        
        // 2. Устанавливаем уникальный маркер
        let marker = UUID().uuidString
        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        
        debugLog("🎯 Marker Strategy: Set UUID marker")
        
        // 3. Отправляем Cmd+C
        performCmdC()
        
        // 4. Активное ожидание изменения содержимого (Polling)
        // Максимум 50 проверок по 10мс = 0.5 секунды.
        // Обычно Electron реагирует за 20-50мс.
        var attempts = 0
        var capturedText: String? = nil
        
        while attempts < 50 {
            usleep(10000) // 10ms
            
            if let currentContent = pasteboard.string(forType: .string) {
                // Если в буфере что-то есть и это НЕ наш маркер — победа!
                if currentContent != marker {
                    capturedText = currentContent
                    debugLog("🎯 Marker Strategy: Text captured after \(attempts * 10)ms")
                    break
                }
            }
            
            attempts += 1
        }
        
        // 5. Если текст так и остался маркером, значит ничего не было выделено
        if capturedText == nil {
            debugLog("⚠️ Marker intact after \(attempts * 10)ms. Nothing selected or Copy blocked.")
            // Восстанавливаем старый буфер, так как мы его затерли маркером зря
            pasteboard.clearContents()
            if !oldItems.isEmpty {
                pasteboard.writeObjects(oldItems)
            }
            return nil
        }
        
        return capturedText
    }
    
    // MARK: - Input Simulation
    
    private func performCmdC() {
        let source = CGEventSource(stateID: .hidSystemState)
        // KeyCode 8 is 'C'
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return }
        
        down.flags = .maskCommand
        up.flags = .maskCommand
        
        down.post(tap: .cghidEventTap)
        usleep(5000) // 5ms - микропауза для надежности
        up.post(tap: .cghidEventTap)
    }
    
    private func performCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        // KeyCode 9 is 'V'
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        
        down.flags = .maskCommand
        up.flags = .maskCommand
        
        down.post(tap: .cghidEventTap)
        usleep(5000) // 5ms
        up.post(tap: .cghidEventTap)
    }
    
    private func sendKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    private func sendCtrlKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    // MARK: - Utilities
    
    private func switchToNextLayout() {
        keyboardLayoutManager.switchToNextLayout()
    }
    
    private func cleanTerminalInput(_ text: String) -> String {
        // Упрощенная версия для стандартного текста
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Базовая защита от случайного срабатывания на коротких строках
        if clean.count < 3 && !clean.contains("$") { return clean }
        return extractCommandFromPrompt(text)
    }
    
    private func getAXAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.1)
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return error == .success ? result : nil
    }
    
    private func getSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = getAXAttribute(element, kAXFocusedUIElementAttribute as String) as! AXUIElement? else { return nil }
        
        if let text = getAXAttribute(focused, kAXSelectedTextAttribute as String) as? String, !text.isEmpty {
            return text
        }
        return nil
    }
    
    private func replaceTextViaAccessibility(_ newText: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = getAXAttribute(element, kAXFocusedUIElementAttribute as String) as! AXUIElement? else { return false }
        return AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, newText as CFString) == .success
    }
}
