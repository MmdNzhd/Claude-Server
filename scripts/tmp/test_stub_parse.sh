#!/usr/bin/env bash
_emit_git_hide_warn() { echo EMIT_OK "$1"; }
_win_hide_broken() {
    local ps_out="GIT_HIDE:skip"
    # INTENTIONALLY missing opening quote (current bug)
    local stub_ps='; if ($hasGit) { echo x }'
    declare -F _emit_git_hide_warn || echo LOST_AFTER_DEF
    _emit_git_hide_warn "$ps_out"
}
echo "=== after parse declare ==="
declare -F _emit_git_hide_warn || echo MISSING_AT_TOP
_win_hide_broken
