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

## Experimental Branch-Reg Fast Probe

`ISH_ARM64_JIT_BRANCH_REG_FAST=1` enables the experimental JIT-side
branch-register resolver. It is intentionally opt-in and should not be treated
as the default path until broader verifier coverage is clean.

```bash
timeout 10s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_BRANCH_REG_FAST=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /bin/echo hello \
  > /private/tmp/branch_fast_echo.stdout 2> /private/tmp/branch_fast_echo.stderr
```

Extra fallback logging is separately gated by:

```bash
ISH_ARM64_JIT_BRANCH_REG_FAST_DEBUG=1
```

`ISH_ARM64_JIT_BRANCH_REG_TRACE=1` logs every runtime branch-register helper
resolution, including the source PC, target, link registers, and JIT debug
slots. This is very verbose; use it only with a narrow bounded repro.

```bash
timeout 20s env ISH_ARM64_BACKEND=arm64_jit ISH_ARM64_JIT_BRANCH_REG_TRACE=1 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_branch_trace.stdout 2> /private/tmp/apk_branch_trace.stderr
```

Important ABI lesson from the first probe: if an experimental JIT helper may
fall back through a fragment spill snippet, it must restore all live JIT state
that the spill snippet reads before calling the spill snippet. In practice that
means restoring any touched cached-register host registers such as `x4` and
restoring `NZCV` before fallback spill.

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

## Direct-Call Debugging

Direct fixed-target `BL` is currently emitted as a conservative nested JIT call
in plain JIT mode. Verifier mode keeps the older terminate-to-runtime path so
single-step comparison remains meaningful.

Useful bounded profiling knobs:

```bash
timeout 15s env ISH_ARM64_BACKEND=arm64_jit \
  ISH_ARM64_JIT_DIRECT_CALL_PROFILE=50000 \
  ./build-arm64-release/ish -f ./build/alpine-arm64-fakefs /sbin/apk stats \
  > /private/tmp/apk_call_profile.stdout 2> /private/tmp/apk_call_profile.stderr
```

`ISH_ARM64_JIT_DIRECT_CALL_PROFILE=N` logs aggregate direct-call counts every
`N` direct calls:

- `returned`: callee returned to the expected guest LR, so caller reloaded and
  continued in-fragment.
- `nonreturn`: callee completed with `INT_NONE` but at a different PC, so the
  caller exited to resume dispatch there.
- `interrupt`: callee hit an interrupt boundary such as timer/syscall/fault.

`ISH_ARM64_JIT_NESTED_NO_TIMER=1` is an opt-in probe that skips timer exits
while inside nested direct-call execution. It is for diagnosis only; do not make
it the default without revisiting scheduling/starvation behavior.

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
- Same-fragment jumps should use fragment-local guest PC to host offset mapping.
  Cross-fragment jumps must account for different cached-register maps before
  branching into the destination body.
- Non-self local backward branches may stay inside fragments for performance.
  Exact self-branches route through the helper path. If the local-fixup table is
  full, the emitter must fall back to the helper path instead of emitting an
  unpatched placeholder branch; an unpatched `b #0` is a host self-loop bug.

### Fragment TLB Probe State

`ISH_ARM64_JIT_FRAGMENT_TLB_FAST=1` currently enables fragment-TLB allocation,
population, and runtime exposure to JIT helpers. The direct cross-fragment
branch in `_arm64_jit_helper_branch_reg_fast_jitabi` is intentionally disabled
behind an unconditional branch while the light JIT-to-JIT enter/exit ABI is
unfinished.

Important lesson from the first direct-handoff probe:

- A RET target can be a return into a caller frame that is currently suspended
  inside the C-managed direct-call helper. Directly jumping to that caller
  fragment creates another caller fragment frame instead of returning to the
  suspended helper continuation.
- Any future direct cross-fragment transfer must make fragment-boundary state
  explicit: target block, target spill/reload snippets, target entry resolver,
  and whether the source context is top-level dispatch or a nested helper
  continuation.
- The fragment-TLB entry currently stores page tag, valid range, target block,
  target entry resolver, and target spill/reload snippets. The assembly probe
  assumes the entry size is 64 bytes.

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
