#!/bin/bash
# ibex recipe. Contract: see stead/recipe.py.
#   run.sh build <tree>                                        fusesoc Verilator build of ibex_riscv_compliance
#   run.sh run   <tree> <isa>/<test> <out> [--dump=on|off]     one riscv-compliance test, e.g. rv32i/I-XOR-01
#   run.sh suite <tree> <out> [<regex>]                        the compliance tests minus the known clean-tree fails
# The testbench prints the STEAD line (shim.patch): it compares the signature with the reference as it
# reads it, and traces a wrong byte to the store that last wrote it. Test ELFs come prebuilt from
# $STEAD_TOOLS/riscv-compliance/work/<isa>/; rv32mi and rv32si are not run (their suite dirs have no
# compile target in the tools image). A hang
# (--term-after-cycles) or a fired assertion (--assert, with the real SVA macros from shim.patch) is
# exit 1. sim.log is only what the sim printed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../env.sh"
COMP=$STEAD_TOOLS/riscv-compliance
KNOWN="I-EBREAK-01 I-ECALL-01 I-MISALIGN_JMP-01 I-MISALIGN_LDST-01"   # trap tests the 2019 suite and ibex disagree on
verb=$1; tree=$(cd "$2" && pwd)
VENV=$tree/build/venv
export PATH=$VENV/bin:$PATH
SIM=$tree/build/lowrisc_ibex_ibex_riscv_compliance_0.1/sim-verilator/Vibex_riscv_compliance
case $verb in
  build)
    cd "$tree" || exit 2
    # the commit's own fusesoc and edalize, once per image (their API moved over the years). PyPI pins
    # install normally; the lowRISC git forks older commits pin need setuptools 68 without build isolation.
    [ -x "$VENV/bin/fusesoc" ] || {
      python3 -m venv "$VENV" && "$VENV/bin/pip" install -q "setuptools==68.2.2" "setuptools_scm<8" wheel pyyaml mako hjson packaging
      grep -E "^(fusesoc|edalize) *==" python-requirements.txt | tr -d " " | xargs -r "$VENV/bin/pip" install -q
      grep -E "^git\+" python-requirements.txt | tr -d " " | xargs -r "$VENV/bin/pip" install -q --no-build-isolation
      [ -x "$VENV/bin/fusesoc" ]
    } > venv.log 2>&1 || { grep -iE "error" venv.log | tail -3; exit 2; }
    OPTS=$(python3 util/ibex_config.py small fusesoc_opts | tr ' ' '\n' | grep -v '^--BaseIsa=' | tr '\n' ' ')
    fusesoc --cores-root=. run --target=sim --setup --build lowrisc:ibex:ibex_riscv_compliance $OPTS \
      --verilator_options="-Wno-UNOPTFLAT --assert" > build.log 2>&1
    [ -x "$SIM" ] || { grep -m3 -E "%Error|error:" build.log; exit 2; }
    exit 0 ;;
  run)
    isa=${3%%/*}; test=${3#*/}; out=$(mkdir -p "$4" && cd "$4" && pwd); dump=${5:---dump=on}
    vmem=$COMP/work/$isa/$test.elf.vmem; ref=$COMP/riscv-test-suite/$isa/references/$test.reference_output
    [ -x "$SIM" ] || { echo "not built" > "$out/sim.log"; exit 2; }
    [ -f "$vmem" ] || { echo "no prebuilt test: $vmem (run the compliance make once)" > "$out/sim.log"; exit 2; }
    [ -f "$ref" ] || { echo "no reference signature: $ref" > "$out/sim.log"; exit 2; }   # the testbench compares against it
    trace=""; [ "$dump" = --dump=on ] && trace="--trace=$out/dump.fst +dump_file=$out/dump.fst"
    ( cd "$out" && "$SIM" --raminit="$vmem" $trace --term-after-cycles=100000 +stead_test="$test" +stead_ref="$ref" > sim.log 2>&1
      mv -f trace_core_00000000.log trace.log 2>/dev/null )
    grep -qE "Simulation timeout of|Assertion failed in" "$out/sim.log" && exit 1   # a hang, or a fired assertion
    grep -q "^SIGNATURE: " "$out/sim.log" || exit 3                             # the sim died before the test ended
    grep -qE "^(FAIL|NOTE) " "$out/sim.log" && exit 1                           # the testbench's signature check
    exit 0 ;;
  suite)
    for isa in rv32i rv32im rv32imc rv32Zicsr rv32Zifencei; do for r in "$COMP/riscv-test-suite/$isa/references"/*.reference_output; do t=$(basename "$r" .reference_output); case " $KNOWN " in *" $t "*) ;; *) echo "$isa/$t";; esac; done; done | stead_suite "$0" "$tree" "$(mkdir -p "$3" && cd "$3" && pwd)" "${4:-.}" ;;
  *) echo "usage: run.sh build <tree> | run <tree> <test> <out> [--dump=on|off] | suite <tree> <out> [<regex>]" >&2; exit 64 ;;
esac
