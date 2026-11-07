# Changelog

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
