# Interface language

Choose **Settings → General → Language → English / Türkçe** on either desktop. The choice is saved with the user's preferences and applies to open Nashi views without restarting or discarding an editor draft. Existing installations keep English until a language is selected.

Turkish includes Home, Library, Settings, tool and action names, window arrangement, editor controls and completion/progress UI. Search accepts translated tool names. File names, clipboard/document contents, metadata values, format identifiers and shortcut keys remain unchanged. Native operating-system dialogs and third-party playback controls follow their platform's language behavior.

Both desktops use `Sources/NashiCore/Resources/Turkish.json`. Run `python3 scripts/generate-localizations.py` after changing it; `--check` verifies the generated macOS native string tables. Swift tests and the Windows core verifier check tool/layout coverage, Turkish casing, interpolation and preference compatibility. The opt-in Mac `--localization-smoke <directory>` and Windows native suite exercise the real language picker, live refresh and draft preservation using isolated profiles.
