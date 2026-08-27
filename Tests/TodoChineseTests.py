#!/usr/bin/env python3
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TodoChineseTests(unittest.TestCase):
    def test_todo_views_do_not_show_english_labels(self):
        sources = "\n".join(
            (ROOT / path).read_text(encoding="utf-8")
            for path in (
                "MacDynamicIsland/components/Todo/DailyTodoView.swift",
                "MacDynamicIsland/components/Settings/SettingsView.swift",
            )
        )
        for english in (
            "Add a task…",
            "Show todo area",
            "Hide completed tasks",
            "Maximum visible tasks",
            "Clear today's completed tasks",
            "Clear all todos",
        ):
            self.assertNotIn(f'"{english}"', sources)

        for chinese in (
            "添加待办…",
            "今天暂无待办",
            "今天的待办已完成",
            "今天暂无安排",
            "在首页显示待办",
            "隐藏已完成待办",
            "最多显示数量",
            "清除今天已完成的待办",
            "清除全部待办",
        ):
            self.assertIn(f'"{chinese}"', sources)

        self.assertIn("项待完成", sources)


if __name__ == "__main__":
    unittest.main()
