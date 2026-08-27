import Foundation

struct DailyTodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

@MainActor
final class DailyTodoManager: ObservableObject {
    static let shared = DailyTodoManager()

    @Published private(set) var itemsByDate: [String: [DailyTodoItem]] = [:]

    private let storageKey = "MacDynamicIsland.DailyTodos"
    private let calendar = Calendar.current

    private init() {
        load()
    }

    func items(for date: Date) -> [DailyTodoItem] {
        itemsByDate[key(for: date)] ?? []
    }

    func add(_ title: String, for date: Date) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let dateKey = key(for: date)
        itemsByDate[dateKey, default: []].append(DailyTodoItem(title: cleaned))
        save()
    }

    func toggle(_ item: DailyTodoItem, for date: Date) {
        let dateKey = key(for: date)
        guard let index = itemsByDate[dateKey]?.firstIndex(where: { $0.id == item.id }) else { return }
        itemsByDate[dateKey]?[index].isCompleted.toggle()
        save()
    }

    func remove(_ item: DailyTodoItem, for date: Date) {
        let dateKey = key(for: date)
        itemsByDate[dateKey]?.removeAll { $0.id == item.id }
        if itemsByDate[dateKey]?.isEmpty == true { itemsByDate.removeValue(forKey: dateKey) }
        save()
    }

    /// 清除指定日期中所有已完成的待办
    func clearCompleted(for date: Date) {
        let dateKey = key(for: date)
        itemsByDate[dateKey]?.removeAll { $0.isCompleted }
        if itemsByDate[dateKey]?.isEmpty == true { itemsByDate.removeValue(forKey: dateKey) }
        save()
    }

    /// 清空所有日期的全部待办
    func clearAll() {
        itemsByDate.removeAll()
        save()
    }

    private func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [DailyTodoItem]].self, from: data)
        else { return }
        itemsByDate = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(itemsByDate) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
