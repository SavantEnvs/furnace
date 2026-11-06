#!/usr/bin/env bash
# Oracle: `furnace -info <demo>` (the normal-flags Release CLI built by mayhem/build.sh) must print
# exactly the committed golden song summary (title/system/instrument/sample/subsong listing) for
# each demo module, which proves the module parser decodes the right data.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/release/furnace"
[ -x "$BIN" ] || { echo "missing $BIN: mayhem/build.sh did not build it" >&2; emit_ctrf furnace-info 0 1; exit 1; }

HOME_DIR=$(mktemp -d)
trap 'rm -rf "$HOME_DIR"' EXIT
export HOME="$HOME_DIR"

passed=0
failed=0
for demo in a2600/Slam_the_Door nes/Famitune1 pce/pcengineasdmo amiga/Ibiza multichip/one ay8910/no_timers genesis/darkstar quickstart; do
  golden="mayhem/golden/$(echo "$demo" | tr / _).txt"
  actual=$("$BIN" -info "demos/$demo.fur" 2>/dev/null | sed -n '/^SONG INFORMATION/,$p')
  if [ -n "$actual" ] && [ "$actual" == "$(cat "$golden")" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: furnace -info demos/$demo.fur differs from $golden" >&2
    diff <(printf '%s\n' "$actual") "$golden" >&2 || true
  fi
done

emit_ctrf furnace-info "$passed" "$failed"
