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


if __name__ == "__main__":
    unittest.main()
