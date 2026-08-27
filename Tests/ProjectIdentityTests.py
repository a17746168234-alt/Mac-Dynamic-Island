#!/usr/bin/env python3
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProjectIdentityTests(unittest.TestCase):
    def test_engineering_name_is_updated(self):
        self.assertTrue((ROOT / "MacDynamicIsland.xcodeproj/project.pbxproj").is_file())
        self.assertTrue((ROOT / "MacDynamicIsland/MacDynamicIslandApp.swift").is_file())
        self.assertFalse((ROOT / "boringNotch.xcodeproj").exists())
        self.assertFalse((ROOT / "boringNotch").exists())

    def test_existing_app_identity_and_user_data_locations_are_preserved(self):
        project = (ROOT / "MacDynamicIsland.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        shelf = (
            ROOT / "MacDynamicIsland/components/Shelf/Services/ShelfPersistenceService.swift"
        ).read_text(encoding="utf-8")
        youtube = (
            ROOT
            / "MacDynamicIsland/MediaControllers/YouTube Music Controller/YouTubeMusicNetworking.swift"
        ).read_text(encoding="utf-8")

        self.assertEqual(project.count("PRODUCT_BUNDLE_IDENTIFIER = theboringteam.boringnotch;"), 2)
        self.assertEqual(
            project.count(
                "PRODUCT_BUNDLE_IDENTIFIER = theboringteam.boringnotch.BoringNotchXPCHelper;"
            ),
            2,
        )
        self.assertEqual(project.count('INFOPLIST_KEY_CFBundleDisplayName = "Mac灵动岛";'), 2)
        self.assertIn('appendingPathComponent("boringNotch", isDirectory: true)', shelf)
        self.assertIn('"\\(baseURL)/auth/boringNotch"', youtube)


if __name__ == "__main__":
    unittest.main()
