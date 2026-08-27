#!/usr/bin/env python3
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PerformanceRegressionTests(unittest.TestCase):
    def source(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_spectrum_and_idle_face_do_not_leave_repeating_timers(self):
        visualizer = self.source("MacDynamicIsland/components/Music/MusicVisualizer.swift")
        face = self.source("MacDynamicIsland/components/AnimatedFace.swift")

        self.assertNotIn("Timer.scheduledTimer", visualizer)
        self.assertIn("CAKeyframeAnimation", visualizer)
        self.assertIn("dismantleNSView", visualizer)
        self.assertIn("!batteryModel.isInLowPowerMode", self.source("MacDynamicIsland/ContentView.swift"))
        self.assertNotIn("Timer.scheduledTimer", face)
        self.assertIn("while !Task.isCancelled", face)

    def test_launcher_is_lazy_and_uses_a_bounded_icon_cache(self):
        app = self.source("MacDynamicIsland/MacDynamicIslandApp.swift")
        manager = self.source("MacDynamicIsland/managers/ApplicationLauncherManager.swift")
        view = self.source("MacDynamicIsland/components/Launcher/ApplicationLauncherView.swift")

        self.assertNotIn("prewarmIcons", app)
        self.assertNotIn("ApplicationLauncherManager.shared.startMonitoring()", app)
        self.assertIn("NSCache<NSString, NSImage>", manager)
        self.assertIn("cache.countLimit = 32", manager)
        self.assertIn("cache.totalCostLimit = 16 * 1_024 * 1_024", manager)
        self.assertIn(".seconds(300)", manager)
        self.assertIn("manager.stopMonitoring()", view)

    def test_disabled_background_features_really_sleep(self):
        bluetooth = self.source("MacDynamicIsland/managers/BluetoothDeviceStatusManager.swift")
        clipboard = self.source("MacDynamicIsland/managers/ClipboardHistoryManager.swift")

        self.assertNotIn("withTimeInterval: 8", bluetooth)
        self.assertIn("setEnabled(Defaults[.showBluetoothBatteryNotifications])", bluetooth)
        self.assertIn("connectNotification?.unregister()", bluetooth)
        self.assertIn("timer.tolerance = 0.25", clipboard)
        self.assertIn("maximumStoredPayloadSize = 16 * 1_024 * 1_024", clipboard)
        self.assertIn("stopMonitoring()", clipboard)

    def test_large_root_views_are_not_forced_into_offscreen_groups(self):
        content = self.source("MacDynamicIsland/ContentView.swift")
        home = self.source("MacDynamicIsland/components/Notch/NotchHomeView.swift")

        root_frame = ".frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)"
        root_tail = content[content.index(root_frame):content.index(root_frame) + 220]
        self.assertNotIn(".compositingGroup()", root_tail)
        self.assertNotIn("MusicControlsView().drawingGroup().compositingGroup()", home)

    def test_adaptive_motion_remains_event_driven(self):
        content = self.source("MacDynamicIsland/ContentView.swift")
        home = self.source("MacDynamicIsland/components/Notch/NotchHomeView.swift")
        policy = self.source("MacDynamicIsland/models/NotchInteractionPolicy.swift")
        view_model = self.source("MacDynamicIsland/models/BoringViewModel.swift")

        self.assertIn("scheduleAutomaticClose", content)
        self.assertIn("pointerInsideGraceArea", content)
        self.assertIn("NotchMotionProfile", policy)
        self.assertIn("reducedMotion", policy)
        self.assertIn("lowPower", policy)
        self.assertIn("presentationCompletionTask?.cancel()", view_model)
        self.assertIn("presentationPhase = .opening", view_model)
        self.assertIn("presentationPhase = .closing", view_model)
        self.assertNotIn("Timer.scheduledTimer", home)

    def test_product_motion_uses_shared_tokens_and_bounded_blur(self):
        matters = self.source("MacDynamicIsland/sizing/matters.swift")
        content = self.source("MacDynamicIsland/ContentView.swift")
        home = self.source("MacDynamicIsland/components/Notch/NotchHomeView.swift")
        header = self.source("MacDynamicIsland/components/Notch/BoringHeader.swift")

        for token in (
            "static let press",
            "static let selection",
            "static let content",
            "static let status",
            "static let drag",
            "static let pageExit",
            "static let pageEnter",
        ):
            self.assertIn(token, matters)

        product_sources = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "MacDynamicIsland").rglob("*.swift")
        )
        self.assertIsNone(re.search(r"withAnimation\s*\{", product_sources))
        self.assertNotIn(".animation()", product_sources)

        self.assertIn("withAnimation(AppMotion.pageExit)", content)
        self.assertIn("withAnimation(AppMotion.pageEnter)", content)
        self.assertIn(".milliseconds(180)", content)
        self.assertEqual(content.count("vm.presentationPhase != .closed ? vm.notchSize"), 2)
        self.assertIn("The lightweight outer shell owns the closing spring", content)
        self.assertNotIn("keepsExpandedLayoutMounted", content)
        self.assertIn(".clipShape(currentNotchShape)", content)
        self.assertIn("resetCurrentViewAfterClose()", self.source("MacDynamicIsland/models/BoringViewModel.swift"))
        self.assertIn("albumArtBackground", home)
        self.assertIn("albumArtDarkOverlay", home)
        self.assertIn(".blur(radius: 40)", home)
        self.assertIn(".blur(radius: 50)", home)
        self.assertIn("vm.notchState == .closed ? 10 : 0", home)
        self.assertEqual(header.count("vm.notchState == .closed ? 8 : 0"), 2)


if __name__ == "__main__":
    unittest.main()
