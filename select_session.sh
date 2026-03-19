#!/usr/bin/env bash
# This script uses fzf to display a list of sessions and allows you to select one.
#
# If you press ENTER, it switches to the selected session.
# If you press ENTER on an empty line, it creates a new session.

function build_session_lines() {
    local exclude_session="${1}"
    local sort_order="${2:-created}"
    local -a names=() brackets=() metadata_list=()
    local max_name_len=0

    # Get session list with last-attached timestamp for sorting
    local session_list
    session_list=$(tmux list-sessions -F '#{session_name}	#{session_windows}	#{session_last_attached}')

    # Sort based on configured order
    case "${sort_order}" in
        mru)
            session_list=$(echo "${session_list}" | sort -t$'\t' -k3 -nr)
            ;;
        alphabetical)
            session_list=$(echo "${session_list}" | sort -t$'\t' -k1,1)
            ;;
        # 'created' — use tmux's default order
    esac

    # First pass: collect session data
    while IFS=$'\t' read -r session_name window_count _; do
        if [[ -n "${exclude_session}" && "${session_name}" = "${exclude_session}" ]]; then
            continue
        fi
        local pane_count=0
        local metadata=""

        while IFS= read -r pane_line; do
            pane_count=$((pane_count + 1))
            metadata+="${pane_line} "
        done < <(tmux list-panes -t "${session_name}" -s -F '#{window_name} #{pane_title} #{pane_current_command}')

        local bracket=""
        if [[ ${window_count} -eq 1 && ${pane_count} -gt 1 ]]; then
            bracket="[${pane_count} panes]"
        elif [[ ${window_count} -gt 1 && ${pane_count} -le ${window_count} ]]; then
            bracket="[${window_count} windows]"
        elif [[ ${window_count} -gt 1 && ${pane_count} -gt ${window_count} ]]; then
            bracket="[${window_count} windows, ${pane_count} panes]"
        fi

        names+=("${session_name}")
        brackets+=("${bracket}")
        metadata_list+=("${metadata}")

        if [[ ${#session_name} -gt ${max_name_len} ]]; then
            max_name_len=${#session_name}
        fi
    done <<< "${session_list}"

    # Second pass: output with column-aligned brackets
    for i in "${!names[@]}"; do
        local display
        if [[ -n "${brackets[$i]}" ]]; then
            local padding=$(( max_name_len - ${#names[$i]} + 2 ))
            display="${names[$i]}$(printf '%*s' "${padding}" '')${brackets[$i]}"
        else
            display="${names[$i]}"
        fi
        printf '%s\t%s\t%s\n' "${names[$i]}" "${display}" "${metadata_list[$i]}"
    done
}

function select_session() {
    local border_styling="" fzf_version fzf_version_comparison
    local current_session fzf_output query selection session_id preview

    # Save the currently active session name
    current_session=$(tmux display-message -p '#{session_name}')

    # Setup border styling
    # Specific fzf releases have added additional styling options.
    fzf_version=$(fzf --version | awk '{print $1}')
    # - 0.58.0 or later, we can enable border styling
    vercomp '0.58.0' "${fzf_version}"
    fzf_version_comparison=$?
    if [[ ${fzf_version_comparison} -ne 1 ]]; then
        border_styling+=" --input-border --input-label=' Search ' --info=inline-right"
        border_styling+=" --list-border --list-label=' Sessions '"
        border_styling+=" --preview-border --preview-label=' Preview '"
    fi
    # - 0.61.0 or later, we can enable ghost text
    vercomp '0.61.0' "${fzf_version}"
    fzf_version_comparison=$?
    if [[ ${fzf_version_comparison} -ne 1 ]]; then
        border_styling+=" --ghost 'type to search...'"
    fi
    # Fallback to old border styling used in tmux-fzf-pane-switch release v1.1.2 if $border_styling is not set
    if [[ -z "${border_styling}" ]]; then
        border_styling="--preview-label='Preview'"
    fi

    # Check if we're using the fzf preview
    if [[ "${1}" = 'true' ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        preview="--preview '${script_dir}/preview_session.sh {1} ${4}' --preview-window=${3}"
    fi

    # Build session list, optionally excluding current session
    local exclude=""
    if [[ "${5}" = 'true' ]]; then
        exclude="${current_session}"
    fi

    # Launch switcher
    fzf_output=$(build_session_lines "${exclude}" "${6}" |
        eval fzf --exit-0 --print-query --reverse --tmux "${2}" \
          --delimiter='\\t' --with-nth=2 "${border_styling}" "${preview}")

    # --print-query makes fzf output: line 1 = query, line 2 = selected item
    query=$(echo "${fzf_output}" | head -1)
    selection=$(echo "${fzf_output}" | tail -n +2 | head -1)

    # Set session_id to first tab-delimited field of fzf output
    session_id=$(echo "${selection}" | awk -F'\t' '{print $1}')

    if [[ -n "${session_id}" ]]; then
        # User selected a session — switch to it
        tmux switch-client -t "${session_id}"
    elif [[ -n "${query}" ]]; then
        # No selection but user typed a query — offer to create new session
        tmux new-session -d -s "${query}" 2>/dev/null && \
            tmux switch-client -t "${query}"
    else
        # User pressed escape with no query — stay on current session
        tmux switch-client -t "${current_session}"
    fi
}

function vercomp() {
  local v1="$1"
  local v2="$2"

  # Split each version string into arrays using '.' as the delimiter
  IFS='.' read -r -a ver1 <<< "$v1"
  IFS='.' read -r -a ver2 <<< "$v2"

  # Compare major, minor, and patch components one by one
  for i in 0 1 2; do
    # Default to 0 if a component is missing (e.g., "1.2" becomes "1.2.0")
    local num1="${ver1[i]:-0}"
    local num2="${ver2[i]:-0}"

    # Compare the numeric values of the current component
    if (( num1 > num2 )); then
      return 1  # First version is newer
    elif (( num1 < num2 )); then
      return 2  # First version is older
    fi
  done

  return 0  # Versions are equal
}

# Check for required commands
command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }
command -v fzf >/dev/null 2>&1 || { echo "fzf not found"; exit 1; }

# Preview
preview="${1}"
# FZF window position
fzf_window_position="${2}"
# FZF preview window position
fzf_preview_position="${3}"
# Minimum preview lines per pane
min_preview_lines="${4}"
# Hide current session from list
hide_current_session="${5}"
# Sort order: created, mru, alphabetical
sort_order="${6}"

select_session "${preview}" "${fzf_window_position}" "${fzf_preview_position}" "${min_preview_lines}" "${hide_current_session}" "${sort_order}"
