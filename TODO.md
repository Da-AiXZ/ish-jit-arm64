# TODO

Track active ARM64 JIT work here. Remove items when finished, and add subitems
when a task needs to be split.

## Fragment Cache And JIT Fast Paths

- Continue hardening the default branch-reg 3-tier path.
  - Same-fragment `BR`/`RET` now jumps directly without spill.
  - Cross-fragment cache hits now use `light_spill_state_fn`, then target
    fragment entry.
  - Fragment entry resolution assumes contiguous 4-byte guest instruction ranges
    and uses O(1) `(target_pc - start_pc) >> 2` indexing.
  - Misses now full-spill before C helper fallback.
  - Re-test `/sbin/apk update` after broader instruction coverage changes.
- Keep same-fragment branch-reg target lookup O(1).
  - Current helper assumes contiguous fragment layout and indexes
    `insn_host_offsets[]` with `(target_pc - start_pc) >> 2`.
  - C runtime fallback uses the same O(1) index in `arm64_jit_find_insn_index()`.
- Complete indirect branch fast paths.
  - `BR`: default same-fragment and fragment-TLB fast paths exist; keep
    verifier coverage broad.
  - `BLR`: default cross-fragment fast path exists; same-fragment direct path
    still needs a safe dedicated LR publication ABI. A naive helper-local
    implementation made `/sbin/apk stats` exit successfully with empty stdout.
  - `RET`: default same-fragment and fragment-TLB fast paths exist; keep
    verifier coverage broad.
- Clean up helper ABI structure and naming.
  - Separate dedicated JITABI fast helpers, light transfer helpers, and slow
    fallback helpers more clearly in `helpers.S`.
  - Keep assembly macros zero-cost where they are pure code-generation
    structure.
