# AGENTS.md

This file is the working operator guide for this repo. Keep it current as the
actual build, run, dump, and verifier workflows evolve.

## Scope

These notes are for the ARM64 JIT work under:

- [/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64](/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64)
- [/Users/zizhengguo/scratch/ish-arm64/build-arm64-release](/Users/zizhengguo/scratch/ish-arm64/build-arm64-release)

## Non-Negotiable Process Rules

- Always use a bounded timeout for every `ish` run. Never launch unbounded guest
  runs during development. Hung guest runs will accumulate and clog the host.
- Do not treat `exit 0` by itself as proof that a run succeeded. For small
  smoke tests, explicitly inspect stdout.
- Prefer small repros first:
  - `/bin/echo hello`
  - `/root/cbench_lite_arm64`
- Use verifier aggressively to debug correctness. Do not roll back a feature
  just because it is broken; instead, find the first mismatch frontier and fix
  it.
- When changing helper ABI or memory-helper shape, update this file and
  [/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64/helpers.S](/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64/helpers.S)
  comments together.

## Build

The repo root does not have a top-level makefile. Use Meson/Ninja for the
standalone ARM64 host binary.

### Configure

```bash
meson setup build-arm64-release -Dguest_arch=arm64 --buildtype=release
```

If the build directory is already configured, do not rerun setup unless Meson
options changed.

### Build

```bash
ninja -C build-arm64-release
```

If the build directory already exists and only code changed, usually this is
enough:

```bash
ninja -C build-arm64-release
```

## Actual Build Commands Used In Current Work

Use these exact commands during JIT development:

### Rebuild after source edits

```bash
ninja -C build-arm64-release
```

If sandboxed execution blocks the default ccache directory under
`~/Library/Caches`, keep ccache inside writable temp storage:

```bash
env CCACHE_DIR=/private/tmp/ish-arm64-ccache ninja -C build-arm64-release
```

### First-time setup, only if `build-arm64-release` does not exist yet

```bash
meson setup build-arm64-release -Dguest_arch=arm64 --buildtype=release
ninja -C build-arm64-release
```

Do not use a top-level `make` in repo root. It will fail because there is no
root makefile.
Do not use `make` inside `build-arm64-release` either; this build directory is
managed by Ninja, so use `ninja -C build-arm64-release`.

## Fakefs / Rootfs

The common rootfs used in local runs is:

- [/Users/zizhengguo/scratch/ish-arm64/build/alpine-arm64-fakefs](/Users/zizhengguo/scratch/ish-arm64/build/alpine-arm64-fakefs)

Interactive shell:

```bash
./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /bin/sh
```

## Bounded Run Pattern

Always run guest programs with a timeout.

### Plain JIT smoke

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /bin/echo hello \
  > /private/tmp/echo.stdout 2> /private/tmp/echo.stderr
```

Success criterion for this smoke is:

- process exits before timeout
- `/private/tmp/echo.stdout` contains exactly `hello`

`exit 0` alone is not enough.

### Plain JIT benchmark

```bash
timeout 30s env ISH_ARM64_BACKEND=arm64_jit \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /root/cbench_lite_arm64
```

### Redirect capture

```bash
timeout 30s env ISH_ARM64_BACKEND=arm64_jit \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /root/cbench_lite_arm64 \
  > /private/tmp/cbench.stdout 2> /private/tmp/cbench.stderr
```

If redirected output disagrees with tty output, suspect guest stdio/path
compatibility rather than assuming a JIT semantic bug immediately.

## Verifier Launch

Verifier is for correctness, not throughput. Keep the target small first.

### Small verifier repro

```bash
timeout 30s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_VERIFY=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /bin/echo hello \
  > /private/tmp/echo_verify.stdout 2> /private/tmp/echo_verify.stderr
```

### Quiet verifier repro

Use quiet verifier mode for long-running tests when step-by-step matched logs
are too expensive and only mismatch/frontier output is needed.

```bash
timeout 30s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_VERIFY=1 \
  ISH_ARM64_JIT_VERIFY_QUIET=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk update \
  > /private/tmp/apk_update_verify.stdout 2> /private/tmp/apk_update_verify.stderr
```

### Benchmark verifier repro

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_VERIFY=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /root/cbench_lite_arm64 \
  > /private/tmp/cbench_verify.stdout 2> /private/tmp/cbench_verify.stderr
```

### Verifier logging notes

- Verifier step logs include timestamps and deltas.
- Every verifier log line should carry a wall-time prefix. Use that to tell
  the difference between “actively making progress” and “reached the last
  visible frontier immediately, then stopped”.
- When a run appears “stuck”, check whether the last step was reached almost
  immediately and then stopped progressing.
- The first mismatch frontier is the only thing that matters; do not chase
  downstream symptoms first.
- For `/bin/echo hello`, “verifier cleared” means both:
  - no `mismatch at` line in stderr
  - stdout actually contains `hello`

## Trace Launch

Use trace only with timeout and only when narrowing a specific region.

### Plain JIT trace

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_TRACE=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /bin/echo hello \
  > /private/tmp/echo_trace.stdout 2> /private/tmp/echo_trace.stderr
```

### Verifier + trace

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_VERIFY=1 ISH_ARM64_JIT_TRACE=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /bin/echo hello \
  > /private/tmp/echo_verify_trace.stdout 2> /private/tmp/echo_verify_trace.stderr
```

Do not leave trace enabled on broad benchmark runs unless the scope is tightly
filtered.

## Branch-Reg Fast Path

The JIT-side branch-register resolver is the default implementation for
`BR`/`BLR`/`RET`. It is no longer opt-in.

`ISH_ARM64_JIT_BRANCH_REG_TRACE=1` logs every runtime branch-register helper
resolution, including the source PC, target, link registers, and JIT debug
slots. This is very verbose; use it only with a narrow bounded repro.

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_BRANCH_REG_TRACE=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_branch_trace.stdout 2> /private/tmp/apk_branch_trace.stderr
```

The branch-reg resolver shape is:

- same-fragment `BR`/`RET`: resolve target PC to current-fragment host offset
  and branch directly with no spill
- cross-fragment cache hit: restore touched live JIT state, call the source
  fragment `light_spill_state_fn`, update runtime block/spill/reload/light-spill
  fields and `rt->entry_target`, then branch to the target JIT-to-JIT light
  entry without running the source fragment full epilogue
- cache miss/failure: restore touched live JIT state, call the source fragment
  full `spill_state_fn`, then fall back to the C branch-register helper

## Runtime Frontier Debugging

These knobs are for plain JIT debugging when verifier throughput is too low for
the target. Always combine them with `timeout`.

`ISH_ARM64_JIT_HANDOFF_AFTER_BLOCKS=N` runs the first `N` JIT block dispatches,
then hands execution back to the threaded backend. It is useful for bisecting a
plain-JIT-only behavioral difference.

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_HANDOFF_AFTER_BLOCKS=2267808 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_handoff.stdout 2> /private/tmp/apk_handoff.stderr
```

`ISH_ARM64_JIT_UNTIL_PC=0x...` hands off when dispatch reaches a specific guest
PC. `ISH_ARM64_JIT_PROGRESS_INTERVAL=N` logs every `N` dispatched JIT blocks.
`ISH_ARM64_JIT_PROGRESS_START_BLOCKS=N` suppresses progress logs until the
dispatch counter reaches `N`; combine it with a small interval when narrowing a
late hot/stuck region without producing huge logs.

Verifier narrowing knobs:

- `ISH_ARM64_JIT_VERIFY_FILTER=0xPC` emits verifier `brk` sites only for blocks
  covering that PC and skips cross-block branch observations inside the filter.
- `ISH_ARM64_JIT_VERIFY_START_BLOCK=N` ignores verifier traps before the `N`th
  dispatched JIT block. Use it only with a bounded command.

Very narrow trace knobs:

- `ISH_ARM64_JIT_IMM9_TRACE=1` prints up to 512 scalar imm9 C-helper entries,
  including decoded mode/base/address/writeback context.
- `ISH_ARM64_JIT_BRK_TRACE=1` traces host-side JIT verifier `brk` handling.
- `ISH_ARM64_SIGNAL_TRACE=1` traces guest signal delivery/recovery context.

## Runtime Bottleneck Profiling

Use syscall-segment profiling to compare guest execution time between syscall
boundaries. This is useful when a complete workload is slower under JIT but the
syscall count and stdout are correct.

Use sampling when dispatch/c-helper counters are insufficient because a hot loop
stays inside one fragment and does not cross JIT block boundaries often.
Sampling is diagnostic-only and uses `ITIMER_PROF`, so do not use sampled runs as
benchmark timings.

### Guest-PC Sampling Profile

The JIT sampler maps sampled host PCs in the current JIT fragment back to guest
PCs using the fragment `pc_map`. It prints ranked
`[arm64-jit-sample-profile]` lines when guest PID 1 exits, and also during
final host shutdown before the runtime calls `_exit`.

```bash
timeout 30s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_SAMPLE_PROFILE=1 \
  ISH_ARM64_JIT_SAMPLE_INTERVAL_US=500 \
  ISH_ARM64_JIT_SAMPLE_TOP=64 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_sample.stdout \
  2> /private/tmp/apk_sample.stderr
```

For short workloads, repeat the target inside a bounded guest shell and require a
visible success marker:

```bash
timeout 60s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_SAMPLE_PROFILE=1 \
  ISH_ARM64_JIT_SAMPLE_INTERVAL_US=500 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs \
  /bin/sh -c 'i=0; while [ $i -lt 10 ]; do /sbin/apk stats >/dev/null || exit 1; i=$((i+1)); done; echo done' \
  > /private/tmp/apk_sample_loop.stdout \
  2> /private/tmp/apk_sample_loop.stderr
```

Success criterion for this loop smoke is that stdout contains exactly `done`.
If the sampler reports many `outside` samples, time is being spent in C helpers,
runtime, syscalls, or other non-current-fragment host code. If it reports many
`jit_snippet` samples, inspect fragment entry/exit/reload/spill snippets.

Hot-path hit/miss counters for JIT-to-JIT branch resolution are gated by the
Meson option `arm64_jit_perf_counters`. Enable it explicitly before diagnosing
fragment-cache hit rates:

```bash
meson configure build-arm64-release -Darm64_jit_perf_counters=true
env CCACHE_DIR=/private/tmp/ish-arm64-ccache ninja -C build-arm64-release
```

Turn it back off for normal performance measurements if counter increments are
not part of the experiment:

```bash
meson configure build-arm64-release -Darm64_jit_perf_counters=false
env CCACHE_DIR=/private/tmp/ish-arm64-ccache ninja -C build-arm64-release
```

### Default backend syscall segments

```bash
timeout 30s env ISH_SYSCALL_SEGMENT_PROFILE=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_stats_default_seg.stdout \
  2> /private/tmp/apk_stats_default_seg.stderr
```

### JIT syscall segments with helper-family deltas

```bash
timeout 30s env ISH_SYSCALL_SEGMENT_PROFILE=1 ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_HELPER_PROFILE=1 ISH_ARM64_JIT_HELPER_PROFILE_INTERVAL=0 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_stats_jit_seg.stdout \
  2> /private/tmp/apk_stats_jit_seg.stderr
```

Each `[syscall-segment]` line reports:

- `guest_ns`: guest execution time since the previous syscall returned
- `syscall_ns`: host time spent handling the syscall itself
- `jit_*`: JIT block/control/C-helper deltas for that syscall-bounded segment

The helper-family deltas only become nonzero when
`ISH_ARM64_JIT_HELPER_PROFILE=1` is enabled.

To find which guest PCs cause repeated returns to the outer JIT dispatcher
inside one syscall-bounded segment, enable dispatch-PC profiling:

```bash
timeout 30s env ISH_SYSCALL_SEGMENT_PROFILE=1 ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_HELPER_PROFILE=1 ISH_ARM64_JIT_HELPER_PROFILE_INTERVAL=0 \
  ISH_ARM64_JIT_DISPATCH_PC_PROFILE=1 \
  ISH_ARM64_JIT_DISPATCH_PC_SEGMENT_MIN_BLOCKS=20000 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_dispatch_pc_segment.stdout \
  2> /private/tmp/apk_dispatch_pc_segment.stderr
```

The segment-local dispatch-PC table is reset after each segment dump.
`[arm64-jit-dispatch-pc-segment]` lines therefore describe guest dispatches
from the syscall-bounded segment that produced the same `index`.

With `arm64_jit_perf_counters=true`, helper-profile output also includes branch
fast counters:

- `branch_fast same_fragment/fragment_tlb/misses` for `BR`/`BLR`/`RET`
- `control_fast dispatch/b_cond/cbz/tbz=same_fragment/fragment_tlb/misses`
  for fixed-target and conditional control transfers

The `fragment_tlb` field reports the second-level 2-way range cache. More
detailed `*_l1` lines split exact-PC L1 hits from compact code-page-list hits.

### Fragment-Per-Page Profiling

Use this when diagnosing fragment-cache associativity and whether hot guest code
pages are split into many live fragments:

```bash
timeout 30s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_FRAGMENT_PAGE_PROFILE=1 \
  ISH_ARM64_JIT_FRAGMENT_PAGE_PROFILE_INTERVAL=5000000 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_pagefrag.stdout \
  2> /private/tmp/apk_pagefrag.stderr
```

To take a late single-bucket snapshot, set
`ISH_ARM64_JIT_FRAGMENT_PAGE_PROFILE_INTERVAL` just below the expected final
`dispatch_blocks` count for the target. This is useful for avoiding very large
logs while still getting a near-final page-fragment layout.

Use `ISH_ARM64_JIT_FRAGMENT_PAGE_DETAIL=0xPAGE` with the same bounded command
to print each live fragment that overlaps a page. This is useful when a page
has many fragments and the top-line count alone does not explain why.

With `arm64_jit_perf_counters=true`, helper-profile output includes the top
branch-reg `same_page_range` miss pages. To sample the actual 2-way fragment
cache set contents at miss time for one page, use:

```bash
ISH_ARM64_JIT_BRANCH_MISS_DETAIL=0xPAGE
```

This prints at most 128 lines and is intended for associativity/thrashing
diagnosis. Do not use `ISH_ARM64_JIT_FRAGMENT_PAGE_PROFILE_INTERVAL=0` as a
final-only mode. Interval `0` currently buckets by every dispatch count and can
produce very large logs.

Common control families should use the fast resolver rather than old C helper
wrappers:

- fixed-target `B`/`BL`
- nonlocal conditional `B.cond`
- nonlocal `CBZ`/`CBNZ`, including uncached tested registers loaded from CPU
  state
- nonlocal `TBZ`/`TBNZ`, including uncached tested registers loaded from CPU
  state
- branch-register forms `BR`/`BLR`/`RET`

## Branch-Link Notes

Plain JIT and verifier mode should use the same instruction implementations;
verifier mode should differ only by inserted verifier `brk` sites.

Fixed-target `BL` currently sets guest `LR` to `guest_pc + 4`, then branches to
the target. Same-fragment targets use local fixups. Cross-fragment targets use
the same fast control-transfer resolver as other nonlocal control transfers and
only fall back to C dispatch on resolver miss. Do not reintroduce C-managed
nested direct-call continuation semantics for `BL`.

## Fast JIT V1

Fast JIT V1 is enabled by default for plain ARM64 JIT runs. Disable it only when
comparing against the slow JIT tier or narrowing a Fast JIT-specific bug:

```bash
ISH_ARM64_JIT_FAST=0
```

Verifier mode disables Fast JIT V1 automatically. In V1, verifier runs must
still use the normal slow-JIT implementations with only verifier `brk` sites
added.

Current safety state:

- Fast JIT mode enables edge profiling, hot-edge trace compilation,
  function-entry profiling/tiering, fast-trace cache lookup, and standalone
  fast-trace execution unless `ISH_ARM64_JIT_FAST=0` is set.
- Verifier mode forcibly disables Fast JIT V1.
- A newly compiled fast trace is installed for future natural dispatches only.
  Do not rewind `cpu->pc` to replay the already-executed hot source edge in the
  same dispatch; that re-executes code against later architectural state.

Current V1 direction:

- Fast traces are expanded from hot branch-heavy source PCs, not from cold
  opportunistic fixed calls.
- A small PC-indexed fast-trace cache and standalone synthetic fast block
  emitter exist. Fast trace blocks are not published into normal slow-fragment
  maps; cache replacement owns and discards them directly.
- Fixed-target/control JITABI helpers receive `source_pc` in `x3`
  (`x0=rt`, `x1=target_pc`, `x2=kind`, `x3=source_pc`). Branch-register
  JITABI helpers already receive source PC and resolved target. When
  Fast JIT mode is enabled, these helpers update a small edge-profile table
  directly without calling C on fast hits.
- The trace builder follows bounded fixed `BL`/`B` expansion and emits the
  expanded body through the normal slow-JIT instruction emitters. Do not add
  opcode whitelists for fast traces.
- Function-entry trace construction uses a reachable-PC pending-target stack,
  not a blind linear scan. Conditional branches append once, continue the
  fallthrough path, and queue the other reachable target; terminal `RET` and
  unconditional `B` pop the next pending target. This prevents a function trace
  from running past a return into the next sequential function while still
  covering real loops.
- V1 function traces are intentionally limited to the current safe target class:
  exactly one guarded observed indirect target and at least one local backedge.
  Multi-guard function traces have exposed incorrect behavior in `/sbin/apk
  stats`; do not relax this until the function-tier ABI/dataflow model can prove
  those traces safe.
- Generic trace path guards currently cover `B.cond`, `CBZ`/`CBNZ`, and
  `TBZ`/`TBNZ`; rejected traces should log the first unsupported frontier when
  `ISH_ARM64_JIT_TRACE=1` is enabled.
- Indirect branches inside an expanded trace are allowed only when generic
  trace dataflow can prove the branch register came from a known guest memory
  load. The emitted fast trace guards that memory address against the observed
  target value before executing the expanded body.
- Guard miss falls back to the normal slow-JIT control-transfer path.
- Trace emission must preflight with a dry-run emitter before writing real code;
  a rejected trace candidate must not leave partial bytes in the source
  fragment.
- Standalone fast-trace blocks are leaf tiering units. They must not record
  edge-profile requests that recursively compile more fast traces while the fast
  trace itself is executing.
- Function-entry fast traces are entered only from `BL`/`BLR` helper paths via a
  target-PC function trace cache lookup. C/top-level dispatch intentionally
  ignores `ARM64_JIT_FAST_TRACE_FUNCTION` entries; otherwise workloads such as
  `/sbin/apk stats` can repeatedly dispatch into standalone function traces and
  fail to make useful forward progress.
- Helper-entered function traces execute only fast-trace-emitted code with the
  fast trace's own cached register map. They must not jump into original
  slow-JIT fragment host code. Terminal guest `RET` is emitted normally and
  returns through the existing branch-register fast helper, so steady-state
  returns can stay in the JIT-to-JIT path.
- Helper-profile output now reports `fast_trace emits`, `dispatch_hits`,
  `runs`, and `guard_exits`. `dispatch_hits/runs` count C-dispatched traces,
  not helper-entered function traces.
- BL/BLR/RET JITABI call-stack profiler hooks are live when Fast JIT is enabled.
  The profiler is intentionally cleared before entering
  a fast trace so fast traces remain leaf tiering units and do not recursively
  request more fast traces from inside optimized code.

Guard fallback test hook:

```bash
timeout 25s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_FAST_FORCE_GUARD_FAIL=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs \
  /usr/bin/sysbench cpu --cpu-max-prime=20000 run
```

Use `ISH_ARM64_JIT_TRACE=1` with a bounded sysbench run to confirm whether a
trace was emitted:

```bash
timeout 25s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_TRACE=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs \
  /usr/bin/sysbench cpu --cpu-max-prime=20000 run \
  > /private/tmp/sysbench_fast.stdout 2> /private/tmp/sysbench_fast.stderr
rg "arm64-jit-fast" /private/tmp/sysbench_fast.stderr
```

The current known-good sysbench CPU fast-function target is the prime-loop
function around `0xefdd46c8`. With dump filtering enabled, the expected fast
trace shape is approximately:

- `function entry=0xefdd46c8 insns=30 guards=1 branch_guards=0`
- fast dump range `0xefdd46c8..0xefdd4730`
- contains the prime loop `0xefdd46e0..0xefdd472c`
- inlines the observed indirect callee path through `0xefdc7920` to
  `fsqrt d0, d0`
- does not include the next sequential function at `0xefdd4730`

## Dump Mode

Dump mode is independent of verifier mode and works in plain JIT mode.

### Plain JIT dump

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_DUMP=1 \
  ISH_ARM64_JIT_DUMP_FILTER=0xeffddc \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /root/cbench_lite_arm64 \
  > /private/tmp/jit_dump.stdout 2> /private/tmp/jit_dump.stderr
```

### Render a dumped fragment

Current JIT dump JSON carries each guest instruction word and PC. Prefer
dump-only rendering for normal analysis; the renderer disassembles the dumped
raw guest words directly with Capstone, so it does not depend on an outer
ELF/base guess for the primary guest instruction annotation.

```bash
python3 -u tools/render_arm64_jit_dump.py \
  /private/tmp/fragment.log
```

### Extract a specific fragment by guest start PC

```bash
python3 -u - <<'PY'
import json
from pathlib import Path
src = Path('/private/tmp/jit_dump.stderr')
want = '0xeffddc94'
for line in src.read_text(errors='replace').splitlines():
    marker = '[arm64-jit-dump] '
    if marker not in line:
        continue
    obj = json.loads(line.split(marker, 1)[1])
    if obj.get('start_pc') == want:
        Path('/private/tmp/fragment.log').write_text(line + '\n')
        break
PY
```

## Common Targets

### `bench_integer`

The current `cbench_lite` `bench_integer` fragment has commonly shown up as:

- `0xeffddc94..0xeffddd78`

Useful dump filter:

```bash
ISH_ARM64_JIT_DUMP_FILTER=0xeffddc
```

### `bench_call`

Useful dump filter:

```bash
ISH_ARM64_JIT_DUMP_FILTER=0xeffde0
```

## JIT vs Gadget Backend

This repo has two separate execution engines relevant to ARM64 guest work:

- threaded-code gadget backend in:
  - [/Users/zizhengguo/scratch/ish-arm64/asbestos/guest-arm64](/Users/zizhengguo/scratch/ish-arm64/asbestos/guest-arm64)
- runtime codegen JIT backend in:
  - [/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64](/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64)

When discussing “JIT” in current debugging, that usually means the runtime
codegen backend selected by:

```bash
ISH_ARM64_BACKEND=arm64_jit
```

If work later needs explicit gadget backend commands, add them here together
with the exact selector env var or launch mechanism once confirmed from code.

## iOS ARM64 JIT / TrollStore Notes

The `iSH-ARM64` Xcode scheme already builds the ARM64 guest libraries through
Meson with `-Dguest_arch=arm64` and links `jit/guest-arm64` into the app target.

Current unsigned device build check:

```bash
timeout 180s xcodebuild -project iSH.xcodeproj -scheme 'iSH-ARM64' \
  -configuration Release -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' EXPANDED_CODE_SIGN_IDENTITY=''
```

Current TrollStore/ad-hoc TIPA packaging command:

```bash
tools/package_arm64_trollstore_ipa.sh
```

The script builds the ARM64 app and `iSHFileProvider.appex` unsigned, stages
`Payload/iSH ARM64.app`, embeds the file provider under `PlugIns/`, signs both
executables with `ldid`, and writes:

```bash
build/iSH-ARM64-JIT-TrollStore.tipa
```

Useful overrides:

- `BUILD_TIMEOUT=300s` for slower clean Xcode builds.
- `OUTPUT_IPA=/path/to/name.tipa` to choose the output path.
- `APP_BUNDLE_ID`, `APP_GROUP_ID`, and `APPEX_BUNDLE_ID` for local bundle ID
  changes.

The ARM64 JIT code allocator is iOS-aware:

- non-iOS builds use the existing single mapping that is sealed with
  `mprotect(PROT_READ | PROT_EXEC)`
- iOS device builds use a single mapping like Folium/oaknut's iPhone path:
  allocate `PROT_READ | PROT_EXEC`, switch to `PROT_READ | PROT_WRITE` while
  emitting into an unpublished compile-only slab, then seal back to
  `PROT_READ | PROT_EXEC`
- `block->code_rw` and `block->code_rx` point into the same mapping on iOS, and
  emitted code is flushed with `sys_icache_invalidate`
- the older iOS `vm_remap` RW/RX alias design was rejected after device crashes
  showed host execution entering a `shared memory` region whose current
  protection was `rw-` despite max `rwx`
- do not use `vm_region_64().protection & VM_PROT_EXECUTE` as the app-level JIT
  availability check; it can reject valid debugger/TrollStore JIT states. Probe
  by attempting the actual allocation/protection transition instead.
- iOS JIT availability is gated on the process `CS_DEBUGGED` code-signing flag
  before entering the backend. A successful `mprotect(PROT_READ | PROT_EXEC)`
  is not enough; device crash logs showed mappings left as `r--/rw-` while
  `mprotect` reported success.

Do not use `pthread_jit_write_protect_np` on iOS; the SDK marks it unavailable
there. Do not add `dynamic-codesigning` for TrollStore iOS 15+ A12+ builds;
TrollStore documents that entitlement as banned on those devices.

Current TrollStore enablement follows Amethyst's working model:

- the ARM64 TrollStore app entitlement file includes `get-task-allow` and
  `com.apple.private.security.no-sandbox`, plus the storage and
  `platform-application` entitlements used by Amethyst's TrollStore package
- at startup, if `CS_DEBUGGED` is absent and no-sandbox is available, iSH spawns
  a child copy of itself with `--ish-arm64-jit-trace-me`; the child calls
  `ptrace(PT_TRACE_ME)`, then the parent detaches and continues
- if `CS_DEBUGGED` is still absent, the app keeps the ARM64 JIT backend disabled
  and shows the existing JIT enablement alert

App-side JIT enablement:

- `iSH-ARM64` uses `app/AppARM64.xcconfig`, which selects
  `app/iSH-ARM64-ad-hoc.entitlements`.
- `app/iSH-ARM64-ad-hoc.entitlements` carries `get-task-allow` plus the ARM64
  app group/font entitlements. The regular `app/iSH.entitlements` is unchanged.
- In-app Settings adds an `ARM64 JIT` section with `Enable ARM64 JIT` and
  `Enable Fast JIT` switches.
- The app applies preferences through C runtime setters rather than host
  environment variables:
  - `cpu_set_arm64_jit_enabled()`
  - `arm64_jit_set_fast_enabled()`
- When JIT is enabled at startup, foreground, or switch-on, the app probes the
  actual executable-memory path with `arm64_jit_probe_executable_memory()`.
  If the probe fails, iSH keeps the preference enabled but temporarily forces
  the threaded backend and presents an alert.
- Recovery mode includes direct `Disable JIT` navigation action plus the same
  normal ARM64 JIT/Fast JIT static-table section. Use recovery mode to clear a
  persisted bad JIT setting before exiting recovery.
- The alert offers:
  - `Switch Off JIT`, which clears the preference and reapplies threaded mode.
  - `Try TrollStore`, which opens
    `apple-magnifier://enable-jit?bundle-id=<bundle id>`.
- Final proof still requires a TrollStore-installed device run or a
  debugger-enabled device run via StikDebug/AltJIT.

## Current Memory-Helper Direction

The intended memory-helper architecture is:

- emitted code calls family helper as a success-only operation
- family helper computes effective address and performs typed access
- shared page helper owns:
  - TLB hit/miss handling
  - spill/reload around miss
  - permission failure / page fault publication
  - fragment exit on fault
- shared page helper ABI uses `x16` for `access_kind` (`0=read`, `1=write`);
  `x3` is the caller helper-frame unwind byte count used when the shared helper
  exits the fragment directly on fault.
- Do not pass shared-helper metadata through `x4-x15`. Those registers may hold
  cached guest GPRs at the fault-spill frontier. Clobbering them before the
  shared helper can publish stale or wrong guest state.

The ABI is documented in:

- [/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64/helpers.S](/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64/helpers.S)

When changing this architecture, update both that file and this one.

Current indexed scalar-pair rule:

- Offset, pre-index, and post-index scalar pair load/store may use the emitted
  TLB-hit fast path.
- Scalar pair stores may use the emitted fast path even when `Rt`/`Rt2` are not
  cached in host registers; the fast path materializes uncached source operands
  from canonical CPU state and treats source register 31 as zero.
- Base-overlap writeback forms stay on the existing C helper path until their
  constrained-unpredictable behavior is deliberately modeled.
- If the emitted fast path falls back to the C helper for a writeback form, it
  must reload the cached base/SP register from `cpu` after helper success.
  Otherwise the helper updates canonical CPU state but the fragment continues
  with a stale cached base register.
- Generic pair fallback helpers that read operands from canonical `cpu->regs`
  must be entered through a full-spill/continue wrapper. Do not use a
  success-only C helper wrapper for fallback pair forms when source operands may
  be live only in cached host registers.
- Scalar unscaled `imm9` loads/stores and scalar register-offset loads/stores
  should use emitted TLB-hit fast paths when base/offset/value registers are
  cached or can be materialized from canonical CPU state. Register-offset
  address emission supports common `UXTW`, `LSL`, `SXTW`, and `SXTX` option
  forms; do not hand-write bitfield encodings for this path after the previous
  `UXTW` constant accidentally emitted `lsl #32`.
- For scalar register-offset stores, compute the effective address before
  materializing the store value in `x3`; address calculation uses `x3` as a
  temporary for scaled offsets.
- Scalar pair live helpers use emitted TLB-hit fast paths and route valid-form
  TLB misses through the shared page helper. Invalid/unmodeled pair forms still
  fall back to the C helper.
- Exclusive/acquire-release memory is split by semantic risk. Common
  single-register `LDXR`/`LDAXR` TLB-hit cases are lowered inline and publish
  `cpu->excl_addr`/`cpu->excl_val`. Common single-register `STXR`/`STLXR`
  TLB-hit cases are also lowered inline with host `CAS`/`CASAL`, preserve
  NZCV, clear `cpu->excl_addr`, and write the status result to a cached `Rs` or
  canonical CPU state. Acquire/release non-exclusive forms and pair-exclusive
  forms still go through the C helper.

## Current Fragment Lookup Direction

Runtime dispatch and JIT-to-JIT cross-fragment transfers now first probe a
compact direct-mapped exact-PC target cache, then a 2-way range fragment TLB,
then a compact per-code-page fragment list. The PC target cache has 256 entries;
each entry is 64 bytes, so the whole first-level cache is 16 KiB. It is indexed
by `(pc >> 2) & 255`, exact-PC checked, and `invalidate_gen` guarded. It is
demand-filled after an actual lower-level lookup. Do not preload every
instruction in a published fragment into this cache; that pollutes the
first-level cache and causes massive self-eviction.

`arm64_jit_state` also owns a direct-mapped array of lazily allocated code-page
maps. Each code-page map stores a linked list of fragments that overlap the
guest code page. A fragment-list node records:

- guest PC range
- owning JIT block
- target fragment entry, spill, reload, and light-spill snippets

The helper computes `index = (pc - block->start_pc) >> 2`, then targets the
fragment-local dispatch-table slot at
`block->code_rx + block->entry_thunks_offset + index * 4`. Each slot is a host
`b` to the corresponding emitted guest-instruction body. This stores the
per-instruction target offset in icache instead of loading
`insn_host_offsets[index]` from dcache on hot JIT-to-JIT transfers.
`insn_host_offsets[]` remains emitter/debug metadata for local branch patching,
dumps, and C-side validity checks. The list scan is bounded by
`ARM64_JIT_CODE_PAGE_FAST_SCAN_LIMIT`; failures fall back to the slow C helper.

The old exact entry hash/cache and per-page block-list scan remain as C-side
fallbacks. The old fragment TLB data structure is now the second-level fast
range cache again, populated when fragments are published and probed by the
JITABI fast helpers before the compact code-page fragment list.

Important invariants for future JIT-to-JIT transfer work:

- A cached entry is valid only if the block is not jetsam, has executable code,
  and the entry index still maps to the requested guest PC.
- Guest page invalidation marks affected blocks jetsam and increments
  `invalidate_gen`; fast caches must either check that generation or be cleared
  under the same invalidation path.
- Superseding an older contained block also bumps `invalidate_gen`; compact
  page-map fragment nodes are removed by exact block ownership so removing an
  older block cannot erase a newer fragment.
- Direct-mapped code-page-map slot collisions free the old fragment list and
  bump `invalidate_gen`, which invalidates stale L1/L2 fast-cache entries.
- Page-list membership uses `end_pc - 1` because fragment `end_pc` is exclusive.
- Same-fragment jumps use fragment-local guest PC to host offset mapping.
  Cross-fragment jumps use the PC target cache first, then the 2-way fragment
  TLB, then the compact code-page fragment list to resolve the target block and
  exact dispatch-table slot, then light-spill source cached registers, update
  the runtime block/spill/reload/light-spill state, and enter the target
  fragment JIT-to-JIT light entry. Fast-cache metadata must advertise the target
  light-entry snippet, not a target resolver snippet, because the fast path has
  already resolved `rt->entry_target`.
- Non-self local backward branches may stay inside fragments for performance.
  Exact self-branches route through the helper path. If the local-fixup table is
  full, the emitter must fall back to the helper path instead of emitting an
  unpatched placeholder branch; an unpatched `b #0` is a host self-loop bug.
- Do not emit timer/verifier safepoints on local backedges in plain JIT. Verifier
  mode already inserts `brk` sites for instruction-by-instruction observation,
  and plain JIT uses the outer block-entry timer check when entering fragments.
  Per-backedge inline checks were measurable in libc string loops.
- Large soft-pressure fragments can make host branch distances much larger
  than guest branch distances. Local fixup patching must range-check the host
  immediate width for each branch class (`B`, `B.cond`, `CBZ/CBNZ`,
  `TBZ/TBNZ`) and disable/retry that individual local fixup on overflow. Do
  not silently truncate host immediates; a truncated `TBNZ` was observed to
  branch into a restore/epilogue island.
- Fragment splitting should treat indirect branches, returns, exceptions, and
  unsupported instructions as boundary candidates, not hard boundaries. The
  scanner keeps moving until it hits code/address-space boundary, max
  instruction count, or register-cache overflow. Overflow currently cuts at the
  latest candidate boundary, or at the current instruction if no boundary has
  been seen. A softer overflow policy that kept scanning until a later boundary
  caused bounded `/bin/echo hello` and `/sbin/apk stats` runs to time out in
  this workspace; do not reintroduce it without a verifier-frontier fix.
- Do not add a simple "cut at candidate boundary after N instructions"
  threshold without measuring full workload dispatch count. A 128-instruction
  candidate-boundary experiment reduced `/sbin/apk stats` emitted code from
  about 55 MiB to about 51.5 MiB, but increased block dispatches from about
  738k to about 837k and worsened total guest time by about 232 ms.
- The emitter uses a memory-efficient three-pass shape:
  - scan/analyze and build the fragment GPR map
  - dry-run the normal emitter path to estimate exact host code size
  - mmap a host-page-rounded code buffer and emit the real executable bytes
  `block->code_size` is the actual emitted byte range used for dumps and host
  PC checks. `block->code_map_size` is the mmap length used for unmap and
  footprint accounting. Helper-profile output reports both
  `code_bytes` and `code_map_bytes`.
- Guest `MEM_WRITE` invalidation should be targeted to pages with live JIT
  blocks. `arm64_jit_invalidate_page()` scans the per-page block lists first and
  only bumps `invalidate_gen`, clears code-page maps, and jetsams blocks when
  the written page actually owns live compiled code. Do not reintroduce a global
  generation bump for ordinary data writes; it poisons PC target/code-page-map
  fast caches without indicating self-modifying code.
- Before taking the JIT state lock for a guest write invalidation,
  `arm64_jit_invalidate_page()` probes a conservative sticky executable-page
  hint bitset. A clear bit means no compiled block has ever marked that hash
  bit, so the invalidation can return without locking. A set bit is only a
  maybe-hit and must still use the authoritative per-page block-list scan. Never
  make this hint an exact direct-mapped page tag unless collisions are handled
  without false negatives; missing a real code-page write would leave stale JIT
  code executable.
- JIT code memory is allocated through compile-only slabs. A slab is writable
  only while the current compile batch is emitting, then `mprotect`ed RX once
  and sealed; sealed slabs must never be made writable again. Each block still
  owns its metadata and invalidates independently; a slab is unmapped only when
  all blocks allocated from it have been discarded. Helper-profile output
  distinguishes per-block requested `code_map_bytes` from actual reserved
  `code_slab_bytes` and `code_slabs`.
- Compile misses batch multiple forward fragments into compile-only slabs until
  the estimated code bytes fill the next host page by about 80%, the scan hits a
  likely function/code boundary, or the batch size limits are reached. If an
  active slab lacks room for a later block because real emission exceeded the
  dry-run estimate, allocation starts another writable slab in the same batch;
  batch finish seals all unsealed slabs.
- Already compiled block starts are also not absolute hard stops when the new
  fragment can safely merge and later supersede the contained block. A merge is
  safe when the combined contiguous range still fits `ARM64_JIT_MAX_INSNS`.
  Combined GPR use may exceed `ARM64_JIT_MAX_ALLOCATABLE_GPRS`; the emitter
  caches the most useful registers and leaves the rest uncached.
- Do not broadly lower uncached DP register/immediate operations by simply
  loading CPU slots into scratch registers and storing back. A first attempt at
  this exposed SP/ZR semantic traps in logical and add/sub forms and broke
  loader relocation/RELRO before `/bin/echo hello` printed. Reintroduce such
  lowering one family at a time under verifier, with explicit SP-vs-ZR rules
  and exact stdout checks.

### Code-Page Map Probe State

Mixed-cache allocation, population, runtime exposure to JIT helpers, and
cross-fragment handoff through `_arm64_jit_helper_branch_reg_fast_jitabi` and
`_arm64_jit_helper_control_transfer_fast_jitabi` are default-enabled.
The helpers handle:

- same-fragment `BR`/`RET` by branching directly to the current fragment body.
  Same-fragment `BLR` is still routed through the fragment-entry path until LR
  publication has a safe dedicated ABI.
- cross-fragment control transfer by probing L1 exact-PC cache, L2 2-way
  fragment TLB, and L3 compact code-page fragment list, light-spilling source
  cached state, updating runtime block/spill/reload/light-spill state and
  `rt->entry_target`, then entering the target fragment JIT-to-JIT light entry
- miss/failure by restoring touched JIT state, full-spilling source state, and
  falling back to the normal C branch-register helper

Important lessons from the direct-handoff probe:

- Fragments are expected to be contiguous 4-byte guest instruction ranges. The
  fallback target fragment entry resolver relies on that invariant and computes
  `index = (target_pc - block->start_pc) >> 2` before selecting the dispatch
  table slot. Do not switch this to a linear `insn_pcs[]` search unless
  fragment layout becomes non-contiguous.
- The same-fragment branch-register fast helper uses the same contiguous
  fragment invariant for O(1) target lookup. Keep it aligned with the entry
  resolver if the fragment layout invariant changes.
- C-side runtime fallback lookup also uses the contiguous fragment invariant in
  `arm64_jit_find_insn_index()`. Per-page block-list scans remain acceptable as
  a slow fallback, but the hot path should hit the code-page instruction map.
- A naive same-fragment `BLR` helper-local LR publication attempt made
  `/sbin/apk stats` exit successfully with empty stdout. Do not reintroduce that
  shape; it needs a dedicated ABI that can update live cached LR without
  clobbering other cached guest registers.
- The resolver fail path must publish `rt->resume_pc` and `cpu->pc` as the
  requested target PC before returning `INT_NONE`; otherwise a failed resolver
  can loop on stale dispatch state.
- `BLR` must publish `cpu->regs[30] = guest_pc + 4` before target-fragment
  reload. Same-fragment `BLR` is still routed through fallback unless the helper
  can update a live cached LR register safely.
- `arm64_jit_emit_spill_cached_state()` is a full architectural sync: cached
  GPRs, guest SP, NZCV/FPCR/FPSR, and all 32 vector registers. It is not a
  lightweight cached-register transfer primitive.
- Do not overload `spill_state_fn` for light transfers. Existing helper/fault
  paths depend on it being a full architectural spill. JIT-to-JIT cache hits use
  the separate `light_spill_state_fn`, which publishes cached GPRs, guest SP,
  and NZCV only. It must not publish FPCR/FPSR or vector registers.
- Fragment entry is split by caller ABI. C/runtime dispatch enters through the
  full C entry, which emits the normal fragment prologue and reloads GPR,
  NZCV, FPCR/FPSR, and all vector registers from canonical CPU state. JIT-to-JIT
  fast transfers enter through the light entry, which assumes the original
  fragment frame is still active and reloads only GPRs, guest SP, and NZCV
  before branching to `rt->entry_target`.
- Cross-fragment fast helpers must not use the full fragment epilogue/prologue
  pair. Restoring host q8-q15 at a JIT-to-JIT boundary would clobber live guest
  vector state before the target fragment runs.
- The fragment-TLB entry stores page tag, valid range, target block, target
  JIT-to-JIT light entry, target spill/reload snippets, and target light-spill
  snippet.
  It is the second-level fast path between the exact-PC L1 cache and compact
  code-page fragment-list scan.

Branch-fast counters are included in helper profile output:

```bash
meson configure build-arm64-release -Darm64_jit_perf_counters=true
ninja -C build-arm64-release
timeout 30s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_HELPER_PROFILE=1 ISH_ARM64_JIT_HELPER_PROFILE_INTERVAL=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /root/cbench_lite_arm64
```

The `branch_fast` line reports:

- `same_fragment`: direct same-fragment `BR`/`RET` hits
- `fragment_tlb`: second-level 2-way range-fragment cache hits
- `misses`: fallback to the C branch-register helper

The `branch_fast_l1` and `control_fast_l1` lines split cross-fragment fast hits
between the first-level PC target cache and the compact code-page fragment-list
lookup. The `fragment_tlb` counter is reported separately. When diagnosing the
PC cache, compare `pc_target` against `page_map` and inspect
`pc_target_cache_overwrite_top*`. High overwrite concentration at a handful of
indices indicates direct-mapped conflict churn; high overwrite volume across
many indices can indicate accidental bulk preloading.

These counters are useful for diagnosis but add writes on fast paths, so do not
enable `arm64_jit_perf_counters` or use profile timings as benchmark timings
for normal performance comparisons. Disable with:

```bash
meson configure build-arm64-release -Darm64_jit_perf_counters=false
ninja -C build-arm64-release
```

## Best Practices

- Start with `/bin/echo hello` under verifier before using `cbench_lite`.
- Use one bounded reproducer at a time.
- If a helper becomes non-leaf, verify `x30` preservation immediately.
- If a helper starts reusing `x4-x15`, save/restore them explicitly or redesign
  the register use.
- If a dump shows helper-heavy code shape, inspect both:
  - emitted fragment
  - family helper
  - shared page helper
- Prefer exact frontier logs over intuition.

## Maintenance Rule

Update this file whenever any of these change:

- build command
- build directory
- fakefs path
- JIT backend selector
- verifier env vars
- dump workflow
- trace workflow
- current best-practice bounded timeout values
