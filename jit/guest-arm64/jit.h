#if defined(GUEST_ARM64) && defined(__aarch64__)

#ifndef ISH_JIT_GUEST_ARM64_JIT_H
#define ISH_JIT_GUEST_ARM64_JIT_H

#include <signal.h>
#include <setjmp.h>
#include <stdbool.h>
#include <stdint.h>

#include "emu/arch/arm64/decode.h"
#include "emu/cpu.h"
#include "emu/interrupt.h"
#include "emu/mmu.h"
#include "emu/tlb.h"
#include "kernel/task.h"
#include "util/list.h"
#include "util/sync.h"

#define ARM64_JIT_HASH_SIZE (1 << 10)
#define ARM64_JIT_PAGE_HASH_SIZE (1 << 10)
#define ARM64_JIT_ENTRY_CACHE_SIZE (1 << 12)
#define ARM64_JIT_FRAGMENT_TLB_SIZE (1 << 12)
#define ARM64_JIT_FRAGMENT_TLB_WAYS 2
#define ARM64_JIT_CODE_PAGE_MAP_SIZE (1 << 12)
#define ARM64_JIT_PC_TARGET_CACHE_SIZE 256
#define ARM64_JIT_CODE_PAGE_FAST_SCAN_LIMIT 32
#define ARM64_JIT_MAX_INSNS 1024
#define ARM64_JIT_INITIAL_INSN_CAP ARM64_JIT_MAX_INSNS
#define ARM64_JIT_SCAN_HARD_LIMIT ARM64_JIT_MAX_INSNS
#define ARM64_JIT_MAX_PC_MAP 2048
#define ARM64_JIT_MAX_FIXUPS 2048
#define ARM64_JIT_MAX_GPR_USES 6
#define ARM64_JIT_MAX_ALLOCATABLE_GPRS 18
#define ARM64_JIT_TARGET_NATURAL_BOUNDARY_INSNS 128
#define ARM64_JIT_MAX_VERIFY_SITES ARM64_JIT_SCAN_HARD_LIMIT

enum arm64_jit_host_role_reg {
    ARM64_JIT_HOST_CPU = 19,
    ARM64_JIT_HOST_TLB = 20,
    ARM64_JIT_HOST_CTX = 21,
    ARM64_JIT_HOST_GUEST_SP = 22,
};

enum arm64_jit_host_temp_reg {
    ARM64_JIT_HOST_TMP0 = 0,
    ARM64_JIT_HOST_TMP1 = 1,
    ARM64_JIT_HOST_TMP2 = 2,
    ARM64_JIT_HOST_TMP3 = 3,
    ARM64_JIT_HOST_HELPER0 = 16,
    ARM64_JIT_HOST_HELPER1 = 17,
};

enum arm64_jit_guest_reg_use_flags {
    ARM64_JIT_USE_READ = 1 << 0,
    ARM64_JIT_USE_WRITE = 1 << 1,
    ARM64_JIT_USE_SP = 1 << 2,
    ARM64_JIT_USE_ZR = 1 << 3,
};

struct arm64_jit_guest_reg_use {
    uint8_t reg;
    uint8_t flags;
};

struct arm64_jit_insn_info {
    enum arm64_insn_type type;
    uint8_t gpr_use_count;
    uint8_t reads_flags;
    uint8_t writes_flags;
    uint8_t accesses_memory;
    uint8_t terminates_fragment;
    struct arm64_jit_guest_reg_use gpr_uses[ARM64_JIT_MAX_GPR_USES];
};

struct arm64_jit_guest_reg_map {
    int8_t host_reg[31];
    int8_t guest_for_host[32];
    uint32_t use_count[31];
};

struct arm64_jit_pc_map {
    uint32_t host_offset;
    addr_t guest_pc;
};

struct arm64_jit_local_fixup {
    uint32_t branch_offset;
    addr_t branch_pc;
    addr_t target_pc;
    uint32_t kind;
};

struct arm64_jit_verify_site {
    uint32_t host_offset;
    addr_t guest_pc;
    uint32_t insn;
};

struct arm64_jit_block;
struct arm64_jit_code_slab;

struct arm64_jit_page_bucket {
    struct list blocks[2];
};

struct arm64_jit_block {
    addr_t start_pc;
    addr_t end_pc;
    bool unsupported;
    bool is_jetsam;
    bool disable_local_fixups;
    int terminal_interrupt;
    uint32_t insn_count;
    uint32_t insn_cap;
    addr_t *insn_pcs;
    uint32_t *insns;
    struct arm64_jit_insn_info *infos;
    struct arm64_jit_guest_reg_map gpr_map;
    struct list hash_chain;
    struct list page[2];
    struct arm64_jit_code_page_fragment *code_page_fragments[2];
    struct list jetsam;
    struct list entrypoints;
    uint8_t *code_rw;
    void *code_rx;
    void *spill_state_fn;
    void *reload_state_fn;
    uint32_t code_size;
    uint32_t body_code_size;
    uint32_t spill_code_offset;
    uint32_t reload_code_offset;
    uint32_t entry_thunks_offset;
    uint32_t code_map_size;
    uint32_t *insn_host_offsets;
    void **entry_code;
    void *c_entry_fn;
    void *jit_entry_fn;
    uint32_t pc_map_count;
    struct arm64_jit_pc_map pc_map[ARM64_JIT_MAX_PC_MAP];
    uint32_t verify_site_count;
    struct arm64_jit_verify_site verify_sites[ARM64_JIT_MAX_VERIFY_SITES];
    uint32_t fixup_count;
    struct arm64_jit_local_fixup fixups[ARM64_JIT_MAX_FIXUPS];
    uint32_t disabled_local_fixup_count;
    addr_t disabled_local_fixup_pcs[ARM64_JIT_MAX_FIXUPS];
    void *light_spill_state_fn;
    uint32_t light_spill_code_offset;
    struct arm64_jit_code_slab *code_slab;
    uint32_t code_slab_offset;
};

struct arm64_jit_entrypoint {
    addr_t pc;
    struct arm64_jit_block *block;
    uint16_t entry_index;
    struct list hash_chain;
    struct list block_chain;
};

struct arm64_jit_entry_cache_entry {
    addr_t pc;
    struct arm64_jit_block *block;
    uint16_t entry_index;
    unsigned invalidate_gen;
};

struct arm64_jit_fragment_tlb_entry {
    addr_t page_tag;
    addr_t start_pc;
    addr_t end_pc;
    unsigned invalidate_gen;
    struct arm64_jit_block *block;
    void *jit_entry_fn;
    void *spill_state_fn;
    void *reload_state_fn;
    void *light_spill_state_fn;
    uint64_t insert_serial;
    void *reserved[6];
};

struct arm64_jit_code_page_fragment {
    addr_t start_pc;
    addr_t end_pc;
    struct arm64_jit_block *block;
    void *jit_entry_fn;
    void *spill_state_fn;
    void *reload_state_fn;
    void *light_spill_state_fn;
    struct arm64_jit_code_page_fragment *next;
};

struct arm64_jit_code_page_map {
    page_t page_tag;
    unsigned invalidate_gen;
    uint32_t reserved;
    struct arm64_jit_code_page_fragment *fragments;
};
struct arm64_jit_pc_target_cache_entry {
    addr_t pc;
    unsigned invalidate_gen;
    uint32_t reserved;
    struct arm64_jit_block *block;
    void *jit_entry_fn;
    void *spill_state_fn;
    void *reload_state_fn;
    void *light_spill_state_fn;
    void *target_host;
};

struct arm64_jit_state {
    struct mmu *mmu;
    struct list *hash;
    size_t hash_size;
    struct list *entry_hash;
    size_t entry_hash_size;
    struct arm64_jit_entry_cache_entry *entry_cache;
    size_t entry_cache_size;
    struct arm64_jit_fragment_tlb_entry *fragment_tlb;
    size_t fragment_tlb_size;
    struct arm64_jit_code_page_map **code_page_maps;
    size_t code_page_map_size;
    struct arm64_jit_pc_target_cache_entry *pc_target_cache;
    size_t pc_target_cache_size;
    struct arm64_jit_page_bucket *page_hash;
    struct list jetsam;
    struct list code_slabs;
    struct arm64_jit_code_slab *active_code_slab;
    lock_t lock;
    wrlock_t jetsam_lock;
    unsigned invalidate_gen;
    bool code_batch_active;
    uint64_t fragment_tlb_insert_serial;
};

struct arm64_jit_runtime {
    struct cpu_state *cpu;
    struct tlb *tlb;
    struct arm64_jit_block *block;
    void (*spill_state_fn)(struct arm64_jit_runtime *rt);
    void (*reload_state_fn)(struct arm64_jit_runtime *rt);
    addr_t resume_pc;
    addr_t fault_pc;
    int exit_interrupt;
    uint64_t debug0;
    uint64_t debug1;
    uint64_t debug2;
    uint64_t debug3;
    void *entry_target;
    struct arm64_jit_fragment_tlb_entry *fragment_tlb;
    size_t fragment_tlb_size;
    unsigned invalidate_gen;
    void (*light_spill_state_fn)(struct arm64_jit_runtime *rt);
    struct arm64_jit_code_page_map **code_page_maps;
    size_t code_page_map_size;
    struct arm64_jit_pc_target_cache_entry *pc_target_cache;
    size_t pc_target_cache_size;
};

struct arm64_jit_tlb_profile {
    _Atomic uint64_t bench_integer_lookups;
    _Atomic uint64_t bench_integer_hits;
    _Atomic uint64_t bench_integer_misses;
};

extern struct arm64_jit_tlb_profile g_arm64_jit_tlb_profile;

struct arm64_jit_helper_profile_snapshot {
    uint64_t dispatch_blocks;
    uint64_t compile_blocks;
    uint64_t compile_insns;
    uint64_t compile_code_bytes;
    uint64_t compile_code_map_bytes;
    uint64_t compile_code_slab_bytes;
    uint64_t compile_code_slabs;
    uint64_t compile_ns;
    uint64_t c_helper_total;
    uint64_t c_dp_imm;
    uint64_t c_dp_reg;
    uint64_t c_ldr_uimm;
    uint64_t c_str_uimm;
    uint64_t c_simd_ldst_uimm;
    uint64_t c_simd_ldst_addr;
    uint64_t c_simd_ldst_multi;
    uint64_t c_ldst_imm9;
    uint64_t c_ldst_regoff;
    uint64_t c_ldst_pair;
    uint64_t c_ldst_excl;
    uint64_t c_system;
    uint64_t control_total;
    uint64_t control_dispatch;
    uint64_t control_branch_reg;
    uint64_t control_cbz_cbnz;
    uint64_t control_b_cond;
    uint64_t control_tbz_tbnz;
    uint64_t syscall;
    uint64_t unsupported;
    uint64_t misc_helper;
};

void arm64_jit_get_helper_profile_snapshot(struct arm64_jit_helper_profile_snapshot *out);
void arm64_jit_dispatch_pc_segment_reset(void);
void arm64_jit_dispatch_pc_segment_dump(uint64_t segment_index, addr_t syscall_pc,
        uint32_t syscall_num, uint64_t dispatch_blocks);

#ifdef ISH_ARM64_JIT_PERF_COUNTERS
struct arm64_jit_branch_fast_profile {
    _Atomic uint64_t same_fragment_hits;
    _Atomic uint64_t fragment_tlb_hits;
    _Atomic uint64_t misses;
    _Atomic uint64_t control_same_fragment_hits[4];
    _Atomic uint64_t control_fragment_tlb_hits[4];
    _Atomic uint64_t control_misses[4];
    _Atomic uint64_t miss_reasons[6];
    _Atomic uint64_t control_miss_reasons[4][6];
    _Atomic uint64_t same_page_range_pages[64];
    _Atomic uint64_t same_page_range_page_counts[64];
    _Atomic uint64_t pc_target_hits;
    _Atomic uint64_t page_map_hits;
    _Atomic uint64_t control_pc_target_hits[4];
    _Atomic uint64_t control_page_map_hits[4];
    _Atomic uint64_t pc_target_miss_reasons[6];
    _Atomic uint64_t pc_target_overwrite_indices[ARM64_JIT_PC_TARGET_CACHE_SIZE];
    _Atomic uint64_t pc_target_overwrite_old_pcs[ARM64_JIT_PC_TARGET_CACHE_SIZE];
    _Atomic uint64_t pc_target_overwrite_new_pcs[ARM64_JIT_PC_TARGET_CACHE_SIZE];
};

extern struct arm64_jit_branch_fast_profile g_arm64_jit_branch_fast_profile;
#endif

struct arm64_jit_emitter {
    struct arm64_jit_state *state;
    struct arm64_jit_block *block;
    uint8_t *buf;
    size_t cap;
    size_t size;
    bool overflowed;
    bool dry_run;
};

enum arm64_jit_fixup_kind {
    ARM64_JIT_FIXUP_B = 0,
    ARM64_JIT_FIXUP_B_COND,
    ARM64_JIT_FIXUP_CBZ,
    ARM64_JIT_FIXUP_TBZ,
};

enum arm64_jit_emit_result {
    ARM64_JIT_EMIT_UNSUPPORTED = 0,
    ARM64_JIT_EMIT_CONTINUE,
    ARM64_JIT_EMIT_TERMINATE,
};

extern __thread struct arm64_jit_runtime *g_arm64_jit_runtime;

static inline struct list *arm64_jit_blocks_list(struct arm64_jit_state *state, page_t page, int i) {
    return &state->page_hash[page % ARM64_JIT_PAGE_HASH_SIZE].blocks[i];
}

struct arm64_jit_state *arm64_jit_state_for_mmu(struct mmu *mmu);
void arm64_jit_invalidate_page(struct mmu *mmu, page_t page);
void arm64_jit_destroy_mmu(struct mmu *mmu);
int cpu_run_to_interrupt_arm64_jit(struct cpu_state *cpu, struct tlb *tlb);
bool arm64_jit_alloc_code(struct arm64_jit_state *state, struct arm64_jit_block *block,
        size_t size, uint8_t **rw_out);
bool arm64_jit_protect_code(struct arm64_jit_block *block);
void arm64_jit_free_code(struct arm64_jit_block *block);
void arm64_jit_begin_code_batch(struct arm64_jit_state *state, size_t reserve_size);
bool arm64_jit_finish_code_batch(struct arm64_jit_state *state);
void arm64_jit_abort_code_batch(struct arm64_jit_state *state);

int arm64_jit_trace_mode(void);
int arm64_jit_verify_mode(void);
addr_t arm64_jit_verify_filter_pc(void);
uint64_t arm64_jit_verify_start_block(void);
int arm64_jit_branch_reg_fast_mode(void);
int arm64_jit_handle_verify_sigtrap(void *ctx);
void arm64_jit_set_saved_pc(addr_t pc);
void arm64_jit_record_fault_pc(void *host_pc);
void arm64_jit_dump_tlb_profile(void);
void arm64_jit_dump_sample_profile(void);

int c_load64(struct tlb *tlb, addr_t addr, uint64_t *out);
int c_load32(struct tlb *tlb, addr_t addr, uint32_t *out);
int c_load16(struct tlb *tlb, addr_t addr, uint16_t *out);
int c_load8(struct tlb *tlb, addr_t addr, uint8_t *out);
int c_load32_sx(struct tlb *tlb, addr_t addr, int64_t *out);
int c_store64(struct tlb *tlb, addr_t addr, uint64_t value);
int c_store32(struct tlb *tlb, addr_t addr, uint32_t value);
int c_store16(struct tlb *tlb, addr_t addr, uint16_t value);
int c_store8(struct tlb *tlb, addr_t addr, uint8_t value);

int arm64_jit_helper_unsupported(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_syscall(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_verify_trap(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_dispatch(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_branch_reg(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_branch_reg_fast_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn, uint64_t target);
int arm64_jit_helper_cbz_cbnz(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_b_cond(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_tbz_tbnz(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_mrs_tpidr(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t rd);
int arm64_jit_helper_mrs_sysreg(struct arm64_jit_runtime *rt, uint64_t packed);
int arm64_jit_helper_msr_tpidr(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t rn);
int arm64_jit_helper_msr_daif(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_exec_dp_imm(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_exec_dp_reg(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_ldr_imm_unsigned(struct arm64_jit_runtime *rt, uint64_t packed0, uint64_t packed1);
int arm64_jit_helper_ldr_imm_unsigned_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t store_in_x1);
int arm64_jit_helper_str_imm_unsigned(struct arm64_jit_runtime *rt, uint64_t packed);
int arm64_jit_helper_str_imm_unsigned_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t value);
int arm64_jit_c_ldr_imm_unsigned(struct arm64_jit_runtime *rt, uint64_t packed0, uint64_t packed1);
int arm64_jit_c_str_imm_unsigned(struct arm64_jit_runtime *rt, uint64_t packed);
int arm64_jit_helper_simd_ldst_imm_unsigned(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_simd_ldst_imm_unsigned_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr);
int arm64_jit_helper_ldst_imm9(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_imm9_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t value);
int arm64_jit_helper_ldst_regoff(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_regoff_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t value);
int arm64_jit_helper_simd_ldst_regoff_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr);
int arm64_jit_helper_ldst_imm9_load_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t store_in_x1);
int arm64_jit_helper_ldst_regoff_load_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t store_in_x1);
int arm64_jit_helper_ldst_pair(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_pair_load_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t return_in_x1_x2);
int arm64_jit_helper_ldst_pair_store_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr, uint64_t val0, uint64_t val1);
int arm64_jit_helper_ldst_pair_vec_live(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr);

int arm64_jit_helper_unsupported_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_syscall_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_verify_trap_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_dispatch_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_control_transfer_fast_jitabi(struct arm64_jit_runtime *rt,
        addr_t target_pc, uint64_t kind);
int arm64_jit_helper_branch_reg_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_cbz_cbnz_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_b_cond_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_tbz_tbnz_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_mrs_tpidr_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t rd);
int arm64_jit_helper_mrs_sysreg_jitabi(struct arm64_jit_runtime *rt, uint64_t packed);
int arm64_jit_helper_msr_tpidr_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t rn);
int arm64_jit_helper_msr_daif_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc);
int arm64_jit_helper_exec_dp_imm_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_exec_dp_reg_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc, uint32_t insn);
int arm64_jit_helper_ldr_imm_unsigned_jitabi(struct arm64_jit_runtime *rt, uint64_t packed0, uint64_t packed1);
int arm64_jit_helper_str_imm_unsigned_jitabi(struct arm64_jit_runtime *rt, uint64_t packed);
int arm64_jit_helper_simd_ldst_imm_unsigned_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_simd_ldst_multi_success_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldr_imm_unsigned_success_jitabi(struct arm64_jit_runtime *rt, uint64_t packed0, uint64_t packed1);
int arm64_jit_helper_str_imm_unsigned_success_jitabi(struct arm64_jit_runtime *rt, uint64_t packed);
int arm64_jit_helper_simd_ldst_imm_unsigned_success_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_imm9_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_regoff_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_pair_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_imm9_success_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_regoff_success_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_pair_success_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_excl_success_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_helper_ldst_excl_jitabi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_c_simd_ldst_imm_unsigned(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_c_simd_ldst_addr(struct arm64_jit_runtime *rt, uint64_t packed,
        uint64_t guest_addr);
int arm64_jit_c_simd_ldst_multi(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_c_ldst_imm9(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_c_ldst_regoff(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_c_ldst_pair(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);
int arm64_jit_c_ldst_excl(struct arm64_jit_runtime *rt, addr_t guest_pc,
        uint32_t insn);

bool arm64_jit_analyze_insn(uint32_t insn, struct arm64_jit_insn_info *info);
void arm64_jit_build_fragment_gpr_map(struct arm64_jit_block *block);
bool arm64_jit_guest_reg_is_cached(const struct arm64_jit_block *block, uint32_t guest_reg);
int arm64_jit_host_reg_for_guest(const struct arm64_jit_block *block, uint32_t guest_reg);

uint32_t arm64_jit_enc_movz(unsigned rd, uint16_t imm16, unsigned shift);
uint32_t arm64_jit_enc_movk(unsigned rd, uint16_t imm16, unsigned shift);
uint32_t arm64_jit_enc_mov_reg(unsigned rd, unsigned rn);
uint32_t arm64_jit_enc_blr(unsigned rn);
uint32_t arm64_jit_enc_br(unsigned rn);
uint32_t arm64_jit_enc_ret(unsigned rn);
uint32_t arm64_jit_enc_ldr64_uimm(unsigned rt, unsigned rn, unsigned imm12);
uint32_t arm64_jit_enc_str64_uimm(unsigned rt, unsigned rn, unsigned imm12);
uint32_t arm64_jit_enc_b_imm(int32_t imm26);
uint32_t arm64_jit_enc_b_cond(enum arm64_cond cond, int32_t imm19);
uint32_t arm64_jit_enc_cbz_cbnz(bool sf, bool nonzero, unsigned rt, int32_t imm19);
uint32_t arm64_jit_enc_tbz_tbnz(bool b5, bool nonzero, unsigned bit40, unsigned rt, int32_t imm14);
void arm64_jit_emit32(struct arm64_jit_emitter *e, uint32_t insn);
void arm64_jit_record_pc_map(struct arm64_jit_emitter *e, addr_t guest_pc);
void arm64_jit_emit_load_imm64(struct arm64_jit_emitter *e, unsigned rd, uint64_t value);
void arm64_jit_emit_prologue(struct arm64_jit_emitter *e);
void arm64_jit_emit_epilogue(struct arm64_jit_emitter *e);
void arm64_jit_emit_load_cached_state(struct arm64_jit_emitter *e);
void arm64_jit_emit_spill_cached_state(struct arm64_jit_emitter *e);
void arm64_jit_emit_helper_return(struct arm64_jit_emitter *e, void *helper, addr_t guest_pc);
bool arm64_jit_block_has_pc(const struct arm64_jit_block *block, addr_t guest_pc);
bool arm64_jit_emit_local_fixup(struct arm64_jit_emitter *e, addr_t branch_pc, addr_t target_pc, uint32_t kind);
bool arm64_jit_patch_local_fixups(struct arm64_jit_block *block, uint8_t *buf);

enum arm64_jit_emit_result arm64_jit_emit_dp_imm(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
enum arm64_jit_emit_result arm64_jit_emit_dp_reg(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
enum arm64_jit_emit_result arm64_jit_emit_branch(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
enum arm64_jit_emit_result arm64_jit_emit_exception(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
enum arm64_jit_emit_result arm64_jit_emit_system(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
enum arm64_jit_emit_result arm64_jit_emit_ld_st(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
enum arm64_jit_emit_result arm64_jit_emit_simd_fp(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc);
void arm64_jit_emit_block(struct arm64_jit_state *state, struct arm64_jit_block *block);
size_t arm64_jit_estimate_block_code_size(struct arm64_jit_state *state,
        struct arm64_jit_block *block);

#endif

#endif
