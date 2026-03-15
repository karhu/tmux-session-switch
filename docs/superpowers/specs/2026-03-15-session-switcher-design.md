# Session Switcher Design

Convert the fzf-pane-switch tmux plugin from listing/switching panes to listing/switching sessions.

## Overview

The plugin currently lists all tmux panes across all sessions in an fzf popup, with a preview of each pane's content. The change replaces pane-level navigation with session-level navigation while preserving the fzf-based workflow and preview functionality.

## Data Source

Replace `tmux list-panes -aF "format"` with `tmux list-sessions -F "format"` to get the list of sessions. Pane metadata (window names, pane titles, current commands) is gathered separately per session for searchability.

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

Format of each fzf input line:
```
<session_name>  <display_string>  <window_names> <pane_titles> <pane_commands>
```

Column 1 is the session ID for switching. Column 2 is displayed. Columns 3+ are hidden but searchable.

## Preview

When a session is highlighted, the preview captures **all panes in the active window** of that session, stacked vertically with dividers between them.

### Implementation
1. Use `tmux list-panes -t <session> -F "#{pane_id}"` filtered to the active window to get pane IDs.
2. For each pane, run `tmux capture-pane -ep -t <pane_id>`.
3. Stack the outputs vertically with a visual divider (e.g., a line of dashes).

### Vertical Space Management
- Divide the available preview lines (`$FZF_PREVIEW_LINES`) equally among panes.
- Enforce a configurable minimum number of lines per pane (default: 10).
- If `pane_count * min_lines > preview_lines`, each pane gets `min_lines` and the output overflows beyond the visible preview area.
- Example: 60 preview lines, min 10, 4 panes = 15 lines each. 8 panes = 10 lines each (overflows).

## Selection Behavior

When a session is selected: `tmux switch-client -t <session_name>`. This switches to whatever window/pane was last active in that session.

If no selection is made (user presses escape or no match): switch back to the current session (no-op).

## Fallback: No Match

If the search query doesn't match any session, prompt to create a **new session** with the query as the session name. Use `tmux new-session -d -s <name>` followed by `tmux switch-client -t <name>`.

## File Renames

| Before | After |
|--------|-------|
| `select_pane.sh` | `select_session.sh` |
| `select_pane.tmux` | `select_session.tmux` |

## Configuration Options

All `@fzf_pane_switch_*` options renamed to `@fzf_session_switch_*`. The `list-panes-format` option is removed (format is now internally managed).

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
