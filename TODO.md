# TODO

Track active ARM64 JIT work here. Remove items when finished, and add subitems
when a task needs to be split.

## Fragment Cache And JIT Fast Paths

- Continue hardening the default branch-reg 3-tier path.
  - Same-fragment `BR`/`RET` now jumps directly without spill.
  - Cross-fragment first probes the 256-entry exact-PC target cache, then the
    2-way fragment TLB, then the compact code-page fragment list. Hits use
    `light_spill_state_fn`, update `rt->entry_target` to the exact dispatch
    table slot, then enter the target fragment shared-entry snippet.
  - Fragment entry resolution assumes contiguous 4-byte guest instruction ranges
    and uses O(1) `(target_pc - start_pc) >> 2` indexing into a host `b`
    dispatch-table prelude.
  - Misses now full-spill before C helper fallback.
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
- Reduce remaining `/sbin/apk stats` slow C-helper volume.
  - Latest profile still shows many C-helper fallbacks in memory families,
    especially `regoff`, `excl`, and `imm9`.
  - Full quiet verifier for `/sbin/apk stats` still exceeds a 30s bound without
    a mismatch; use smaller frontiers or longer bounded verifier runs when
    proving correctness.
- Clean up helper ABI structure and naming.
  - Separate dedicated JITABI fast helpers, light transfer helpers, and slow
    fallback helpers more clearly in `helpers.S`.
  - Keep assembly macros zero-cost where they are pure code-generation
    structure.
