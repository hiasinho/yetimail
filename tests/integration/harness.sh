#!/usr/bin/env bash
# Shared isolation and process lifecycle for offline QML integration tests.

integration_cleanup() {
    local pid
    if [[ -n ${YETIMAIL_CHILD_PIDS:-} && -f ${YETIMAIL_CHILD_PIDS} ]]; then
        while read -r pid; do
            [[ $pid =~ ^[0-9]+$ ]] || continue
            kill "$pid" 2>/dev/null || true
        done < "$YETIMAIL_CHILD_PIDS"
        while read -r pid; do
            [[ $pid =~ ^[0-9]+$ ]] || continue
            wait "$pid" 2>/dev/null || true
        done < "$YETIMAIL_CHILD_PIDS"
    fi
    [[ -z ${work:-} ]] || rm -rf "$work"
}

integration_init() {
    integration_name=$1
    root=${root:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
    quickshell=${quickshell:-$(command -v quickshell || true)}
    if [[ -z $quickshell ]]; then
        printf '%s: quickshell is required\n' "$integration_name" >&2
        return 1
    fi

    work=$(mktemp -d)
    mkdir -p "$work/bin" "$work/home" "$work/xdg/config" "$work/xdg/cache" \
        "$work/xdg/data" "$work/xdg/state" "$work/xdg/runtime"
    chmod 700 "$work" "$work/home" "$work/xdg" "$work/xdg/"*
    export HOME="$work/home"
    export XDG_CONFIG_HOME="$work/xdg/config"
    export XDG_CACHE_HOME="$work/xdg/cache"
    export XDG_DATA_HOME="$work/xdg/data"
    export XDG_STATE_HOME="$work/xdg/state"
    export XDG_RUNTIME_DIR="$work/xdg/runtime"
    export YETIMAIL_TEST_BIN="$work/bin"
    export YETIMAIL_CHILD_PIDS="$work/child-pids"
    export YETIMAIL_HIMALAYA_GUARD="$work/himalaya-guard"
    : > "$YETIMAIL_CHILD_PIDS"
    : > "$YETIMAIL_HIMALAYA_GUARD"
    cp "$root/tests/integration/himalaya-guard" "$work/bin/himalaya"
    chmod +x "$work/bin/himalaya"
    trap integration_cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Exercise the exact fail-closed executable installed in the guarded PATH.
    local guard_status=0
    PATH="$work/bin" himalaya >/dev/null 2>&1 || guard_status=$?
    if [[ $guard_status != 99 ]] || ! grep -qx 'FORBIDDEN Himalaya invocation' "$YETIMAIL_HIMALAYA_GUARD"; then
        printf '%s: offline Himalaya guard regression failed\n' "$integration_name" >&2
        return 1
    fi
    : > "$YETIMAIL_HIMALAYA_GUARD"
}

integration_run_qml() {
    local scenario=$1 timeout_seconds=$2 config_root=${3:-$work}
    local output="$work/$scenario.output"
    local result=0
    if QT_QPA_PLATFORM=offscreen PATH="$work/bin" \
        /usr/bin/timeout --kill-after=2 "$timeout_seconds" \
        "$quickshell" -p "$config_root" --no-color > "$output" 2>&1; then
        result=0
    else
        result=$?
        printf '%s_FAIL %s: shell failed or exceeded %ss hard timeout (status %s)\n' \
            "${integration_name^^}" "$scenario" "$timeout_seconds" "$result" >&2
    fi
    cat "$output"
    return "$result"
}

integration_assert_output() {
    local scenario=$1 success=$2 rejected=$3
    local output="$work/$scenario.output"
    if ! grep -q "$success" "$output" || grep -Eq "$rejected" "$output"; then
        printf '%s_FAIL %s: missing success marker or rejected output detected\n' \
            "${integration_name^^}" "$scenario" >&2
        return 1
    fi
}

integration_assert_no_himalaya() {
    if [[ -s $YETIMAIL_HIMALAYA_GUARD ]]; then
        printf '%s_FAIL: offline scenario attempted to invoke Himalaya\n' "${integration_name^^}" >&2
        cat "$YETIMAIL_HIMALAYA_GUARD" >&2
        return 1
    fi
}
