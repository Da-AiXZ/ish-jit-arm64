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
  fields, then enter the target fragment resolver
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

## Runtime Bottleneck Profiling

Use syscall-segment profiling to compare guest execution time between syscall
boundaries. This is useful when a complete workload is slower under JIT but the
syscall count and stdout are correct.

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

With `arm64_jit_perf_counters=true`, helper-profile output also includes:

- `branch_fast same_fragment/fragment_tlb/misses` for `BR`/`BLR`/`RET`
- `control_fast dispatch/b_cond/cbz/tbz=same_fragment/fragment_tlb/misses`
  for fixed-target and conditional control transfers

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

```bash
python3 -u tools/render_arm64_jit_dump.py \
  /private/tmp/fragment.log \
  /Users/zizhengguo/scratch/ish-arm64/benchmark/assets/cbench_lite_arm64 \
  0xeffdd000 \
  > /private/tmp/fragment.rendered
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

## Current Memory-Helper Direction

The intended memory-helper architecture is:

- emitted code calls family helper as a success-only operation
- family helper computes effective address and performs typed access
- shared page helper owns:
  - TLB hit/miss handling
  - spill/reload around miss
  - permission failure / page fault publication
  - fragment exit on fault
- shared page helper ABI uses `x4` for `access_kind` (`0=read`, `1=write`);
  `x3` remains family-specific, such as a scalar store value or load return
  selector.

The ABI is documented in:

- [/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64/helpers.S](/Users/zizhengguo/scratch/ish-arm64/jit/guest-arm64/helpers.S)

When changing this architecture, update both that file and this one.

Current indexed scalar-pair rule:

- Offset, pre-index, and post-index scalar pair load/store may use the emitted
  TLB-hit fast path.
- Base-overlap writeback forms stay on the existing C helper path until their
  constrained-unpredictable behavior is deliberately modeled.
- If the emitted fast path falls back to the C helper for a writeback form, it
  must reload the cached base/SP register from `cpu` after helper success.
  Otherwise the helper updates canonical CPU state but the fragment continues
  with a stale cached base register.

## Current Fragment Lookup Direction

Runtime dispatch now has a direct-mapped PC-to-entry cache in
`arm64_jit_state`, keyed from `pc >> 2`, with entries guarded by
`invalidate_gen`. The slow covering-block fallback uses the existing per-guest
page block lists instead of scanning every block hash bucket.

Important invariants for future JIT-to-JIT transfer work:

- A cached entry is valid only if the block is not jetsam, has executable code,
  and the entry index still maps to the requested guest PC.
- Guest page invalidation marks affected blocks jetsam and increments
  `invalidate_gen`; fast caches must either check that generation or be cleared
  under the same invalidation path.
- Superseding an older contained block also bumps `invalidate_gen`, because the
  JIT-side fragment TLB only has the generation guard and cannot cheaply test
  `block->is_jetsam` before jumping.
- Page-list membership uses `end_pc - 1` because fragment `end_pc` is exclusive.
- Same-fragment jumps should use fragment-local guest PC to host offset mapping.
  Cross-fragment jumps must account for different cached-register maps before
  branching into the destination body.
- Non-self local backward branches may stay inside fragments for performance.
  Exact self-branches route through the helper path. If the local-fixup table is
  full, the emitter must fall back to the helper path instead of emitting an
  unpatched placeholder branch; an unpatched `b #0` is a host self-loop bug.
- Fragment splitting should treat indirect branches, returns, exceptions, and
  unsupported instructions as boundary candidates, not hard boundaries. The
  scanner keeps moving until it hits code/address-space boundary, max
  instruction count, or register-cache overflow. On overflow or max scan, cut
  at the latest candidate boundary if it is in the recent half of the scan;
  otherwise materialize the whole scanned range.
- Already compiled block starts are also not absolute hard stops when the new
  fragment can safely merge and later supersede the contained block. A merge is
  safe only when the combined contiguous range still fits
  `ARM64_JIT_MAX_INSNS` and the combined analyzed GPR-use mask does not exceed
  `ARM64_JIT_MAX_ALLOCATABLE_GPRS`.

### Fragment TLB Probe State

Fragment-TLB allocation, population, runtime exposure to JIT helpers, and
cross-fragment branch-register handoff through
`_arm64_jit_helper_branch_reg_fast_jitabi` are default-enabled.
The helper handles:

- same-fragment `BR`/`RET` by branching directly to the current fragment body.
  Same-fragment `BLR` is still routed through the fragment-entry path until LR
  publication has a safe dedicated ABI.
- cross-fragment `BR`/`BLR`/`RET` by probing the fragment TLB, light-spilling
  source cached state, updating runtime block/spill/reload/light-spill state,
  then entering the target fragment resolver
- miss/failure by restoring touched JIT state, full-spilling source state, and
  falling back to the normal C branch-register helper

Important lessons from the direct-handoff probe:

- Fragments are expected to be contiguous 4-byte guest instruction ranges. The
  target fragment entry resolver relies on that invariant and computes
  `index = (target_pc - block->start_pc) >> 2` before indexing
  `insn_host_offsets[]`. Do not switch this to a linear `insn_pcs[]` search
  unless fragment layout becomes non-contiguous.
- The same-fragment branch-register fast helper uses the same contiguous
  fragment invariant for O(1) target lookup. Keep it aligned with the entry
  resolver if the fragment layout invariant changes.
- C-side runtime fallback lookup also uses the contiguous fragment invariant in
  `arm64_jit_find_insn_index()`. Per-page block-list scans remain acceptable as
  a slow fallback because code pages should have only a small number of
  fragments.
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
  and NZCV; it also publishes FPCR/FPSR and vector registers for fragments that
  may dirty host FP/SIMD state.
- The fragment-TLB entry stores page tag, valid range, target block, target
  entry resolver, target spill/reload snippets, and target light-spill snippet.
  The assembly probe assumes the entry size is 128 bytes.

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
- `fragment_tlb`: fragment-TLB cross-fragment handoff hits
- `misses`: fallback to the C branch-register helper

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
