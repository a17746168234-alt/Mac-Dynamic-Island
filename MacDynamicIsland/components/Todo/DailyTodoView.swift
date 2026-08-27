import Defaults
import SwiftUI

struct DailyTodoView: View {
    @ObservedObject private var manager = DailyTodoManager.shared
    @State private var draft = ""
    @State private var hoveredItemID: UUID?

    /// 列表区域宽度：日历开启时为 145（原待办区域），日历关闭时为 165（原日历区域）
    var width: CGFloat = 145

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var allItems: [DailyTodoItem] {
        manager.items(for: today)
    }

    private var items: [DailyTodoItem] {
        var list = allItems
        if Defaults[.todoHideCompleted] {
            list = list.filter { !$0.isCompleted }
        }
        let limit = Defaults[.todoMaxVisibleItems]
        if limit > 0 && list.count > limit {
            list = Array(list.prefix(limit))
        }
        return list
    }

    private var completedCount: Int {
        allItems.filter(\.isCompleted).count
    }

    private var remainingCount: Int {
        allItems.count - completedCount
    }

    private var completionProgress: CGFloat {
        guard !allItems.isEmpty else { return 0 }
        return CGFloat(completedCount) / CGFloat(allItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                TextField("添加待办…", text: $draft)
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

            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(items) { item in
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
                                    .opacity(hoveredItemID == item.id ? 1 : 0)
                                    .accessibilityHidden(hoveredItemID != item.id)
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    Color.white.opacity(hoveredItemID == item.id ? 0.055 : 0),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                                .onHover { isHovering in
                                    hoveredItemID = isHovering ? item.id : nil
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            todoFooter
        }
        .padding(9)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func addTask() {
        manager.add(draft, for: today)
        draft = ""
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: allItems.isEmpty ? "checklist" : "checkmark.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(allItems.isEmpty ? Color.secondary : Color.blue)
            Text(allItems.isEmpty ? "今天暂无待办" : "今天的待办已完成")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var todoFooter: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * completionProgress)
                }
            }
            .frame(height: 3)

            HStack(spacing: 4) {
                Text(allItems.isEmpty ? "今天暂无安排" : "\(remainingCount) 项待完成")
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(completedCount)/\(allItems.count)")
                    .monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日待办完成 \(completedCount) 项，共 \(allItems.count) 项")
    }
}
