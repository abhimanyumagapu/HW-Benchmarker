#!/bin/bash
# openc910 recipe. Contract: see stead/recipe.py.
#   run.sh build <tree>                                   the smart_run Verilator TB (FST) and the five tests
#   run.sh run   <tree> <test> <out> [--dump=on|off]      one test: ISA_IMAC, ISA_FP, ISA_AMO, ISA_THEAD or exception
#   run.sh suite <tree> <out> [<regex>]                   the five
# The other smart_run cases have no value check (or no stimulus in the Verilator TB) and are not run.
# openc910 targets Verilator 4 and T-Head's GCC 8. For Verilator 5.050 and GCC 15: -Os dropped,
# --no-timing (Verilator 4 ignored delays too), the timescale overridden so $time is the dump's time,
# xtheadc spelled as its parts, T-Head's CSR names given as symbols, bash for the case rules' `>&`,
# and srec2vmem.py for the x86-only Srec2vmem. shim.patch renames old T-Head mnemonics to th.*, keeps
# two li in ISA_IMAC uncompressed, and adds the dump and the trace stead_line.py reads.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../env.sh"
verb=$1; tree=$(cd "$2" && pwd)
S=$tree/smart_run
SIM=$S/work/obj_dir/Vtop
TESTS="ISA_IMAC ISA_FP ISA_AMO ISA_THEAD exception"
MAX_CYCLES=100000   # per run, 4x the longest clean test; a livelock ends here, a deadlock at the TB's 50k idle cycles
export CODE_BASE_PATH=$tree/C910_RTL_FACTORY TOOL_EXTENSION=$STEAD_TOOLS/bin
VFLAGS="-x-assign 0 -Wno-fatal --no-timing --threads 4 --trace-fst --timescale-override 1ns/1ns"
MARCH=rv64imafdc_zicsr_zifencei_zfh_xtheadba_xtheadbb_xtheadbs_xtheadcmo_xtheadcondmov
MARCH=${MARCH}_xtheadfmemidx_xtheadmac_xtheadmemidx_xtheadmempair_xtheadsync_xtheadfmv_xtheadint
# T-Head CSRs GCC 15 does not name, with the numbers gen_rtl/cp0 gives them
CSRS="
  fxcr=0x800 hpmcnt10=0xc0a hpmcnt11=0xc0b hpmcnt12=0xc0c hpmcnt13=0xc0d hpmcnt14=0xc0e
  hpmcnt15=0xc0f hpmcnt16=0xc10 hpmcnt17=0xc11 hpmcnt18=0xc12 hpmcnt19=0xc13 hpmcnt20=0xc14
  hpmcnt21=0xc15 hpmcnt22=0xc16 hpmcnt23=0xc17 hpmcnt24=0xc18 hpmcnt25=0xc19 hpmcnt26=0xc1a
  hpmcnt27=0xc1b hpmcnt28=0xc1c hpmcnt29=0xc1d hpmcnt3=0xc03 hpmcnt30=0xc1e hpmcnt31=0xc1f
  hpmcnt4=0xc04 hpmcnt5=0xc05 hpmcnt6=0xc06 hpmcnt7=0xc07 hpmcnt8=0xc08 hpmcnt9=0xc09
  mapbaddr=0xfc1 mccr2=0x7c3 mcdata0=0x7d4 mcdata1=0x7d5 mcer=0x7c8 mcer2=0x7c4 mcindex=0x7d3
  mcins=0x7d2 mcnten=0x306 mcntihbt=0x320 mcntinten=0x7ca mcntof=0x7cb mcntwen=0x7c9 mcor=0x7c2
  mcpuid=0xfc0 meicr=0x7d6 meicr2=0x7d7 mhcr=0x7c1 mhint=0x7c5 mhint2=0x7cc mhint3=0x7cd
  mhint4=0x7ce mhpmcnt10=0xb0a mhpmcnt11=0xb0b mhpmcnt12=0xb0c mhpmcnt13=0xb0d mhpmcnt14=0xb0e
  mhpmcnt15=0xb0f mhpmcnt16=0xb10 mhpmcnt17=0xb11 mhpmcnt18=0xb12 mhpmcnt19=0xb13 mhpmcnt20=0xb14
  mhpmcnt21=0xb15 mhpmcnt22=0xb16 mhpmcnt23=0xb17 mhpmcnt24=0xb18 mhpmcnt25=0xb19 mhpmcnt26=0xb1a
  mhpmcnt27=0xb1b mhpmcnt28=0xb1c mhpmcnt29=0xb1d mhpmcnt3=0xb03 mhpmcnt30=0xb1e mhpmcnt31=0xb1f
  mhpmcnt4=0xb04 mhpmcnt5=0xb05 mhpmcnt6=0xb06 mhpmcnt7=0xb07 mhpmcnt8=0xb08 mhpmcnt9=0xb09
  mhpmcr=0x7f0 mhpmep=0x7f2 mhpmevt10=0x32a mhpmevt11=0x32b mhpmevt12=0x32c mhpmevt13=0x32d
  mhpmevt14=0x32e mhpmevt15=0x32f mhpmevt16=0x330 mhpmevt17=0x331 mhpmevt18=0x332 mhpmevt19=0x333
  mhpmevt20=0x334 mhpmevt21=0x335 mhpmevt22=0x336 mhpmevt23=0x337 mhpmevt24=0x338 mhpmevt25=0x339
  mhpmevt26=0x33a mhpmevt27=0x33b mhpmevt28=0x33c mhpmevt29=0x33d mhpmevt3=0x323 mhpmevt30=0x33e
  mhpmevt31=0x33f mhpmevt4=0x324 mhpmevt5=0x325 mhpmevt6=0x326 mhpmevt7=0x327 mhpmevt8=0x328
  mhpmevt9=0x329 mhpmsp=0x7f1 mrmr=0x7c6 mrvbr=0x7c7 msmpr=0x7f3 mteecfg=0x7f4 mwmsr=0xfc2
  mxstatus=0x7c0 scer=0x5c3 scer2=0x5c2 scnten=0x106 scntihbt=0x5c8 scntinten=0x5c4 scntof=0x5c5
  scycle=0x5e0 shcr=0x5c1 shint=0x5c6 shint2=0x5c7 shpmcnt10=0x5ea shpmcnt11=0x5eb
  shpmcnt12=0x5ec shpmcnt13=0x5ed shpmcnt14=0x5ee shpmcnt15=0x5ef shpmcnt16=0x5f0 shpmcnt17=0x5f1
  shpmcnt18=0x5f2 shpmcnt19=0x5f3 shpmcnt20=0x5f4 shpmcnt21=0x5f5 shpmcnt22=0x5f6 shpmcnt23=0x5f7
  shpmcnt24=0x5f8 shpmcnt25=0x5f9 shpmcnt26=0x5fa shpmcnt27=0x5fb shpmcnt28=0x5fc shpmcnt29=0x5fd
  shpmcnt3=0x5e3 shpmcnt30=0x5fe shpmcnt31=0x5ff shpmcnt4=0x5e4 shpmcnt5=0x5e5 shpmcnt6=0x5e6
  shpmcnt7=0x5e7 shpmcnt8=0x5e8 shpmcnt9=0x5e9 shpmcr=0x5c9 shpmep=0x5cb shpmsp=0x5ca
  sinstret=0x5e2 smcir=0x9c3 smeh=0x9c2 smel=0x9c1 smir=0x9c0 sxstatus=0x5c0"
FLAG_MARCH="-march=$MARCH -fpermissive $(for c in $CSRS; do printf -- '-Wa,--defsym,%s ' "$c"; done)"
case $verb in
  build)
    mkdir -p "$S/work"  # smart_run compiles in work/, which the repository does not hold
    { make -s -C "$S" compile SIM=verilator SIMULATOR_OPT="$VFLAGS" \
        && cp "$S/logical/tb/Makefile_obj" "$S/work/" \
        && make -j4 -C "$S/work/obj_dir" -f ../Makefile_obj; } > "$tree/build.log" 2>&1
    [ -x "$SIM" ] || { grep -m3 -E "%Error|error:" "$tree/build.log" || tail -3 "$tree/build.log"; exit 2; }
    for t in $TESTS; do
      if [ "$t" = exception ]; then   # not in smart_cfg.mk's case list: its ISA_*_build steps by hand
        make -s -C "$S" cleancase && cp "$S"/tests/cases/exception/* "$S/work/" \
          && find "$S/tests/lib/" -maxdepth 1 -type f -exec cp {} "$S/work/" \; \
          && make -s -C "$S/work" all CPU_ARCH_FLAG_0=c910 ENDIAN_MODE=little-endian CASENAME=exception \
               FILE=ct_expt_smoke FLAG_MARCH="$FLAG_MARCH" CONVERT="python3 $HERE/srec2vmem.py"
      else
        make -s -C "$S" SHELL=/bin/bash buildcase CASE=$t FLAG_MARCH="$FLAG_MARCH" CONVERT="python3 $HERE/srec2vmem.py"
      fi >> "$tree/build.log" 2>&1
      mkdir -p "$S/cases/$t" && cp "$S"/work/inst.pat "$S"/work/data.pat "$S"/work/*.elf "$S/cases/$t/" \
        || { echo "test $t did not build: $S/work/${t}_build.case.log"; exit 2; }
    done
    exit 0 ;;
  run)
    test=$3; out=$(mkdir -p "$4" && cd "$4" && pwd); dump=${5:---dump=on}
    [ -x "$SIM" ] || { echo "not built" > "$out/sim.log"; exit 2; }
    [ -f "$S/cases/$test/inst.pat" ] || { echo "no such test: $test" > "$out/sim.log"; exit 2; }
    cp "$S/cases/$test/inst.pat" "$S/cases/$test/data.pat" "$out/"
    plus="+trace_file=$out/trace.txt"; [ "$dump" = --dump=on ] && plus="$plus +dump_file=$out/dump.fst"
    ( cd "$out" && "$SIM" $plus +max_cycles=$MAX_CYCLES > stdout 2>&1 )
    grep -q "simulation finished successfully" "$out/stdout" && { cp "$out/stdout" "$out/sim.log"; exit 0; }
    if grep -qE "no instructions retired|meeting max simulation time" "$out/stdout"; then
      { cat "$out/stdout"; echo "NOTE  test=$test  hang  (no test end inside $MAX_CYCLES cycles)"; } > "$out/sim.log"; exit 1
    fi
    # anything but a check jumping to __fail (watchdog, timeout, crash) is not a verdict
    grep -q "simulation finished with error" "$out/stdout" || { cp "$out/stdout" "$out/sim.log"; exit 3; }
    { cat "$out/stdout"; python3 "$HERE/stead_line.py" "$test" "$S/cases/$test"/*.elf "$out/trace.txt" "$out/dump.fst"; } \
      > "$out/sim.log" || exit 3
    exit 1 ;;
  suite)
    printf '%s\n' $TESTS | stead_suite "$0" "$tree" "$(mkdir -p "$3" && cd "$3" && pwd)" "${4:-.}" ;;
  *) echo "usage: run.sh build <tree> | run <tree> <test> <out> [--dump=on|off] | suite <tree> <out> [<regex>]" >&2; exit 64 ;;
esac
