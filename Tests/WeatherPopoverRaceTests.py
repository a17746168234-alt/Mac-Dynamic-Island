#!/usr/bin/env python3
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WeatherPopoverRaceTests(unittest.TestCase):
    def test_city_picker_opens_to_the_left_as_requested(self):
        source = (
            ROOT / "MacDynamicIsland/components/Weather/WeatherView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn(
            ".popover(isPresented: $isCityPickerPresented, arrowEdge: .trailing)",
            source,
            "箭头必须在弹窗右侧，让城市搜索窗口向天气模块左侧展开",
        )

    def test_city_picker_marks_popover_active_before_requesting_presentation(self):
        source = (
            ROOT / "MacDynamicIsland/components/Weather/WeatherView.swift"
        ).read_text(encoding="utf-8")

        button_action_start = source.index("citySelectionError = nil")
        button_action_end = source.index("} label:", button_action_start)
        button_action = source[button_action_start:button_action_end]

        active_assignment = "vm.isWeatherPopoverActive = true"
        self.assertIn(
            active_assignment,
            button_action,
            "打开城市搜索前必须立即登记天气弹窗状态",
        )
        active_index = button_action.index(active_assignment)
        presented_index = button_action.index("isCityPickerPresented = true")
        self.assertLess(
            active_index,
            presented_index,
            "必须先阻止灵动岛自动收回，再请求显示城市搜索窗口",
        )


if __name__ == "__main__":
    unittest.main()
