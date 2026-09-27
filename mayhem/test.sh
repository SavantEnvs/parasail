#!/usr/bin/env bash
#
# mayhem/test.sh — RUN parasail's upstream test suite (built by mayhem/build.sh in build-tests/).
# The upstream suite is exactly the 3 CTest/Automake tests: test_isa, test_basic, test_verify
# (see CMakeLists.txt ADD_TEST / Makefile.am TESTS). We run the SAME binaries with the SAME
# invocations upstream uses, and ASSERT ON THEIR OUTPUT — not just exit status — because
# test_verify and test_isa always return 0 and only signal correctness through stdout. A sabotage
# patch that neuters a binary to exit(0) therefore prints nothing and FAILS here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

BT="$SRC/build-tests"
DATA="$SRC/data/test_small_2.fasta"

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

passed=0; failed=0

# --- test_isa : diagnostic ISA table (always exits 0; assert the table printed) ---
out="$("$BT/test_isa" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'ISA' && printf '%s' "$out" | grep -q 'SSE2'; then
  echo "PASS test_isa"; passed=$((passed+1))
else
  echo "FAIL test_isa (rc=$rc)"; printf '%s\n' "$out" | tail -5; failed=$((failed+1))
fi

# --- test_basic : known-answer parasail_sw checks; prints 'pass' per sub-test, EXIT_FAILURE on any fail ---
out="$("$BT/test_basic" 2>&1)"; rc=$?
npass="$(printf '%s\n' "$out" | grep -c '^pass$')"
if [ "$rc" -eq 0 ] && [ "$npass" -ge 4 ] && ! printf '%s\n' "$out" | grep -q '^failed$'; then
  echo "PASS test_basic ($npass sub-checks)"; passed=$((passed+1))
else
  echo "FAIL test_basic (rc=$rc, pass-lines=$npass)"; printf '%s\n' "$out" | tail -10; failed=$((failed+1))
fi

# --- test_verify : cross-checks every vectorized impl vs the serial reference over all seq pairs.
#     Mismatches print 'wrong ...'/'invalid ...' lines (exit code stays 0), so assert on OUTPUT. ---
out="$("$BT/test_verify" -f "$DATA" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s\n' "$out" | grep -q 'choose 2 is' \
   && [ "$(printf '%s\n' "$out" | grep -c 'checking .* functions')" -gt 0 ] \
   && ! printf '%s\n' "$out" | grep -qE 'wrong (score|flag|end_query|end_ref|matches|similar|length)|invalid (reference|result) flag'; then
  echo "PASS test_verify ($(printf '%s\n' "$out" | grep -c 'checking .* functions') function groups verified)"
  passed=$((passed+1))
else
  echo "FAIL test_verify (rc=$rc)"; printf '%s\n' "$out" | grep -E 'wrong |invalid ' | head -10; failed=$((failed+1))
fi

emit_ctrf "parasail-ctest" "$passed" "$failed" 0
