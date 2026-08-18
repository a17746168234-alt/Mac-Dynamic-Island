import Defaults
import SwiftUI

struct DailyTodoView: View {
    @ObservedObject private var manager = DailyTodoManager.shared
    @State private var draft = ""

    /// 列表区域宽度：日历开启时为 145（原待办区域），日历关闭时为 165（原日历区域）
    var width: CGFloat = 145

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var items: [DailyTodoItem] {
        var list = manager.items(for: today)
        if Defaults[.todoHideCompleted] {
            list = list.filter { !$0.isCompleted }
        }
        let limit = Defaults[.todoMaxVisibleItems]
        if limit > 0 && list.count > limit {
            list = Array(list.prefix(limit))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                TextField("Add a task…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 6) {
                                Button {
                                    manager.toggle(item, for: today)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? .blue : .secondary)
                                    Text(item.title)
                                        .strikethrough(item.isCompleted, color: .secondary)
                                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    manager.remove(item, for: today)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(9)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func addTask() {
        manager.add(draft, for: today)
        draft = ""
    }
}
