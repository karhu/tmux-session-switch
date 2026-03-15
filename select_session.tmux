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
