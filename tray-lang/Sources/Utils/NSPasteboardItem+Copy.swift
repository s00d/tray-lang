import AppKit

/// Расширение для ручного копирования NSPasteboardItem
/// NSPasteboardItem не поддерживает протокол NSCopying,
/// поэтому нужно вручную создавать новый экземпляр и переносить все типы данных
extension NSPasteboardItem {
    /// Создает глубокую копию NSPasteboardItem
    /// Переносит все типы данных из текущего элемента в новый
    func manualDeepCopy() -> NSPasteboardItem {
        let newItem = NSPasteboardItem()
        
        // Перебираем все типы данных в текущем элементе
        for type in self.types {
            // Извлекаем данные и устанавливаем их в новый элемент
            if let data = self.data(forType: type) {
                newItem.setData(data, forType: type)
            }
        }
        
        return newItem
    }
}
