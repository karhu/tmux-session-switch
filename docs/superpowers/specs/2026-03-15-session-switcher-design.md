# Session Switcher Design

Convert the fzf-pane-switch tmux plugin from listing/switching panes to listing/switching sessions.

## Overview

The plugin currently lists all tmux panes across all sessions in an fzf popup, with a preview of each pane's content. The change replaces pane-level navigation with session-level navigation while preserving the fzf-based workflow and preview functionality.

## Data Source

Replace `tmux list-panes -aF "format"` with a script that builds session lines. For each session, gather:
- Session-level info via `tmux list-sessions -F "#{session_name} #{session_windows}"`.
- Pane-level metadata via `tmux list-panes -t <session> -F "#{window_name} #{pane_title} #{pane_current_command}"` to collect searchable metadata and total pane count.

This requires iterating over sessions, but the number of sessions is typically small (single digits), so performance is not a concern.

## Display Format

Each session row in fzf follows conditional formatting rules:

| Windows | Panes | Display |
|---------|-------|---------|
| 1 | 1 | `my-project` |
| 1 | 3 | `my-project [3 panes]` |
| 3 | 3 | `my-project [3 windows]` |
| 3 | 5 | `my-project [3 windows, 5 panes]` |

Rules:
- If 1 window and 1 pane: show only session name, no brackets.
- If 1 window and multiple panes: show `[N panes]`.
- If multiple windows and panes == windows (one pane per window): show `[N windows]`.
- If multiple windows and panes > windows: show `[N windows, M panes]`.

## Searchable Hidden Columns

Each fzf line includes hidden columns containing aggregated pane metadata from the session:
- Window names
- Pane titles
- Current commands

These are not displayed (`--with-nth` controls visible columns) but are searchable, so typing "vim" surfaces sessions containing a vim pane.

Format of each fzf input line (tab-delimited, fzf `--delimiter='\t'`):
```
<session_name>\t<display_string>\t<window_names> <pane_titles> <pane_commands>
```

- Column 1: session name (used for switching via `tmux switch-client -t`).
- Column 2: display string (shown to user via `--with-nth=2`).
- Column 3: space-separated aggregated pane metadata (hidden but searchable).

Tab delimiter ensures reliable column separation since session names, display strings, and metadata all contain spaces.

## Preview

When a session is highlighted, the preview captures **all panes in the active window** of that session, stacked vertically with dividers between them.

### Implementation
1. Use `tmux list-panes -t <session> -F "#{pane_id}"` to get pane IDs. This defaults to the active window of the session.
2. For each pane, run `tmux capture-pane -ep -t <pane_id>` capturing the last N lines (where N = lines_per_pane).
3. Stack the outputs vertically with a divider line of `─` characters spanning the preview width.

### Vertical Space Management
- Divide the available preview lines (`$FZF_PREVIEW_LINES`) equally among panes.
- Enforce a configurable minimum number of lines per pane (default: 10).
- If `pane_count * min_lines > preview_lines`, each pane gets `min_lines` and the output overflows beyond the visible preview area.
- Example: 60 preview lines, min 10, 4 panes = 15 lines each. 8 panes = 10 lines each (overflows).

## Selection Behavior

When a session is selected: `tmux switch-client -t <session_name>`. This switches to whatever window/pane was last active in that session.

If no selection is made (user presses escape or no match): switch back to the current session (no-op).

## New Session Creation (No Match)

When fzf exits with no selection (via `--exit-0` and `--print-query`), the script checks if the search query is non-empty. If so, it uses `tmux command-prompt` pre-filled with the query to confirm session creation. On confirmation, it runs `tmux new-session -d -s <name> && tmux switch-client -t <name>`.

This mirrors the existing UX pattern from the pane switcher (which uses `tmux command-prompt` for new window creation) — the user gets a chance to confirm or edit the name before creation.

The current session is included in the list (not excluded) since the user may want to preview it or use it as a reference.

## File Renames

| Before | After |
|--------|-------|
| `select_pane.sh` | `select_session.sh` |
| `select_pane.tmux` | `select_session.tmux` |

## Configuration Options

All options use a new `@fzf_session_switch_*` prefix. The old `list-panes-format` option is removed (format is now internally managed). The old `-pane` suffix on preview options is dropped as a deliberate simplification (e.g., `preview-pane` → `preview`, `preview-pane-position` → `preview-position`).

| Option | Default | Purpose |
|--------|---------|---------|
| `@fzf_session_switch_bind-key` | `s` | Keybinding (prefix + key) |
| `@fzf_session_switch_preview` | `true` | Show preview pane |
| `@fzf_session_switch_window-position` | `center,70%,80%` | fzf popup position/size |
| `@fzf_session_switch_preview-position` | `right,,,nowrap` | Preview pane position |
| `@fzf_session_switch_min-preview-lines` | `10` | Minimum lines per pane in preview |

## FZF Border Labels

- List label: "Sessions" (was "Panes")
- Search label: "Search" (unchanged)
- Preview label: "Preview" (unchanged)

## Approach

Minimal adaptation of the existing codebase. Same script structure, same fzf invocation pattern, same version detection logic. Changes are scoped to: data source, display formatting, preview logic, naming, and config options.
