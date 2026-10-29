# Float

Float keeps references to files and folders in a small floating stack. It does not move or copy the originals when a file is added.

- The stack starts compact, with the latest three file thumbnails and an item count.
- Hover for 200 ms, or click the stack/count, to open a narrow vertical shelf. Leaving it for 650 ms folds it away. A menu or active drag keeps it open.
- Drag the file artwork to carry every file in the stack. Drag the wire paperclip, or the shelf's empty header, to move Float.
- Drop files onto the compact stack or expanded shelf to add them. Existing paths are kept once.
- Each shelf item supports normal multi-selection and dragging selected files into other apps. The destination controls the copy/move operation.
- The options menu retains icon/list views, adding files, preview, reveal, sharing, copying, removing references and attachment to any screen edge. Near-edge moves also snap. At the top edge, the collapsed stack leaves a small count tab visible; hover or click reveals it.
- The shelf fits the monitor's work area and scrolls larger collections. Native light/dark appearance, English/Turkish labels and reduced-motion preferences apply.

| Action | macOS | Windows |
| --- | --- | --- |
| Select all (also opens the stack) | Command+A | Ctrl+A |
| Copy files | Command+C | Ctrl+C |
| Copy paths | Command+Option+C | Ctrl+Shift+C |
| Add clipboard files | Command+V | Ctrl+V |
| Preview | Space | Space |
| Open | Return / Command+O / double-click | Enter / Ctrl+O / double-click |
| Reveal | Command+R | Ctrl+R |
| Remove selected references | Delete | Delete |
| Clear selection, then collapse | Escape, Escape | Escape, Escape |

Removing a reference, clearing Float or closing its window does not delete any original file.

## Verification

`Nashi --float-smoke <output-directory>` runs an opt-in native AppKit replay with generated fixtures and captures compact/expanded/list/Turkish states. It checks controls, keyboard selection, top-edge tuck/reveal and byte-for-byte preservation of the originals. `--keep-float-open` leaves a test-only native drag source/destination open for Computer Use; all its files are restricted to that output directory. It does not install a global input driver or request additional system access.

Windows native parity smoke captures the compact/expanded shelf and exercises selection, deduplication, Escape, collapse/reopen and removal with real keyboard input. Cross-compilation alone is not counted as native Windows verification.
