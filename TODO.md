# TODO

Track active ARM64 JIT work here. Remove items when finished, and add subitems
when a task needs to be split.

## Fragment Cache And JIT Fast Paths

- Continue hardening the default branch-reg 3-tier path.
  - Same-fragment `BR`/`RET` now jumps directly without spill.
  - Cross-fragment first probes the 256-entry exact-PC target cache, then the
    2-way fragment TLB, then the compact code-page fragment list.
  - Cross-fragment fast hits light-spill the source cached GPR/SP/NZCV state,
    update runtime target metadata, and enter the target fragment's JIT-to-JIT
    light entry. Misses full-spill before C helper fallback.
  - Fragment entry resolution assumes contiguous 4-byte guest instruction ranges
    and uses O(1) `(target_pc - start_pc) >> 2` indexing into a host `b`
    dispatch-table prelude.
  - Re-test `/sbin/apk update` after broader instruction coverage changes.
- Keep same-fragment branch-reg target lookup O(1).
  - Current helper assumes contiguous fragment layout and targets
    `entry_thunks_offset + ((target_pc - start_pc) >> 2) * 4`.
  - C runtime fallback uses the same O(1) index in `arm64_jit_find_insn_index()`.
- Complete indirect branch fast paths.
  - `BR`: default same-fragment and mixed-cache fast paths exist; keep verifier
    coverage broad.
  - `BLR`: default cross-fragment fast path exists; same-fragment direct path
    still needs a safe dedicated LR publication ABI. A naive helper-local
    implementation made `/sbin/apk stats` exit successfully with empty stdout.
  - `RET`: default same-fragment and mixed-cache fast paths exist; keep verifier
    coverage broad.
- Revisit PC target cache sizing/associativity after more measurements.
  - Current first-level cache is direct-mapped, 256 entries, 16 KiB total,
    indexed by `(pc >> 2) & 255`.
  - PC target cache is demand-filled from actual lower-level target lookups; do
    not bulk-fill it while publishing all fragment instructions.
  - Re-measure direct-mapped conflict churn now that L2 range-fragment TLB and
    L3 compact page-list lookup are both active.
- Add cross-fragment register-map connector snippets.
  - For fallthrough and other hot cross-fragment jumps, generate a connector
    that transforms the source cached-GPR map into the target cached-GPR map
    with in-place register moves, cycle-safe temporary handling, and only the
    needed canonical CPU loads/stores.
  - This should be semantically equivalent to light-spill plus light-reload,
    but avoid spilling/loading common guest GPRs that can be permuted directly.
- Reduce remaining `/sbin/apk stats` slow C-helper volume.
  - Current plain JIT `apk stats` completes and prints stats again under a
    bounded run. Quiet verifier still has a separate mismatch frontier at
    `start_pc=0xefcbc9ac`, `trapped insn=0x29405414`, with `x20/x21` differing
    after a pair load sequence; keep this as the next correctness target.
  - The dominant observed helper volume after memory fixes is pure DP helper
    traffic, especially shifted logical/add/sub and two-source variable shifts
    in zlib/musl loops.
  - Reintroduce uncached DP lowering narrowly, one family at a time, with exact
    SP-vs-ZR semantics. Do not repeat the broad scratch-load/storeback attempt;
    it corrupted loader state and made `/bin/echo hello` print no `hello`.
  - Current memory fast paths cover the hot scalar regoff forms, SIMD imm9
    signed-offset stores, single-register LD/ST-exclusive TLB hits, and scalar
    pair valid-form TLB misses via the shared page helper.
  - Scalar pair stores no longer require both source registers to be cached;
    uncached source operands are materialized from canonical CPU state, and
    `Rt/Rt2 == 31` is materialized as zero.
  - Latest profiled C-helper counts for `/sbin/apk stats` after the
    scalar-pair uncached-source store change:
    `ldr_uimm=1561`, `imm9=1095`, `regoff=21796`, `pair=17666`, `excl=476`,
    `simd=1790`.
  - Remaining pair C-helper volume is mostly invalid/unmodeled forms such as
    vector pairs and base-overlap writeback pairs that still require full
    semantics. Non-overlap writeback stack pairs may use generic fallback, but
    that path must full-spill live cached GPRs before C/helper execution.
- Investigate `/sbin/apk stats` broad-callgraph overhead next.
  - Syscall-segment profiling currently shows about `738k` JIT blocks, `723k`
    control transfers, `44k` C helpers, `8.1k` compiled blocks, about `55 MiB`
    emitted code, and about `68 ms` compile time for one run.
  - The largest observed segment regression (`index=7089`, syscall 215) had
    only `20` C helpers but `499` block/control transfers, `252` compiled
    blocks, and about `1.6 MiB` emitted code. This points at control/code-size
    overhead, not memory C-helper volume.
  - A generic "cut at candidate boundary after 128 instructions" experiment
    reduced emitted code to about `51.5 MiB` but increased dispatches to about
    `837k` and worsened total `apk stats` guest time by about `232 ms`.
    Do not reintroduce that threshold blindly.
  - Representative dumps show repeated inline TLB sequences for stack/global
    accesses and branch-register miss epilogue islands after indirect stubs.
    Next candidate work: shared slow-exit snippets or a slimmer terminal
    branch-reg/control fallback shape that does not duplicate full restore
    islands after every terminator.
- Clean up helper ABI structure and naming.
  - Separate dedicated JITABI fast helpers, light transfer helpers, and slow
    fallback helpers more clearly in `helpers.S`.
  - Keep assembly macros zero-cost where they are pure code-generation
    structure.
