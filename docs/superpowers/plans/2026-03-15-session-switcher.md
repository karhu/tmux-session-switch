# Session Switcher Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the fzf-pane-switch tmux plugin to list and switch tmux sessions instead of panes.

**Architecture:** Minimal adaptation of two existing bash scripts. Replace the data source (`list-panes` → session iteration), rewrite the display formatting with conditional bracket logic, replace the single-pane preview with a multi-pane stacked preview, and rename files/config options.

**Tech Stack:** Bash, tmux, fzf

**Spec:** `docs/superpowers/specs/2026-03-15-session-switcher-design.md`

---

## Chunk 1: File Renames and Config Loader

### Task 1: Rename files and update plugin loader

**Files:**
- Rename: `select_pane.sh` → `select_session.sh`
- Rename: `select_pane.tmux` → `select_session.tmux`

- [ ] **Step 1: Rename the files and the function**

```bash
git mv select_pane.sh select_session.sh
git mv select_pane.tmux select_session.tmux
```

Then in `select_session.sh`, rename the function and its call:
- `function select_pane()` → `function select_session()`
- The call at the bottom: `select_pane` → `select_session`

This is done early so all subsequent chunks can reference `select_session` consistently.

- [ ] **Step 2: Rewrite `select_session.tmux` with new config options**

Replace the entire content of `select_session.tmux` with:

```bash
#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
default_bind_key='s'
default_preview='true'
default_fzf_window_position='center,70%,80%'
default_fzf_preview_position='right,,,nowrap'
default_min_preview_lines='10'

# User overridable options
tmux_bind_key="@fzf_session_switch_bind-key"
tmux_preview="@fzf_session_switch_preview"
tmux_fzf_window_position="@fzf_session_switch_window-position"
tmux_fzf_preview_position="@fzf_session_switch_preview-position"
tmux_min_preview_lines="@fzf_session_switch_min-preview-lines"

get_tmux_option() {
    local option="${1}"
    local default_value="${2}"
    local option_override
    option_override="$(tmux show-option -gqv "${option}")"
    if [ -z "${option_override}" ]; then
        echo "${default_value}"
    else
        echo "${option_override}"
    fi
}

set_switch_session_bindings() {
    local bind_key preview fzf_window_position fzf_preview_position min_preview_lines
    bind_key="$(get_tmux_option "${tmux_bind_key}" "${default_bind_key}")"
    preview="$(get_tmux_option "${tmux_preview}" "${default_preview}")"
    fzf_window_position="$(get_tmux_option "${tmux_fzf_window_position}" "${default_fzf_window_position}")"
    fzf_preview_position="$(get_tmux_option "${tmux_fzf_preview_position}" "${default_fzf_preview_position}")"
    min_preview_lines="$(get_tmux_option "${tmux_min_preview_lines}" "${default_min_preview_lines}")"

    tmux bind-key "${bind_key}" run-shell \
        "'${CURRENT_DIR}/select_session.sh' '${preview}' '${fzf_window_position}' '${fzf_preview_position}' '${min_preview_lines}'"
}

set_switch_session_bindings
```

Key changes from original:
- All `pane_switch` → `session_switch` in option names.
- Removed `list-panes-format` option (format is now internal).
- Added `min-preview-lines` option (5th argument).
- `preview-pane` → `preview`, `preview-pane-position` → `preview-position`.
- Bind calls `select_session.sh` with 4 arguments: `preview`, `window_position`, `preview_position`, `min_preview_lines`.

- [ ] **Step 3: Commit**

```bash
git add select_session.sh select_session.tmux
git commit -m "refactor: rename files and update config loader for session switching"
```

---

## Chunk 2: Session Data Source and Display Formatting

### Task 2: Build session lines with conditional display format

This replaces the old `tmux list-panes -aF` data source with a bash function that iterates sessions and builds tab-delimited fzf lines.

**Files:**
- Modify: `select_session.sh`

- [ ] **Step 1: Write the `build_session_lines` function**

Add this function to `select_session.sh` (above `select_session`). It outputs one tab-delimited line per session to stdout:

```bash
function build_session_lines() {
    while IFS=$'\t' read -r session_name window_count; do
        local pane_count=0
        local metadata=""

        # Gather pane metadata for this session
        while IFS= read -r pane_line; do
            pane_count=$((pane_count + 1))
            metadata+="${pane_line} "
        done < <(tmux list-panes -t "${session_name}" -s -F '#{window_name} #{pane_title} #{pane_current_command}')

        # Build display string with conditional brackets
        local display="${session_name}"
        if [[ ${window_count} -eq 1 && ${pane_count} -gt 1 ]]; then
            display+=" [${pane_count} panes]"
        elif [[ ${window_count} -gt 1 && ${pane_count} -le ${window_count} ]]; then
            display+=" [${window_count} windows]"
        elif [[ ${window_count} -gt 1 && ${pane_count} -gt ${window_count} ]]; then
            display+=" [${window_count} windows, ${pane_count} panes]"
        fi
        # 1 window, 1 pane: no brackets (display stays as session_name)

        # Output: session_name<TAB>display_string<TAB>metadata
        printf '%s\t%s\t%s\n' "${session_name}" "${display}" "${metadata}"
    done < <(tmux list-sessions -F '#{session_name}	#{session_windows}')
}
```

Note: `tmux list-panes -s -t <session>` lists all panes across all windows in a session. The `-s` flag means "all panes in session" rather than just the active window.

- [ ] **Step 2: Update the `select_session` function to use `build_session_lines`**

Replace the old fzf pipeline data source. The fzf invocation captures both the query and the selection:

```bash
fzf_output=$(build_session_lines |
    eval fzf --exit-0 --print-query --reverse --tmux "${2}" \
      --delimiter='\t' --with-nth=2 "${border_styling}" "${preview}")

# --print-query makes fzf output: line 1 = query, line 2 = selected item
query=$(echo "${fzf_output}" | head -1)
selection=$(echo "${fzf_output}" | tail -n +2 | head -1)
```

Key changes:
- `tmux list-panes -aF "${4}"` → `build_session_lines`.
- Added `--delimiter='\t'` to fzf for tab-based column separation.
- `--with-nth=2..` → `--with-nth=2` to show only the display column.
- Removed `| tail -1` pipe — capture full fzf output to split query from selection.
- Note: `--with-nth` controls display only; fzf searches all columns by default, so pane metadata in column 3 is searchable.

- [ ] **Step 3: Update session ID extraction**

Replace:
```bash
pane_id=$(echo "${pane}" | awk '{print $1}')
```

With:
```bash
session_id=$(echo "${selection}" | awk -F'\t' '{print $1}')
```

This uses tab as the field separator to extract the session name from column 1 of the selection (not the query).

- [ ] **Step 4: Verify manually**

Open tmux with multiple sessions. Source the plugin and press the keybinding. Confirm:
- Sessions are listed with correct bracket formatting.
- Searching for pane metadata (e.g., a command name) filters correctly.

- [ ] **Step 5: Commit**

```bash
git add select_session.sh
git commit -m "feat: build session lines with conditional display formatting"
```

---

## Chunk 3: Multi-Pane Preview

### Task 3: Implement stacked multi-pane preview

Replace the single-pane preview with a preview that captures all panes in the active window of the highlighted session, stacked vertically with dividers.

**Files:**
- Modify: `select_session.sh`

- [ ] **Step 1: Write the preview command**

The preview command is a bash snippet passed to fzf's `--preview` flag. It receives the session name via `{1}` (column 1 from the tab-delimited input). Replace the existing preview block:

```bash
if [[ "${1}" = 'true' ]]; then
    local min_lines="${4}"
    preview="--preview '"
    preview+='session={1}; '
    preview+='pane_ids=$(tmux list-panes -t "${session}" -F "#{pane_id}"); '
    preview+='pane_count=$(echo "${pane_ids}" | wc -l | tr -d " "); '
    preview+='lines_per_pane=$(( ${FZF_PREVIEW_LINES:-30} / pane_count )); '
    preview+="[ \${lines_per_pane} -lt ${min_lines} ] && lines_per_pane=${min_lines}; "
    preview+='first=1; '
    preview+='for pid in ${pane_ids}; do '
    preview+='  if [ ${first} -eq 0 ]; then '
    preview+='    printf "%.0s─" $(seq 1 ${FZF_PREVIEW_COLUMNS:-80}); echo; '
    preview+='  fi; '
    preview+='  first=0; '
    preview+='  tmux capture-pane -ep -S -${lines_per_pane} -t ${pid} | '
    preview+="  awk \"{a[NR]=\\\$0} END{for(i=NR;i>0;i--) if(a[i]~/[^ \\t]/){for(j=1;j<=i;j++) print a[j]; exit}}\" | "
    preview+='  tail -n ${lines_per_pane}; '
    preview+='done'
    preview+="' --preview-window=${3}"
fi
```

How this works:
1. Gets all pane IDs in the active window of the session (`list-panes -t` defaults to active window).
2. Calculates `lines_per_pane = preview_lines / pane_count`, floored to `min_lines`.
3. For each pane (except the first), prints a `─` divider line.
4. Captures the last `lines_per_pane` lines of each pane, trims trailing whitespace (same awk as original).

- [ ] **Step 2: Update fzf `--delimiter` in preview context**

Ensure the `--delimiter='\t'` flag is present in the fzf call so that `{1}` correctly resolves to the session name (column 1 of the tab-delimited line).

This was already done in Task 2 Step 2 — just verify it's in place.

- [ ] **Step 3: Verify manually**

Open tmux with a session that has split panes. Trigger the switcher and confirm:
- Preview shows all panes from the active window stacked vertically.
- A `─` divider separates each pane.
- Space is divided equally, with minimum lines enforced.

- [ ] **Step 4: Commit**

```bash
git add select_session.sh
git commit -m "feat: multi-pane stacked preview for session switcher"
```

---

## Chunk 4: Selection, Fallback, and Border Labels

### Task 4: Update selection behavior and new session creation

**Files:**
- Modify: `select_session.sh`

- [ ] **Step 1: Rewrite the selection/fallback block**

Replace the old pane-switching block (after fzf exits) with:

```bash
# session_id was extracted from `selection` in the earlier step
# query was extracted from fzf output line 1

if [[ -n "${session_id}" ]]; then
    # User selected a session — switch to it
    tmux switch-client -t "${session_id}"
elif [[ -n "${query}" ]]; then
    # No selection but user typed a query — offer to create new session
    tmux command-prompt -b -I "${query}" -p "Create new session:" \
        "new-session -d -s '%1' && switch-client -t '%1'"
else
    # User pressed escape with no query — stay on current session
    tmux switch-client -t "${current_session}"
fi
```

Key changes:
- Uses `query` (captured from fzf line 1) for new session creation, not `session_id`.
- `command-prompt -I` pre-fills the query so the user can confirm or edit.
- Three branches: selection made → switch; no selection + query → create; no selection + no query → no-op.

- [ ] **Step 2: Update current context saving**

At the top of the `select_session` function, change:

```bash
current_pane=$(tmux display-message -p '#{pane_id}')
```

To:

```bash
current_session=$(tmux display-message -p '#{session_name}')
```

- [ ] **Step 3: Update border labels**

In the border styling block, change:

```bash
border_styling+=" --list-border --list-label=' Panes '"
```

To:

```bash
border_styling+=" --list-border --list-label=' Sessions '"
```

- [ ] **Step 4: Update script header comment**

Change the comment at the top of `select_session.sh`:

```bash
# This script uses fzf to display a list of sessions and allows you to select one.
#
# If you press ENTER, it switches to the selected session.
# If you press ENTER on an empty line, it creates a new session.
```

- [ ] **Step 5: Clean up unused code**

Remove the old `list_panes_format` argument handling at the bottom of the script:

```bash
# Remove these lines:
read -r -a list_panes_format_overrides <<< "${4}"
list_panes_formatted_overrides=$(printf '#{%s} ' "${list_panes_format_overrides[@]}")
```

Replace the bottom of the script with:

```bash
# Pane preview
preview="${1}"
# FZF window position
fzf_window_position="${2}"
# FZF preview window position
fzf_preview_position="${3}"
# Minimum preview lines per pane
min_preview_lines="${4}"

select_session "${preview}" "${fzf_window_position}" "${fzf_preview_position}" "${min_preview_lines}"
```

- [ ] **Step 6: Verify manually**

Test the full flow:
1. Switch between sessions — confirm it lands on the last-active window/pane.
2. Press escape — confirm no switch happens.
3. Type a non-matching query and press enter — confirm the `command-prompt` appears pre-filled.
4. Confirm border label shows "Sessions".

- [ ] **Step 7: Commit**

```bash
git add select_session.sh
git commit -m "feat: session selection, new session creation, and updated labels"
```

---

## Chunk 5: Final Assembly and Verification

### Task 5: Full integration test

**Files:**
- Verify: `select_session.sh`, `select_session.tmux`

- [ ] **Step 1: Review the complete `select_session.sh` for consistency**

Read through the entire file and verify:
- No references to `pane_id` or `select_pane` remain.
- All variable names use session terminology.
- The `vercomp` function is unchanged.
- The argument handling at the bottom passes 4 args: `preview`, `window_position`, `preview_position`, `min_preview_lines`.

- [ ] **Step 2: Review the complete `select_session.tmux` for consistency**

Verify:
- All option names use `@fzf_session_switch_*` prefix.
- `bind-key` calls `select_session.sh` with 4 arguments.
- No references to old pane-related options.

- [ ] **Step 3: End-to-end manual test**

Set up test environment:
```bash
# Create test sessions
tmux new-session -d -s "project-alpha"
tmux new-session -d -s "project-beta"
tmux split-window -t "project-beta"
tmux new-window -t "project-beta"
tmux new-session -d -s "single"
```

Test cases:
1. Trigger switcher (prefix + s) — see 3 sessions listed.
2. `project-alpha` shows no brackets (1 window, 1 pane).
3. `project-beta` shows `[2 windows, 3 panes]`.
4. `single` shows no brackets.
5. Preview shows pane content; `project-beta` shows stacked panes with divider.
6. Select a session — switches correctly.
7. Search for a command running in `project-beta` — filters correctly.
8. Type nonexistent name, press enter — new session prompt appears.

- [ ] **Step 4: Commit any fixes**

```bash
git add select_session.sh select_session.tmux
git commit -m "fix: address issues found during integration testing"
```

(Skip this step if no fixes are needed.)
