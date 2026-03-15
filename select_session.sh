#!/usr/bin/env bash
# This script uses fzf to display a list of sessions and allows you to select one.
#
# If you press ENTER, it switches to the selected session.
# If you press ENTER on an empty line, it creates a new session.

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

function select_session() {
    local border_styling="" fzf_version_comparison
    local current_session preview

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
    if [[ -z ${border_styling+x} ]]; then
        border_styling="--preview-label='Preview'"
    fi

    # Check if we're using the fzf preview pane
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

    # Launch switcher
    fzf_output=$(build_session_lines |
        eval fzf --exit-0 --print-query --reverse --tmux "${2}" \
          --delimiter='\t' --with-nth=2 "${border_styling}" "${preview}")

    # --print-query makes fzf output: line 1 = query, line 2 = selected item
    query=$(echo "${fzf_output}" | head -1)
    selection=$(echo "${fzf_output}" | tail -n +2 | head -1)

    # Set session_id to first tab-delimited field of fzf output
    session_id=$(echo "${selection}" | awk -F'\t' '{print $1}')

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

select_session "${preview}" "${fzf_window_position}" "${fzf_preview_position}" "${min_preview_lines}"
