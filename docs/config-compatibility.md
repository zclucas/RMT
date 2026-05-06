# Config Compatibility

RMT configuration and macro data are owned by the AutoHotkey side. The WebView UI should treat them as state returned by AHK, not as files to edit directly.

## Maintenance Rules

- Do not remove or rename saved fields without a compatibility path.
- Prefer adding default values for new fields instead of requiring users to recreate settings.
- Keep UI labels and internal saved field names separate where possible.
- Before changing a saved value format, write down the old format, new format, and rollback behavior.
- Keep `Setting/` runtime data out of source control.

## Recommended Migration Pattern

For future config changes:

1. Add a config version field if the target file does not already have one.
2. On startup, read the old data with tolerant defaults.
3. If fields are missing, fill defaults in memory.
4. Before writing a migrated file, create a timestamped backup.
5. Save the new format only after the app has a complete valid state.
6. Log or surface a concise message if migration fails.

## WebView-Specific Rules

- React may request updates through bridge actions such as `updateSetting`, `updateTool`, `updateItem`, and `updateFold`.
- React must not infer saved file paths or write config files directly.
- AHK should normalize booleans, numbers, hotkeys, and enum values before returning state.
- AHK should call `RmtPostState()` when non-WebView flows change settings or tool state.

## Compatibility Checklist

Use this checklist before release when saved data behavior changes:

- Existing settings load without errors.
- Missing new fields receive defaults.
- Saving and restarting preserves old and new values.
- Macro table edits still round-trip through existing save/load code.
- Hotkeys remain registered or show a clear failure.
- A backup exists before any destructive migration.

## Fixture Check

Run this check after changing `RmtBuildState()` or saved field defaults:

```powershell
.\scripts\verify-rmt-build-state-fixtures.ps1
```

The fixture script builds representative old in-memory state, including missing newer item arrays and multi-fold disabled/collapsed modules, and verifies the WebView state shape remains stable.
