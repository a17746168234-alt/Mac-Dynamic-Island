#!/usr/bin/env python3
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ShelfDragRegressionTests(unittest.TestCase):
    def test_dragging_never_removes_or_moves_the_shelf_source(self):
        shelf_view = (
            ROOT / "MacDynamicIsland/components/Shelf/Views/ShelfItemView.swift"
        ).read_text(encoding="utf-8")
        constants = (ROOT / "MacDynamicIsland/models/Constants.swift").read_text(
            encoding="utf-8"
        )
        settings = (
            ROOT / "MacDynamicIsland/components/Settings/SettingsView.swift"
        ).read_text(encoding="utf-8")

        drag_source = shelf_view[
            shelf_view.index("final class DraggableClickView") :
        ]
        operation_policy = drag_source[
            drag_source.index("sourceOperationMaskFor") :
            drag_source.index("willBeginAt")
        ]
        drag_ended = drag_source[
            drag_source.index("endedAt screenPoint") :
            drag_source.index("ignoreModifierKeys")
        ]

        self.assertNotIn("autoRemoveShelfItems", shelf_view + constants + settings)
        self.assertNotIn("ShelfStateViewModel.shared.remove", drag_ended)
        self.assertNotIn(".move", operation_policy)
        self.assertIn("case .outsideApplication:", operation_policy)
        self.assertIn("return [.copy]", operation_policy)

    def test_drag_completion_and_manual_remove_are_preserved(self):
        shelf_view = (
            ROOT / "MacDynamicIsland/components/Shelf/Views/ShelfItemView.swift"
        ).read_text(encoding="utf-8")
        item_view_model = (
            ROOT / "MacDynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift"
        ).read_text(encoding="utf-8")
        boring_view_model = (
            ROOT / "MacDynamicIsland/models/BoringViewModel.swift"
        ).read_text(encoding="utf-8")
        content_view = (ROOT / "MacDynamicIsland/ContentView.swift").read_text(
            encoding="utf-8"
        )
        constants = (ROOT / "MacDynamicIsland/models/Constants.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn("onDragEnded?(screenPoint)", shelf_view)
        self.assertIn("ShelfFileDragCompletionMonitor.shared.finish", shelf_view)
        self.assertIn("func finishFileDrag(at position: NSPoint)", boring_view_model)
        self.assertIn("clearDropInteractionState()", boring_view_model)
        self.assertIn('addMenuItem(title: "Remove")', item_view_model)
        self.assertIn('case "Remove":', item_view_model)
        self.assertIn("ShelfActionService.remove(it)", item_view_model)
        self.assertIn("shelfContextMenuDidDismiss", constants)

        context_menu = item_view_model[
            item_view_model.index("func presentContextMenu") :
            item_view_model.index("private func isDirectory")
        ]
        self.assertLess(
            context_menu.index("NSMenu.popUpContextMenu"),
            context_menu.index("NotificationCenter.default.post"),
        )
        self.assertIn(
            "publisher(for: .shelfContextMenuDidDismiss)", content_view
        )
        self.assertIn("scheduleAutomaticClose()", content_view)


if __name__ == "__main__":
    unittest.main()
