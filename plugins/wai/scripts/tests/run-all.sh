#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

declare -A results
for test in test-server-info.sh test-heartbeat.sh test-parallel.sh test-security.sh; do
  echo "=== Running $test ==="
  if bash "$SCRIPT_DIR/$test"; then
    results[$test]="PASS"
  else
    results[$test]="FAIL"
  fi
  echo
done

echo "=== Summary ==="
fail=0
for test in "${!results[@]}"; do
  printf "  %-30s %s\n" "$test" "${results[$test]}"
  [[ "${results[$test]}" == "FAIL" ]] && fail=1
done

exit $fail
