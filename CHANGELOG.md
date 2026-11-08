# Changelog

## v0.2.2

### Fixed

- Animation stutter after each refresh as quota history grew: the tray icon, popup and widget no longer freeze while the usage history is saved, even with a full 8 days of history.

### Changed

- Lower memory and CPU use per refresh: the usage history stays in memory and is written to disk at most every 5 minutes (and when the app exits), the background quota reader is reused between refreshes, and memory is released after a refresh or when the popup or a notification closes.
- History is stored more compactly: one sample per minute for the last 2 hours and one per 10 minutes before that (still 8 days). Existing history files are read and converted automatically.

## v0.2.1

### Added

- Update check from the tray menu: **Check for updates** asks GitHub Releases for the latest version in the background and reports the result in a notification. When a newer version is known, the item becomes **Update to vX**.
- Optional automatic update check: shortly after the app starts and then at most once a day, with one notification per new version. Clicking the notification starts the update.
- A small version badge in the popup header when a newer version is available; click it to update.
- `agentview update --check` to check for a newer version from the terminal.
- A setting to turn off automatic update checks. Agent-view never updates without asking: updates run only when you click the menu item, notification, or badge, or run `agentview update`.

### Changed

- Notifications now use an agent-view styled toast (the same dark Bezel look as the popup and widget) in the bottom-right corner instead of a tray balloon labelled "Windows PowerShell". It never takes focus, hides after 8 seconds (hover to keep it), opens the popup when clicked, and combines several alerts into one toast. During full-screen apps, presentations, or quiet hours, the app falls back to a standard Windows notification so it lands in Notification Center.
- "Full again" notifications no longer repeat the provider name: the title is "Claude Code: full again" and the text is the window, for example "5-hour limit · 100% left".

## v0.2.0

### Added

- English and Vietnamese UI for the app, popup, widget, tray menu, terminal command, and installer. The language follows Windows by default; `agentview lang auto|vi|en` changes it.
- Low-quota notifications: a tray notification when a 5-hour or weekly window drops to 30% and 10% left (once per threshold per window cycle), and when a window that ran low is full again. Several alerts at once are combined into one notification.
- Run-out forecast: the popup shows when each window is expected to run out at the current pace, or that it is enough until reset; the widget adds the run-out time for the tightest window. Forecasts use a small local history of usage percentages (kept for 8 days).
- Settings window (gear button in the popup, or **Settings…** in the tray menu): language, refresh interval (1, 2, or 5 minutes), notifications and thresholds, widget, start at sign-in, and hiding providers.

## v0.1.1

### Fixed

- One-line install via `irm | iex` failed with `param: The term 'param' is not recognized` because `install.ps1` started with a UTF-8 BOM. `install.ps1` is now a plain-ASCII bootstrap that downloads the real installer (`installer.ps1`) and runs it in Windows PowerShell, from both Windows PowerShell 5.1 and PowerShell 7. `agentview update` runs `installer.ps1` directly.

## v0.1.0

### Added

- Windows tray quota display for Claude Code and Codex, with a Bezel ring icon showing the lowest remaining percentage and green, amber, or red levels.
- Tray menu to refresh, toggle the floating widget, toggle start at sign-in, and quit.
- Dark detail popup with each provider's 5-hour and weekly windows, reset times, and errors.
- Optional floating widget that docks to the left, right, or top screen edge, with saved edge, position, and visibility settings.
- Support for providers that expose only one quota window; missing windows are hidden.
- Claude Code quota from the local usage cache; when it is older than 5 minutes, the CLI's `/usage` command (no model turn, at most once every 5 minutes) refreshes it. Windows past their reset time show as full, and cached data is used for up to 7 days.
- One-line installer with interactive prompts, a step-by-step report, and a first-run notification with the current quota.
- Installer options as switches or `AGENT_VIEW_*` environment variables; reinstalling keeps existing choices, and a failed install restores the previous files.
- `agentview` terminal command: `up`, `down`, `restart`, `status [--json]`, `widget`, `autostart`, `update`, `uninstall`, `version`, and `help`, with suggestions for mistyped commands.
- Uninstall script that removes the app, Startup shortcut, settings, and user PATH entry.
