#!/usr/bin/env bash
# Tests for kde/css2ini.awk. Run from the repository root or from anywhere;
# paths are resolved relative to this script.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_SCRIPT="${HERE}/../css2ini.awk"
failures=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        echo "ok   - ${name}"
    else
        echo "FAIL - ${name}"
        diff <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") || true
        failures=$((failures + 1))
    fi
}

# 1. A well-formed document converts exactly.
got="$(awk -f "${AWK_SCRIPT}" < "${HERE}/css2ini/input.css")"
want="$(cat "${HERE}/css2ini/expected.ini")"
check "converts sections, keys and comma spacing" "${want}" "${got}"

# 2. An unmapped selector is a hard error, not a malformed section header.
if awk -f "${AWK_SCRIPT}" < "${HERE}/css2ini/unmapped.css" >/dev/null 2>&1; then
    echo "FAIL - unmapped selector should exit non-zero"
    failures=$((failures + 1))
else
    echo "ok   - unmapped selector rejected"
fi

# 3. No spaces survive inside any value.
if awk -f "${AWK_SCRIPT}" < "${HERE}/css2ini/input.css" | grep -qE '=[0-9]+, '; then
    echo "FAIL - comma spacing not stripped"
    failures=$((failures + 1))
else
    echo "ok   - comma spacing stripped"
fi

if [[ ${failures} -gt 0 ]]; then
    echo "${failures} test(s) failed"
    exit 1
fi
echo "all css2ini tests passed"
