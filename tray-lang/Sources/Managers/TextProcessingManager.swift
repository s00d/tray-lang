import Foundation
import AppKit
import ApplicationServices

enum SelectionStatus {
    case selected
    case notSelected
    case unknown
}

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
        "com.microsoft.VSCode",         // VS Code (терминал)
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
            debugLog("✅ Распознан терминал: \(frontmostApp.localizedName ?? bundleID)")
            handleTerminalProcessing(app: frontmostApp)
            return
        }
        
        // 2. СТАНДАРТНАЯ ЛОГИКА
        debugLog("ℹ️ Обычное приложение, используем стандартную стратегию")
        attemptAccessibilityStrategy()
    }
    
    // MARK: - Terminal Logic (Backspace Strategy)
    
    private func handleTerminalProcessing(app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // 1. Получаем весь текст окна или текущей области
        guard let focused = getAXAttribute(appElement, kAXFocusedUIElementAttribute as String) as! AXUIElement?,
              let fullText = getAXAttribute(focused, kAXValueAttribute as String) as? String,
              !fullText.isEmpty else {
            debugLog("❌ Терминал: Не удалось прочитать текст через Accessibility")
            return
        }
        
        debugLog("📋 Терминал: Прочитано \(fullText.count) символов")
        
        // 2. Вытаскиваем последнюю строку (текущую команду)
        let lines = fullText.components(separatedBy: .newlines)
        guard let lastLine = lines.reversed().first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            debugLog("ℹ️ Терминал: Пустая строка, нечего обрабатывать")
            return
        }
        
        debugLog("🖥 Сырая строка: '\(lastLine)'")
        
        // 3. Отделяем промпт (user % command)
        let commandText = extractCommandFromPrompt(lastLine)
        if commandText.isEmpty {
            debugLog("⚠️ Терминал: Команда пустая после извлечения промпта")
            return
        }
        
        debugLog("🖥 Извлеченная команда: '\(commandText)'")
        
        // 4. Трансформируем
        let transformedText = textTransformer.transformText(commandText)
        if transformedText == commandText {
            debugLog("ℹ️ Терминал: Текст не изменился после трансформации")
            return
        }
        
        debugLog("🔄 Терминал: '\(commandText)' -> '\(transformedText)'")
        
        // 5. ОЧИСТКА: Удаляем старый текст через Backspace
        // Это самый надежный способ, так как терминал не дает стереть промпт
        clearTerminalLine(length: commandText.count)
        
        // 6. ВСТАВКА
        replaceTextViaPasteboardStrategy(transformedText)
        
        // 7. Переключение языка
        switchToNextLayout()
        
        debugLog("✅ Терминал: Замена завершена")
    }
    
    /// Очищает текст от терминального "мусора"
    /// Удаляет левый промпт (ζ, $, %, >, #, ➜, ❯) и правый промпт (время, git статус, etc)
    private func extractCommandFromPrompt(_ line: String) -> String {
        var clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // ШАГ 1: Удаляем ЛЕВЫЙ промпт (user@host $ command)
        // Ищем типичные разделители промптов
        let prompts = ["$ ", "% ", "> ", "# ", "ζ ", ": ", "➜ ", "❯ ", "$", "%", ">", "#", "ζ"]
        
        for p in prompts {
            if let range = clean.range(of: p, options: .backwards) {
                // Берём текст ПОСЛЕ промпта
                clean = String(clean[range.upperBound...])
                break
            }
        }
        
        // ШАГ 2: Удаляем ПРАВЫЙ промпт (git статус, время, etc)
        // Паттерн: много пробелов (2+) перед блоком в скобках [] () <> или временем HH:MM:SS
        // Примеры правых промптов:
        // - "   [5d7692a]" (git hash)
        // - "   (main)" (git branch)
        // - "   14:35:22" (время)
        // - "   <env>" (виртуальное окружение)
        let rightPromptPattern = "\\s{2,}(\\[.*?\\]|\\(.*?\\)|<.*?>|\\d{2}:\\d{2}(:\\d{2})?|[✔✘]).*?$"
        
        if let range = clean.range(of: rightPromptPattern, options: .regularExpression) {
            clean.removeSubrange(range)
        }
        
        // ШАГ 3: Финальная очистка пробелов
        clean = clean.trimmingCharacters(in: .whitespaces)
        
        // Если после всех очисток ничего не осталось, возвращаем исходную строку (fallback)
        return clean.isEmpty ? line.trimmingCharacters(in: .whitespaces) : clean
    }
    
    /// ЖЕЛЕЗОБЕТОННАЯ СТРАТЕГИЯ: Ctrl+E (в конец) + Backspace N раз
    /// Работает везде: zsh, bash, fish, vi-mode, ssh сессии
    /// Терминал физически не даст стереть промпт - это его встроенная защита
    private func clearTerminalLine(length: Int) {
        // Ограничитель безопасности
        let safeLength = min(length, 300)
        
        debugLog("🧹 Терминал: Очистка через Ctrl+E + Backspace x \(safeLength)")
        
        // 1. Жмем Ctrl+E (End), чтобы убедиться, что курсор в конце
        sendCtrlKey(14) // 'E' = 14
        usleep(20000) // 20ms
        
        // 2. Долбим Backspace нужное количество раз
        // Добавляем +2 на случай лишних пробелов или ошибок подсчета
        // Терминал не даст стереть промпт, так что можно смело
        for i in 0..<(safeLength + 2) {
            sendKey(51) // Backspace = 51
            usleep(1000) // 1ms (быстро, но терминал успевает)
            
            // Логируем прогресс для длинных команд
            if safeLength > 50 && (i + 1) % 25 == 0 {
                debugLog("  🧹 Удалено \(i + 1)/\(safeLength) символов...")
            }
        }
        
        // Небольшая пауза перед вставкой
        usleep(50000) // 50ms
        
        debugLog("✅ Терминал: Строка очищена")
    }
    
    // MARK: - Helpers & Standard Logic
    
    private func replaceTextViaPasteboardStrategy(_ newText: String) {
        let pasteboard = NSPasteboard.general
        // ✅ ИСПРАВЛЕНО: NSPasteboardItem не поддерживает NSCopying
        // Используем ручное копирование через extension
        let oldItems = pasteboard.pasteboardItems?.map { $0.manualDeepCopy() } ?? []
        
        pasteboard.clearContents()
        // TransientType - чтобы не мусорить в истории Maccy/Paste
        pasteboard.declareTypes([.string, .init("org.nspasteboard.TransientType")], owner: nil)
        pasteboard.setString(newText, forType: .string)
        
        // Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        
        // Отложенное восстановление буфера (fix для Electron apps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            pasteboard.writeObjects(oldItems)
        }
    }
    
    /// Отправляет простое нажатие клавиши (БЕЗ модификаторов)
    /// КРИТИЧЕСКИ ВАЖНО: Очищаем флаги, чтобы не было Cmd+Backspace
    private func sendKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        // ВАЖНО: Очищаем флаги, чтобы не было Cmd+Backspace от хоткея
        down.flags = []
        up.flags = []
        
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    /// Отправляет клавишу с модификатором Control
    private func sendCtrlKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        // Только Control, остальные модификаторы сбрасываем
        down.flags = .maskControl
        up.flags = .maskControl
        
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    private func switchToNextLayout() {
        keyboardLayoutManager.switchToNextLayout()
    }
    
    // MARK: - Standard Application Logic
    
    private func attemptAccessibilityStrategy() {
        if let selectedText = getSelectedText() {
            // Очищаем от возможного терминального мусора (на всякий случай)
            let cleanText = cleanTerminalInput(selectedText)
            let transformed = textTransformer.transformText(cleanText)
            if transformed == cleanText { return }
            
            if replaceTextViaAccessibility(transformed) {
                switchToNextLayout()
            } else {
                replaceTextViaPasteboardStrategy(transformed)
                switchToNextLayout()
            }
        } else {
            processViaClipboardStrategy()
        }
    }
    
    private func processViaClipboardStrategy() {
        do {
            guard let text = try getSelectedTextViaHotkeys() else { return }
            // Очищаем от возможного терминального мусора (на всякий случай)
            let cleanText = cleanTerminalInput(text)
            let transformed = textTransformer.transformText(cleanText)
            if transformed == cleanText { return }
            replaceTextViaPasteboardStrategy(transformed)
            switchToNextLayout()
        } catch { }
    }
    
    /// Универсальная очистка текста от терминального "мусора"
    /// Может использоваться для любого текста, не только из терминалов
    /// Удаляет: левый промпт (ζ, $, %, etc), правый промпт ([git], время, etc)
    private func cleanTerminalInput(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Если текст короткий и не содержит специальных символов - не трогаем
        if clean.count < 3 || (!clean.contains("$") && !clean.contains("%") && 
                                !clean.contains("ζ") && !clean.contains("➜") && 
                                !clean.contains("[") && !clean.contains("(")) {
            return clean
        }
        
        // ШАГ 1: Удаляем ЛЕВЫЙ промпт
        // Паттерн: всё до последнего вхождения промпта ($, %, >, #, ζ, ➜, ❯)
        let leftPromptPattern = "^.*?[ζ$%>#➜❯]\\s+"
        if let range = clean.range(of: leftPromptPattern, options: .regularExpression) {
            clean.removeSubrange(range)
        }
        
        // ШАГ 2: Удаляем ПРАВЫЙ промпт
        // Паттерн: 2+ пробела перед блоком в скобках [] () <> или временем HH:MM:SS
        let rightPromptPattern = "\\s{2,}(\\[.*?\\]|\\(.*?\\)|<.*?>|\\d{2}:\\d{2}(:\\d{2})?|[✔✘]).*?$"
        if let range = clean.range(of: rightPromptPattern, options: .regularExpression) {
            clean.removeSubrange(range)
        }
        
        // ШАГ 3: Финальная очистка
        clean = clean.trimmingCharacters(in: .whitespaces)
        
        return clean.isEmpty ? text : clean
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
    
    private func getSelectedTextViaHotkeys() throws -> String? {
        let pasteboard = NSPasteboard.general
        let oldCount = pasteboard.changeCount
        
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        
        var attempts = 0
        while pasteboard.changeCount == oldCount && attempts < 10 {
            usleep(20000) // 20ms
            attempts += 1
        }
        
        return pasteboard.changeCount == oldCount ? nil : pasteboard.string(forType: .string)
    }
}
