#!/bin/bash
# caliptra-rtl recipe. Contract: see stead/recipe.py.
#   run.sh build <tree>                                            Verilator build of caliptra_top_tb (FST always on)
#   run.sh run   <tree> <smoke_test_sha256> <out> [--dump=on|off]  build the test firmware and run it (~3 min)
#   run.sh suite <tree> <out> [<regex>]                            the 59 L0 smoke tests (~3 min each); pass a regex for a subset
# E/A come from the firmware's expected/actual prints, S/T from the AHB bus log (+CLP_BUS_LOGS); stead_line.py
# joins them. A hang (+CLP_MAX_CYCLES) or a fired assertion (CLP_ASSERT_ON, shim.patch) ends in a NOTE line, exit 1.
# The build/run dir is <tree>/work/trace (gitignored).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../env.sh"
verb=$1; tree=$(cd "$2" && pwd)
export CALIPTRA_ROOT=$tree CALIPTRA_AXI4PC_DIR=$tree/src/integration/tb
export CALIPTRA_PRIM_ROOT=$tree/src/caliptra_prim_generic CALIPTRA_PRIM_MODULE_PREFIX=caliptra_prim_generic
# --trace-threads is fatal on Verilator 5.050; GCC 15 -O3 firmware overflows the 96 KiB ROM, and its C23
# default rejects older firmware's `void f()` prototypes; older commits have Verilator warnings the tool
# now treats as fatal
MK=(make -f "$tree/tools/scripts/Makefile" debug=1 VERILATOR_TRACE=fst "VERILATOR_DEBUG=--trace-fst -Wno-fatal" "BUILD_CFLAGS=-O2 -std=gnu17")
W=$tree/work/trace
# +CLP_MAX_CYCLES per test: 1.5x its clean run (the table), else the longest; a hang then ends inside the harness limit
cycles() { case $1 in
  *) echo 2000000 ;;
esac; }
case $verb in
  build)
    mkdir -p "$W" && cd "$W" || exit 2
    rm -rf obj_dir verilator-build            # never trust a copied sim: the stamp file says "up to date"
    "${MK[@]}" TESTNAME=iccm_lock verilator-build > "$tree/build.log" 2>&1
    [ -x obj_dir/Vcaliptra_top_tb ] || { grep -m3 -E "%Error|error:" "$tree/build.log"; exit 2; }
    exit 0 ;;
  run)
    test=$3; out=$(mkdir -p "$4" && cd "$4" && pwd); dump=${5:---dump=on}
    [ -x "$W/obj_dir/Vcaliptra_top_tb" ] || { echo "not built" > "$out/sim.log"; exit 2; }
    cd "$W" || exit 2
    rm -f program.hex *.o sim.fst console.log exec.log lsu_master_ahb_trace.log verilator_sim.log
    cap=$(cycles "$test")   # the test's own plusargs (its yml) ride along, so the OCP lock setting is not random
    args=$(grep -oE "^\s*-\s*'?\+[A-Za-z0-9_=]+" "$tree/src/integration/test_suites/$test/$test.yml" 2>/dev/null | grep -oE "\+.*" | tr '\n' ' ')
    "${MK[@]}" TESTNAME="$test" verilator VERILATOR_RUN_ARGS="+CLP_BUS_LOGS +CLP_MAX_CYCLES=$cap $args" > "$out/run.log" 2>&1 || true
    [ -f verilator_sim.log ] || { grep -m3 -iE "error" "$out/run.log" > "$out/sim.log"; exit 2; }   # the firmware did not build: no sim ran
    cp console.log lsu_master_ahb_trace.log "$out/" 2>/dev/null
    if [ "$dump" = --dump=on ] && [ -f sim.fst ]; then mv sim.fst "$out/dump.fst"; else rm -f sim.fst; fi
    cat verilator_sim.log console.log > "$out/sim.log"   # everything the sim and the firmware printed, the verdict last
    if grep -q "TESTCASE PASSED" verilator_sim.log; then echo "PASS  test=$test" >> "$out/sim.log"; exit 0; fi
    if grep -q "TESTCASE FAILED" verilator_sim.log; then
      python3 "$HERE/stead_line.py" "$out" "$test" "$out/dump.fst" >> "$out/sim.log" || exit 3   # the joiner crashed: a crash, not a verdict
      exit 1
    fi
    if grep -q "Hit max cycle count" verilator_sim.log; then echo "NOTE  test=$test  hang  (no test end inside $cap cycles)" >> "$out/sim.log"; exit 1; fi
    if grep -q "Assertion failed in" verilator_sim.log; then
      echo "NOTE  test=$test  assertion  $(grep -m1 "Assertion failed in" verilator_sim.log)" >> "$out/sim.log"; exit 1
    fi
    exit 3 ;;
  suite)
    grep -vE "^\s*#" "$tree/src/integration/stimulus/L0_regression.yml" | grep -o "test_suites/[A-Za-z0-9_]*/" | cut -d/ -f2 | sort -u | stead_suite "$0" "$tree" "$(mkdir -p "$3" && cd "$3" && pwd)" "${4:-.}" ;;
  *) echo "usage: run.sh build <tree> | run <tree> <test> <out> [--dump=on|off] | suite <tree> <out> [<regex>]" >&2; exit 64 ;;
esac
