#!/usr/bin/env bash
# Preview script for fzf session switcher.
# Shows all panes in the active window of the given session, stacked vertically.
#
# Usage: preview_session.sh <session_name> <min_lines>

session="$1"
min_lines="${2:-10}"

pane_ids=$(tmux list-panes -t "${session}" -F '#{pane_id}')
pane_count=$(echo "${pane_ids}" | wc -l | tr -d ' ')

lines_per_pane=$(( ${FZF_PREVIEW_LINES:-30} / pane_count ))
[ "${lines_per_pane}" -lt "${min_lines}" ] && lines_per_pane="${min_lines}"

first=1
for pid in ${pane_ids}; do
    if [ "${first}" -eq 0 ]; then
        cols="${FZF_PREVIEW_COLUMNS:-80}"
        printf '\n\033[38;5;240m'
        printf '%.0s═' $(seq 1 "${cols}")
        printf '\033[0m\n\n'
    fi
    first=0
    tmux capture-pane -ep -S "-${lines_per_pane}" -t "${pid}" |
        awk '{a[NR]=$0} END{for(i=NR;i>0;i--) if(a[i]~/[^ \t]/){for(j=1;j<=i;j++) print a[j]; exit}}' |
        tail -n "${lines_per_pane}"
done
