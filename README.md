# Clawd Buddy

A tiny pixel companion for Claude Code on Windows. It sits in the bottom-right corner of your screen and tells you what your sessions are doing while you work on something else.

![All scenes](preview.png)

| State | When | What it does |
|---|---|---|
| Idle | No session needs you | Reads a book, blinks and turns pages. Every 20-45 s it does something at random: drinks mate, listens to music, plays with a yo-yo, stretches or looks around. After 10 idle minutes it falls asleep |
| Working | You sent a prompt | Types on a laptop. Every 6-15 s it has an idea (light bulb), grumbles, scratches its head, sweats, types at full speed or looks up thinking |
| Done | Claude finished its turn | Jumps with confetti, shows a green bubble with the first line of the answer, chimes |
| Needs you | Permission or input required | Waves under a blinking "!", shows an amber bubble, chimes |
| Error | The turn failed (rate limit, API error...) | Shakes with X eyes and smoke, red bubble, alert sound |

- **Left click**: dismiss the bubble and jump to the terminal window of that session.
- **Drag**: move it. It keeps its bottom-right corner when the bubble appears.
- **Right click**: mute sounds or quit.
- **Hover**: list of active sessions and their state.

With several sessions open, the avatar shows the most urgent one: error, then needs you, then done, then working. The bubble names the project, and the hover list shows every session. Clicking brings the terminal window forward; picking the exact Windows Terminal tab is not possible from outside, so the project name tells you which tab it is.

## Language

Bubbles and menus follow the Windows display language (English and Spanish included). To force one, set `CLAWD_BUDDY_LANG` (for example `es` or `en`) and restart the avatar. Translations live in `lib/strings.json`; add a language by copying the `en` block. Texts sent by Claude Code itself, such as notification messages, are shown as received.

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 (built in). No Node, Python or Electron.
- Claude Code with hook support (`PermissionRequest`, `StopFailure`, async hooks).

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

1. Backs up `~/.claude/settings.json` to `settings.json.clawd-buddy-<timestamp>.bak`.
2. Adds async hooks tagged `clawd-buddy` for `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, `StopFailure`, `PermissionRequest` and `Notification`. Your other hooks are left untouched, and running it again does not duplicate entries.
3. Starts the avatar.

Hooks load when a session starts, so open a new Claude Code session afterwards. The avatar also starts automatically with each new session.

Keep the repository where it is: the hooks point to `hook.ps1` by absolute path. If you move it, run `install.ps1` again.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes only the `clawd-buddy` hooks and stops the avatar.

## How it works

- `hook.ps1` receives each hook event on stdin and writes one small JSON file per session to `%LOCALAPPDATA%\clawd-buddy\sessions`. It never prints anything and always exits 0, so it cannot break Claude Code. Errors go to `%LOCALAPPDATA%\clawd-buddy\hook.log`.
- `avatar.ps1` is a transparent WPF window that polls those files and animates the sprite.
- `PermissionRequest` signals "needs you" immediately; `Notification` is only a fallback because it arrives late and repeats idle reminders.
- No hook fires when you grant a permission, so the avatar treats new transcript output as "working again".
- A closed terminal sends no `SessionEnd`, so a working session with no activity for 15 minutes goes back to idle.
- `PreToolUse`/`PostToolUse` are deliberately not used: they would start a PowerShell process on every tool call.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

To regenerate the scene sheet after editing sprites:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\tools\preview.ps1
```

## Notes

- Script files are ASCII-only on purpose: Windows PowerShell 5.1 misreads UTF-8 files without a BOM. Translated text lives in `lib/strings.json`, which is read explicitly as UTF-8.
- The pixel character is an original design in Claude's colors, inspired by the cozy lo-fi pixel style of Claude FM.
