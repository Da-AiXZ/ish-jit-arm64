# TODO

Track active ARM64 JIT work here. Remove items when finished, and add subitems
when a task needs to be split.

## Fragment Cache And JIT Fast Paths

- Continue hardening the default branch-reg 3-tier path.
  - Same-fragment `BR`/`RET` now jumps directly without spill.
  - Cross-fragment cache hits now use `light_spill_state_fn`, then target
    fragment entry.
  - Misses now full-spill before C helper fallback.
  - Re-test `/sbin/apk update` after broader instruction coverage changes.
- Improve target fragment entry resolution.
  - Preserve support for arbitrary valid in-fragment target PCs if future
    fragments become non-contiguous. The current resolver uses O(1)
    `(target_pc - start_pc) >> 2` indexing, which assumes contiguous 4-byte
    guest instruction layout.
- Audit fragment-cache invalidation.
  - Ensure all guest code invalidation marks affected blocks jetsam.
  - Ensure `invalidate_gen` is checked by every JIT-side cache consumer.
  - Ensure no JIT-side path can jump to stale or unmapped code.
- Complete indirect branch fast paths.
  - `BR`: default same-fragment and fragment-TLB fast paths exist; keep
    verifier coverage broad.
  - `BLR`: default cross-fragment fast path exists; add same-fragment fast path
    only after LR cached-register publication is implemented.
  - `RET`: default same-fragment and fragment-TLB fast paths exist; keep
    verifier coverage broad.
- Clean up helper ABI structure and naming.
  - Replace vague `JITABI_WRAP1/2/3` usage with explicit wrapper categories.
  - Separate C ABI wrappers, JIT ABI helpers, light transfer helpers, and slow
    fallback helpers.
  - Keep assembly macros zero-cost where they are pure code-generation
    structure.
