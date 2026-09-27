/*
 * mayhem/aligner_stdin_guard.c — neutralize parasail_aligner's stdin auto-detection.
 *
 * Mayhem runs the aligner as a FILE-INPUT target: `/mayhem/parasail_aligner -f @@ -g ...`.
 * The aligner auto-detects "piped input" with poll(POLLIN) on fd 0 (stdin_has_data() in
 * apps/parasail_aligner.cpp). Under Mayhem's coverage collection — and under any
 * non-interactive launcher, e.g. `docker run --read-only` without -i — the target's stdin is
 * /dev/null (or a closed fd), which polls READABLE (revents=POLLIN). That is a FALSE POSITIVE:
 * with -f already set, the aligner then treats stdin as the QUERY file (qname="stdin",
 * has_query=true), aligns the -f database against an empty query set, prints
 *   "no alignment work, either the filter removed all alignments or the input file(s) were empty"
 * and exit()s EXIT_FAILURE *before processing the -f input*. Mayhem therefore sees the target
 * fail INSTANTLY on every testcase: tests=0, has_critical_errors=true, no phase, 0 edges — a
 * "Run Failed" that is invisible to `docker build` and to fuzz-smoke (which only checks the
 * binary isn't 127). Reproduced exactly under `docker run --read-only`.
 *
 * Fix: close fd 0 before main() runs. poll() on a closed fd returns POLLNVAL (not POLLIN), so
 * stdin_has_data() returns false and the aligner uses ONLY its -f file input — running the seed
 * to completion (exit 0) and writing its CSV. This target only ever reads via `-f @@`, so it
 * never needs stdin; the aligner's first subsequent fopen() harmlessly reuses fd 0. Linked into
 * parasail_aligner ONLY (via CMAKE_EXE_LINKER_FLAGS in mayhem/build.sh) — matrix-create and the
 * test suite are untouched.
 */
#include <unistd.h>

__attribute__((constructor))
static void mayhem_close_stdin(void)
{
    close(0);
}
