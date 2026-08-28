from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SettingsInteractionRegressionTests(unittest.TestCase):
    def test_settings_entry_is_always_available_and_selection_follows_icon(self):
        tabs = (ROOT / "MacDynamicIsland/components/Tabs/TabSelectionView.swift").read_text()
        button = (ROOT / "MacDynamicIsland/components/Tabs/TabButton.swift").read_text()
        constants = (ROOT / "MacDynamicIsland/models/Constants.swift").read_text()

        self.assertNotIn("settingsIconInNotch", tabs + constants)
        self.assertIn('TabModel(label: String(localized: "Settings")', tabs)
        self.assertIn("preservesTrailingIconPosition: true", tabs)
        self.assertIn("Circle()", button)
        self.assertLess(button.index(".background"), button.index(".frame("))
        self.assertIn("alignment: iconAlignment", button)

    def test_settings_changes_are_deferred_until_notch_closes(self):
        content = (ROOT / "MacDynamicIsland/ContentView.swift").read_text()
        app = (ROOT / "MacDynamicIsland/MacDynamicIslandApp.swift").read_text()
        policy = (ROOT / "MacDynamicIsland/models/NotchInteractionPolicy.swift").read_text()

        self.assertIn("case settingsInteraction", policy)
        self.assertIn("beginSettingsHoverMonitoring", content)
        self.assertIn("pointerInsideSettings", content)
        self.assertIn("deferWindowChangesWhileEditingSettings", app)
        self.assertIn("applyPendingSettingsWindowChanges", app)
        self.assertIn("NotificationCenter.default.post(name: .notchDidClose", (
            ROOT / "MacDynamicIsland/models/BoringViewModel.swift"
        ).read_text())

    def test_about_page_has_one_click_full_quit_button(self):
        settings = (ROOT / "MacDynamicIsland/components/Settings/SettingsView.swift").read_text()

        self.assertIn('Label("完全退出 Mac灵动岛", systemImage: "power")', settings)
        self.assertIn("NSApp.terminate(nil)", settings)

    def test_prediction_is_fully_embedded_in_battery_settings(self):
        settings = (ROOT / "MacDynamicIsland/components/Settings/SettingsView.swift").read_text()
        sidebar = settings[
            settings.index("List(selection: $selectedTab)"):
            settings.index(".listStyle(SidebarListStyle())")
        ]
        charge = settings[
            settings.index("struct Charge: View"):
            settings.index("//struct Downloads")
        ]

        self.assertNotIn('.tag("续航预测")', sidebar)
        self.assertNotIn("struct BatteryPredictionSettings", settings)
        for expected in (
            'Text("续航预测")',
            'Text("本机学习状态")',
            'Text("数据与隐私")',
            'Toggle("启用个性化续航预测"',
            "batteryModel.resetPersonalPredictionHistory()",
        ):
            self.assertIn(expected, charge)

    def test_launcher_page_is_removed_and_toggle_is_second_appearance_row(self):
        settings = (ROOT / "MacDynamicIsland/components/Settings/SettingsView.swift").read_text()
        sidebar = settings[
            settings.index("List(selection: $selectedTab)"):
            settings.index(".listStyle(SidebarListStyle())")
        ]
        appearance = settings[
            settings.index("struct Appearance: View"):
            settings.index("struct Advanced: View")
        ]

        self.assertNotIn('.tag("Launcher")', sidebar)
        self.assertNotIn("struct LauncherSettings", settings)
        self.assertLess(
            appearance.index('Toggle("Always show tabs"'),
            appearance.index("Defaults.Toggle(key: .showApplicationLauncher)"),
        )
        self.assertIn("coordinator.currentView = .home", appearance)


if __name__ == "__main__":
    unittest.main()
