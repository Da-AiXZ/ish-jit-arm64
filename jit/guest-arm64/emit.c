#if defined(GUEST_ARM64) && defined(__aarch64__)

#include <stddef.h>

#include "jit/guest-arm64/jit.h"

uint32_t arm64_jit_enc_movz(unsigned rd, uint16_t imm16, unsigned shift) {
    return 0xd2800000u | ((uint32_t) shift << 21) | ((uint32_t) imm16 << 5) | rd;
}

uint32_t arm64_jit_enc_movk(unsigned rd, uint16_t imm16, unsigned shift) {
    return 0xf2800000u | ((uint32_t) shift << 21) | ((uint32_t) imm16 << 5) | rd;
}

uint32_t arm64_jit_enc_mov_reg(unsigned rd, unsigned rn) {
    return 0xaa0003e0u | (rn << 16) | rd;
}

uint32_t arm64_jit_enc_blr(unsigned rn) {
    return 0xd63f0000u | (rn << 5);
}

uint32_t arm64_jit_enc_br(unsigned rn) {
    return 0xd61f0000u | (rn << 5);
}

uint32_t arm64_jit_enc_ret(unsigned rn) {
    return 0xd65f0000u | (rn << 5);
}

static uint32_t arm64_jit_enc_eor_reg64(unsigned rd, unsigned rn, unsigned rm) {
    return 0xca000000u | ((rm & 0x1f) << 16) | ((rn & 0x1f) << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_eor_shift_reg64(unsigned rd, unsigned rn, unsigned rm,
        unsigned shift, unsigned imm6) {
    return 0xca000000u | ((shift & 0x3) << 22) | ((rm & 0x1f) << 16) |
           ((imm6 & 0x3f) << 10) | ((rn & 0x1f) << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_add_imm64(unsigned rd, unsigned rn, unsigned imm12) {
    return 0x91000000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_sub_imm64(unsigned rd, unsigned rn, unsigned imm12) {
    return 0xd1000000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_add_shift_reg64(unsigned rd, unsigned rn, unsigned rm, unsigned imm6) {
    return 0x8b000000u | ((rm & 0x1f) << 16) | ((imm6 & 0x3f) << 10) |
           ((rn & 0x1f) << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_ubfm64(unsigned rd, unsigned rn, unsigned immr, unsigned imms) {
    return 0xd3400000u | ((immr & 0x3f) << 16) | ((imms & 0x3f) << 10) |
           ((rn & 0x1f) << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_lsr_imm64(unsigned rd, unsigned rn, unsigned shift) {
    return arm64_jit_enc_ubfm64(rd, rn, shift, 63);
}

static uint32_t arm64_jit_enc_ubfx64(unsigned rd, unsigned rn, unsigned lsb, unsigned width) {
    return arm64_jit_enc_ubfm64(rd, rn, lsb, lsb + width - 1);
}

static uint32_t arm64_jit_enc_ldr_size_uimm(unsigned rt, unsigned rn, unsigned size, unsigned imm12) {
    static const uint32_t bases[4] = {0x39400000u, 0x79400000u, 0xb9400000u, 0xf9400000u};
    return bases[size & 3] | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

static uint32_t arm64_jit_enc_ldrsw_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0xb9800000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

static uint32_t arm64_jit_enc_ldrsb_uimm(unsigned rt, unsigned rn, unsigned imm12, bool sf) {
    return (sf ? 0x39800000u : 0x39c00000u) |
           ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

static uint32_t arm64_jit_enc_ldrsh_uimm(unsigned rt, unsigned rn, unsigned imm12, bool sf) {
    return (sf ? 0x79800000u : 0x79c00000u) |
           ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

static uint32_t arm64_jit_enc_str_size_uimm(unsigned rt, unsigned rn, unsigned size, unsigned imm12) {
    static const uint32_t bases[4] = {0x39000000u, 0x79000000u, 0xb9000000u, 0xf9000000u};
    return bases[size & 3] | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

static uint32_t arm64_jit_enc_ldr_size_uimm0(unsigned rt, unsigned rn, unsigned size) {
    return arm64_jit_enc_ldr_size_uimm(rt, rn, size, 0);
}

static uint32_t arm64_jit_enc_str_size_uimm0(unsigned rt, unsigned rn, unsigned size) {
    return arm64_jit_enc_str_size_uimm(rt, rn, size, 0);
}

static uint32_t arm64_jit_enc_cmp_reg64(unsigned rn, unsigned rm) {
    return 0xeb00001fu | ((rm & 0x1f) << 16) | ((rn & 0x1f) << 5);
}

static uint32_t arm64_jit_enc_cmp_reg32(unsigned rn, unsigned rm) {
    return 0x6b00001fu | ((rm & 0x1f) << 16) | ((rn & 0x1f) << 5);
}

static uint32_t arm64_jit_enc_cset32(unsigned rd, enum arm64_cond cond) {
    return 0x1a9f07e0u | (((uint32_t) cond ^ 1u) << 12) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_movn64(unsigned rd, uint16_t imm16, unsigned shift) {
    return 0x92800000u | ((uint32_t) shift << 21) | ((uint32_t) imm16 << 5) | (rd & 0x1f);
}

static uint32_t arm64_jit_enc_cas_size(unsigned expected, unsigned desired, unsigned rn,
        unsigned size, bool acquire_release) {
    static const uint32_t cas_base[4] = {0x08a07c00u, 0x48a07c00u, 0x88a07c00u, 0xc8a07c00u};
    static const uint32_t casal_base[4] = {0x08e0fc00u, 0x48e0fc00u, 0x88e0fc00u, 0xc8e0fc00u};
    const uint32_t *base = acquire_release ? casal_base : cas_base;
    return base[size & 3] | ((expected & 0x1f) << 16) | ((rn & 0x1f) << 5) | (desired & 0x1f);
}

static uint32_t arm64_jit_enc_simd_ldst_uimm0(uint32_t insn, unsigned rn) {
    return (insn & ~(((uint32_t) 0xfff << 10) | ((uint32_t) 0x1f << 5))) |
           ((rn & 0x1f) << 5);
}

uint32_t arm64_jit_enc_brk(unsigned imm16) {
    return 0xd4200000u | ((imm16 & 0xffff) << 5);
}

uint32_t arm64_jit_enc_ldr64_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0xf9400000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_str64_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0xf9000000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_ldr32_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0xb9400000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_str32_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0xb9000000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_ldr128_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0x3dc00000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_str128_uimm(unsigned rt, unsigned rn, unsigned imm12) {
    return 0x3d800000u | ((imm12 & 0xfff) << 10) | ((rn & 0x1f) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_b_imm(int32_t imm26) {
    return 0x14000000u | ((uint32_t) imm26 & 0x03ffffffu);
}

uint32_t arm64_jit_enc_b_cond(enum arm64_cond cond, int32_t imm19) {
    return 0x54000000u | (((uint32_t) imm19 & 0x7ffffu) << 5) | (cond & 0xf);
}

uint32_t arm64_jit_enc_cbz_cbnz(bool sf, bool nonzero, unsigned rt, int32_t imm19) {
    return ((uint32_t) sf << 31) | 0x34000000u | ((uint32_t) nonzero << 24) |
           (((uint32_t) imm19 & 0x7ffffu) << 5) | (rt & 0x1f);
}

uint32_t arm64_jit_enc_tbz_tbnz(bool b5, bool nonzero, unsigned bit40, unsigned rt, int32_t imm14) {
    return ((uint32_t) b5 << 31) | 0x36000000u | ((uint32_t) nonzero << 24) |
           ((bit40 & 0x1f) << 19) | (((uint32_t) imm14 & 0x3fffu) << 5) | (rt & 0x1f);
}

void arm64_jit_emit32(struct arm64_jit_emitter *e, uint32_t insn) {
    if (e->dry_run) {
        e->size += 4;
        return;
    }
    if (e->size + 4 <= e->cap) {
        *(uint32_t *) (e->buf + e->size) = insn;
        e->size += 4;
    } else {
        e->overflowed = true;
    }
}

void arm64_jit_record_pc_map(struct arm64_jit_emitter *e, addr_t guest_pc) {
    if (e->block->pc_map_count < ARM64_JIT_MAX_PC_MAP) {
        struct arm64_jit_pc_map *m = &e->block->pc_map[e->block->pc_map_count++];
        m->host_offset = (uint32_t) e->size;
        m->guest_pc = guest_pc;
    }
}

void arm64_jit_record_verify_site(struct arm64_jit_emitter *e, addr_t guest_pc, uint32_t insn) {
    if (e->block->verify_site_count < ARM64_JIT_MAX_VERIFY_SITES) {
        struct arm64_jit_verify_site *site =
                &e->block->verify_sites[e->block->verify_site_count++];
        site->host_offset = (uint32_t) e->size;
        site->guest_pc = guest_pc;
        site->insn = insn;
    }
}

void arm64_jit_emit_verify_entry_brk(struct arm64_jit_emitter *e, addr_t guest_pc, uint32_t insn) {
    if (!arm64_jit_verify_mode())
        return;
    addr_t filter_pc = arm64_jit_verify_filter_pc();
    if (filter_pc != 0 &&
            (filter_pc < e->block->start_pc || filter_pc >= e->block->end_pc))
        return;
    arm64_jit_record_verify_site(e, guest_pc, insn);
    arm64_jit_record_pc_map(e, guest_pc);
    arm64_jit_emit32(e, arm64_jit_enc_brk(0x4a1));
}

bool arm64_jit_block_has_pc(const struct arm64_jit_block *block, addr_t guest_pc) {
    for (uint32_t i = 0; i < block->insn_count; i++) {
        if (block->insn_pcs[i] == guest_pc)
            return true;
    }
    return false;
}

bool arm64_jit_emit_local_fixup(struct arm64_jit_emitter *e, addr_t branch_pc, addr_t target_pc, uint32_t kind) {
    if (e->block->fixup_count >= ARM64_JIT_MAX_FIXUPS)
        return false;
    struct arm64_jit_local_fixup *f = &e->block->fixups[e->block->fixup_count++];
    f->branch_offset = (uint32_t) e->size;
    f->branch_pc = branch_pc;
    f->target_pc = target_pc;
    f->kind = kind;
    return true;
}

static bool arm64_jit_local_fixup_disabled(const struct arm64_jit_block *block, addr_t branch_pc) {
    for (uint32_t i = 0; i < block->disabled_local_fixup_count; i++) {
        if (block->disabled_local_fixup_pcs[i] == branch_pc)
            return true;
    }
    return false;
}

static uint32_t arm64_jit_find_host_offset_for_pc(const struct arm64_jit_block *block, addr_t guest_pc) {
    for (uint32_t i = 0; i < block->pc_map_count; i++) {
        if (block->pc_map[i].guest_pc == guest_pc)
            return block->pc_map[i].host_offset;
    }
    return UINT32_MAX;
}

static void arm64_jit_disable_local_fixup(struct arm64_jit_block *block, addr_t branch_pc) {
    for (uint32_t i = 0; i < block->disabled_local_fixup_count; i++) {
        if (block->disabled_local_fixup_pcs[i] == branch_pc)
            return;
    }
    if (block->disabled_local_fixup_count < ARM64_JIT_MAX_FIXUPS)
        block->disabled_local_fixup_pcs[block->disabled_local_fixup_count++] = branch_pc;
}

static bool arm64_jit_fixup_word_delta_fits(int64_t word_delta, unsigned bits) {
    int64_t min = -(1ll << (bits - 1));
    int64_t max = (1ll << (bits - 1)) - 1;
    return word_delta >= min && word_delta <= max;
}

bool arm64_jit_patch_local_fixups(struct arm64_jit_block *block, uint8_t *buf) {
    for (uint32_t i = 0; i < block->fixup_count; i++) {
        struct arm64_jit_local_fixup *f = &block->fixups[i];
        uint32_t target_off = arm64_jit_find_host_offset_for_pc(block, f->target_pc);
        if (target_off == UINT32_MAX) {
            if (arm64_jit_trace_mode()) {
                fprintf(stderr, "[arm64-jit] fixup unresolved idx=%u target_pc=0x%llx kind=%u branch_off=%u\n",
                        i, (unsigned long long) f->target_pc, f->kind, f->branch_offset);
            }
            arm64_jit_disable_local_fixup(block, f->branch_pc);
            return false;
        }
        int64_t byte_delta = (int64_t) target_off - (int64_t) f->branch_offset;
        int64_t word_delta = byte_delta >> 2;
        uint32_t *slot = (uint32_t *) (buf + f->branch_offset);
        switch (f->kind) {
            case ARM64_JIT_FIXUP_B:
                if (!arm64_jit_fixup_word_delta_fits(word_delta, 26))
                    goto out_of_range;
                *slot = arm64_jit_enc_b_imm((int32_t) word_delta);
                break;
            case ARM64_JIT_FIXUP_B_COND: {
                if (!arm64_jit_fixup_word_delta_fits(word_delta, 19))
                    goto out_of_range;
                enum arm64_cond cond = (enum arm64_cond) (*slot & 0xf);
                *slot = arm64_jit_enc_b_cond(cond, (int32_t) word_delta);
                break;
            }
            case ARM64_JIT_FIXUP_CBZ: {
                if (!arm64_jit_fixup_word_delta_fits(word_delta, 19))
                    goto out_of_range;
                bool sf = ((*slot >> 31) & 1) != 0;
                bool nonzero = ((*slot >> 24) & 1) != 0;
                unsigned rt = *slot & 0x1f;
                *slot = arm64_jit_enc_cbz_cbnz(sf, nonzero, rt, (int32_t) word_delta);
                break;
            }
            case ARM64_JIT_FIXUP_TBZ: {
                if (!arm64_jit_fixup_word_delta_fits(word_delta, 14))
                    goto out_of_range;
                bool b5 = ((*slot >> 31) & 1) != 0;
                bool nonzero = ((*slot >> 24) & 1) != 0;
                unsigned bit40 = (*slot >> 19) & 0x1f;
                unsigned rt = *slot & 0x1f;
                *slot = arm64_jit_enc_tbz_tbnz(b5, nonzero, bit40, rt, (int32_t) word_delta);
                break;
            }
            default:
                return false;
        }
        continue;
out_of_range:
        if (arm64_jit_trace_mode()) {
            fprintf(stderr,
                    "[arm64-jit] fixup out of range idx=%u target_pc=0x%llx kind=%u branch_off=%u target_off=%u word_delta=%lld\n",
                    i, (unsigned long long) f->target_pc, f->kind, f->branch_offset,
                    target_off, (long long) word_delta);
        }
        arm64_jit_disable_local_fixup(block, f->branch_pc);
        return false;
    }
    return true;
}

void arm64_jit_emit_load_imm64(struct arm64_jit_emitter *e, unsigned rd, uint64_t value) {
    arm64_jit_emit32(e, arm64_jit_enc_movz(rd, value & 0xffff, 0));
    for (unsigned shift = 1; shift < 4; shift++) {
        uint16_t chunk = (uint16_t) ((value >> (shift * 16)) & 0xffff);
        if (chunk == 0)
            continue;
        arm64_jit_emit32(e, arm64_jit_enc_movk(rd, chunk, shift));
    }
}

void arm64_jit_emit_prologue(struct arm64_jit_emitter *e) {
    arm64_jit_emit32(e, 0xa9ba7bfd); // stp x29, x30, [sp, #-96]!
    arm64_jit_emit32(e, 0xa90153f3); // stp x19, x20, [sp, #16]
    arm64_jit_emit32(e, 0xa9025bf5); // stp x21, x22, [sp, #32]
    arm64_jit_emit32(e, 0xa90363f7); // stp x23, x24, [sp, #48]
    arm64_jit_emit32(e, 0xa9046bf9); // stp x25, x26, [sp, #64]
    arm64_jit_emit32(e, 0xa90573fb); // stp x27, x28, [sp, #80]
    arm64_jit_emit32(e, 0xd10203ff); // sub sp, sp, #128
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(8, 31, 0));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(9, 31, 1));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(10, 31, 2));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(11, 31, 3));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(12, 31, 4));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(13, 31, 5));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(14, 31, 6));
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(15, 31, 7));
    arm64_jit_emit32(e, 0xaa0003f5); // mov x21, x0 ; runtime*
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_CPU, ARM64_JIT_HOST_CTX, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_TLB, ARM64_JIT_HOST_CTX, 1));
}

static void arm64_jit_emit_load_cached_gpr_state(struct arm64_jit_emitter *e) {
    for (uint32_t guest = 0; guest < 31; guest++) {
        int host = arm64_jit_host_reg_for_guest(e->block, guest);
        if (host < 0)
            continue;
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) host, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[guest]) >> 3)));
    }
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_GUEST_SP, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(sp) >> 3)));
    arm64_jit_emit32(e, arm64_jit_enc_ldr32_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(nzcv) >> 2)));
    arm64_jit_emit32(e, 0xd51b4210); // msr nzcv, x16
}

void arm64_jit_emit_load_cached_state(struct arm64_jit_emitter *e) {
    arm64_jit_emit_load_cached_gpr_state(e);
    arm64_jit_emit32(e, arm64_jit_enc_ldr32_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(fpcr) >> 2)));
    arm64_jit_emit32(e, 0xd51b4410); // msr fpcr, x16
    arm64_jit_emit32(e, arm64_jit_enc_ldr32_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(fpsr) >> 2)));
    arm64_jit_emit32(e, 0xd51b4430); // msr fpsr, x16
    for (uint32_t v = 0; v < 32; v++) {
        arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(v, ARM64_JIT_HOST_CPU,
                ((CPU_OFFSET(fp[0]) >> 4) + v)));
    }
}

void arm64_jit_emit_spill_cached_state(struct arm64_jit_emitter *e) {
    for (uint32_t guest = 0; guest < 31; guest++) {
        int host = arm64_jit_host_reg_for_guest(e->block, guest);
        if (host < 0)
            continue;
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm((unsigned) host, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[guest]) >> 3)));
    }
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_GUEST_SP, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(sp) >> 3)));
    arm64_jit_emit32(e, 0xd53b4210); // mrs x16, nzcv
    arm64_jit_emit32(e, arm64_jit_enc_str32_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(nzcv) >> 2)));
    arm64_jit_emit32(e, 0xd53b4410); // mrs x16, fpcr
    arm64_jit_emit32(e, arm64_jit_enc_str32_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(fpcr) >> 2)));
    for (uint32_t v = 0; v < 32; v++) {
        arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(v, ARM64_JIT_HOST_CPU,
                ((CPU_OFFSET(fp[0]) >> 4) + v)));
    }
}

static void arm64_jit_emit_light_spill_cached_state(struct arm64_jit_emitter *e) {
    for (uint32_t guest = 0; guest < 31; guest++) {
        int host = arm64_jit_host_reg_for_guest(e->block, guest);
        if (host < 0)
            continue;
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm((unsigned) host, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[guest]) >> 3)));
    }
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_GUEST_SP, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(sp) >> 3)));
    arm64_jit_emit32(e, 0xd53b4210); // mrs x16, nzcv
    arm64_jit_emit32(e, arm64_jit_enc_str32_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(nzcv) >> 2)));
}

static void arm64_jit_emit_spill_cached_vreg(struct arm64_jit_emitter *e, uint32_t reg) {
    if (reg >= 32)
        return;
    arm64_jit_emit32(e, arm64_jit_enc_str128_uimm(reg, ARM64_JIT_HOST_CPU,
            ((CPU_OFFSET(fp[0]) >> 4) + reg)));
}

static void arm64_jit_emit_load_cached_vreg(struct arm64_jit_emitter *e, uint32_t reg) {
    if (reg >= 32)
        return;
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(reg, ARM64_JIT_HOST_CPU,
            ((CPU_OFFSET(fp[0]) >> 4) + reg)));
}

void arm64_jit_emit_epilogue(struct arm64_jit_emitter *e) {
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(8, 31, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(9, 31, 1));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(10, 31, 2));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(11, 31, 3));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(12, 31, 4));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(13, 31, 5));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(14, 31, 6));
    arm64_jit_emit32(e, arm64_jit_enc_ldr128_uimm(15, 31, 7));
    arm64_jit_emit32(e, 0x910203ff); // add sp, sp, #128
    arm64_jit_emit32(e, 0xa94573fb); // ldp x27, x28, [sp, #80]
    arm64_jit_emit32(e, 0xa9446bf9); // ldp x25, x26, [sp, #64]
    arm64_jit_emit32(e, 0xa94363f7); // ldp x23, x24, [sp, #48]
    arm64_jit_emit32(e, 0xa9425bf5); // ldp x21, x22, [sp, #32]
    arm64_jit_emit32(e, 0xa94153f3); // ldp x19, x20, [sp, #16]
    arm64_jit_emit32(e, 0xa8c67bfd); // ldp x29, x30, [sp], #96
    arm64_jit_emit32(e, arm64_jit_enc_ret(30));
}

static void arm64_jit_emit_state_snippet_ret(struct arm64_jit_emitter *e) {
    arm64_jit_emit32(e, arm64_jit_enc_ret(30));
}

static void arm64_jit_patch_cond_branch_to_here(struct arm64_jit_emitter *e, uint32_t branch_off);
static void arm64_jit_emit_exit_epilogue_branch(struct arm64_jit_emitter *e);
static void arm64_jit_patch_exit_epilogue_branches(struct arm64_jit_emitter *e,
        uint32_t epilogue_off);
static void arm64_jit_emit_publish_resume_pc(struct arm64_jit_emitter *e, addr_t pc);
static void arm64_jit_emit_internal_fallthrough(struct arm64_jit_emitter *e,
        addr_t branch_pc, addr_t target_pc);
static bool arm64_jit_branch_has_fallthrough(uint32_t insn);
static enum arm64_jit_emit_result arm64_jit_emit_one(struct arm64_jit_emitter *e,
        const struct arm64_jit_insn_info *info, uint32_t insn, addr_t guest_pc);
static void arm64_jit_reset_emit_metadata(struct arm64_jit_block *block);
static size_t arm64_jit_code_cap_for_estimate(size_t estimate);
struct arm64_jit_fast_trace_build;
static bool arm64_jit_emit_fast_trace_guard_prelude(struct arm64_jit_emitter *e,
        const struct arm64_jit_fast_trace_build *trace, uint32_t *miss_branches,
        uint32_t *miss_branch_count, uint32_t miss_branch_cap);

static void arm64_jit_emit_c_entry_snippet(struct arm64_jit_emitter *e) {
    arm64_jit_emit_prologue(e);
    arm64_jit_emit_load_cached_state(e);
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_CTX,
            (96 >> 3))); // rt->entry_target
    arm64_jit_emit32(e, arm64_jit_enc_br(ARM64_JIT_HOST_HELPER1));
}

static void arm64_jit_emit_fast_trace_jit_entry_snippet(struct arm64_jit_emitter *e,
        const struct arm64_jit_fast_trace_build *trace, uint32_t exit_epilogue_off,
        addr_t guard_miss_pc) {
    uint32_t guard_miss_branches[32];
    uint32_t guard_miss_branch_count = 0;
    if (!arm64_jit_emit_fast_trace_guard_prelude(e, trace, guard_miss_branches,
                &guard_miss_branch_count,
                sizeof(guard_miss_branches) / sizeof(guard_miss_branches[0])))
        return;
    arm64_jit_emit_load_cached_gpr_state(e);
    uint32_t body_off = e->block->insn_host_offsets[0];
    uint32_t body_branch_off = (uint32_t) e->size;
    int64_t body_delta = (int64_t) body_off - (int64_t) body_branch_off;
    if ((body_delta & 3) != 0 ||
            body_delta < -0x08000000ll || body_delta > 0x07fffffcll) {
        e->overflowed = true;
        arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
    } else {
        arm64_jit_emit32(e, arm64_jit_enc_b_imm((int32_t) (body_delta >> 2)));
    }

    for (uint32_t i = 0; i < guard_miss_branch_count; i++)
        arm64_jit_patch_cond_branch_to_here(e, guard_miss_branches[i]);
    arm64_jit_emit_publish_resume_pc(e, guard_miss_pc);
    uint32_t exit_branch_off = (uint32_t) e->size;
    int64_t exit_delta = (int64_t) exit_epilogue_off - (int64_t) exit_branch_off;
    if ((exit_delta & 3) != 0 ||
            exit_delta < -0x08000000ll || exit_delta > 0x07fffffcll) {
        e->overflowed = true;
        arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
    } else {
        arm64_jit_emit32(e, arm64_jit_enc_b_imm((int32_t) (exit_delta >> 2)));
    }
}

static void arm64_jit_emit_fast_trace_jit_return(struct arm64_jit_emitter *e) {
    arm64_jit_emit_spill_cached_state(e);
    arm64_jit_emit_publish_resume_pc(e, e->block->start_pc + 4);
    arm64_jit_emit_exit_epilogue_branch(e);
}

static void arm64_jit_emit_jit_entry_snippet(struct arm64_jit_emitter *e) {
    arm64_jit_emit_load_cached_gpr_state(e);
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_CTX,
            (96 >> 3))); // rt->entry_target
    arm64_jit_emit32(e, arm64_jit_enc_br(ARM64_JIT_HOST_HELPER1));
}

static void arm64_jit_emit_entry_dispatch_table(struct arm64_jit_emitter *e) {
    for (uint32_t i = 0; i < e->block->insn_count; i++) {
        uint32_t slot_off = (uint32_t) e->size;
        uint32_t target_off = e->block->insn_host_offsets[i];
        if (target_off == UINT32_MAX) {
            arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
            continue;
        }
        int64_t byte_delta = (int64_t) target_off - (int64_t) slot_off;
        if ((byte_delta & 3) != 0 ||
                byte_delta < -0x08000000ll || byte_delta > 0x07fffffcll) {
            e->overflowed = true;
            arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
            continue;
        }
        arm64_jit_emit32(e, arm64_jit_enc_b_imm((int32_t) (byte_delta >> 2)));
    }
}

static int arm64_jit_guest_src_host_reg(const struct arm64_jit_block *block,
        uint32_t guest_reg, bool sp_not_zr);

void arm64_jit_emit_helper_return(struct arm64_jit_emitter *e, void *helper, addr_t guest_pc) {
    arm64_jit_emit_spill_cached_state(e);
    arm64_jit_emit_load_imm64(e, 1, guest_pc);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    arm64_jit_emit_exit_epilogue_branch(e);
}

static void arm64_jit_emit_control_transfer_fast_return(struct arm64_jit_emitter *e,
        unsigned target_reg, unsigned kind, addr_t source_pc, unsigned control_flags) {
    arm64_jit_emit_load_imm64(e, 2, (kind & 3) | (control_flags << 8));
    arm64_jit_emit_load_imm64(e, 3, source_pc);
    if (target_reg != 1)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(1, target_reg));
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) arm64_jit_helper_control_transfer_fast_jitabi);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    arm64_jit_emit_exit_epilogue_branch(e);
}

static void arm64_jit_emit_control_transfer_fast_return_imm(struct arm64_jit_emitter *e,
        addr_t source_pc, addr_t target_pc, unsigned kind) {
    arm64_jit_emit_load_imm64(e, 1, target_pc);
    arm64_jit_emit_control_transfer_fast_return(e, 1, kind, source_pc, 0);
}

static void arm64_jit_emit_control_transfer_fast_return_imm_flags(struct arm64_jit_emitter *e,
        addr_t source_pc, addr_t target_pc, unsigned kind, unsigned control_flags) {
    arm64_jit_emit_load_imm64(e, 1, target_pc);
    arm64_jit_emit_control_transfer_fast_return(e, 1, kind, source_pc, control_flags);
}

static void arm64_jit_emit_conditional_transfer_fast_return(struct arm64_jit_emitter *e,
        uint32_t branch_insn, addr_t source_pc, addr_t fallthrough_pc,
        addr_t target_pc, unsigned kind) {
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, target_pc);
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP2, fallthrough_pc);
    arm64_jit_emit32(e, branch_insn);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP2));
    arm64_jit_emit_control_transfer_fast_return(e, ARM64_JIT_HOST_TMP1, kind, source_pc, 0);
}

static void arm64_jit_emit_helper_return_branch_reg_fast(struct arm64_jit_emitter *e,
        addr_t guest_pc, uint32_t insn) {
    uint32_t rn = ARM64_RN(insn);
    arm64_jit_emit_load_imm64(e, 1, guest_pc);
    arm64_jit_emit_load_imm64(e, 2, insn);
    int host_rn = arm64_jit_guest_src_host_reg(e->block, rn, false);
    if (host_rn >= 0) {
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(3, (unsigned) host_rn));
    } else if (rn < 31) {
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(3, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[rn]) >> 3)));
    } else {
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(3, 31));
    }
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) arm64_jit_helper_branch_reg_fast_jitabi);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    arm64_jit_emit_exit_epilogue_branch(e);
}

static void arm64_jit_emit_helper_success_regarg(struct arm64_jit_emitter *e, void *helper,
        addr_t guest_pc, unsigned x2_imm) {
    arm64_jit_emit_load_imm64(e, 1, guest_pc);
    arm64_jit_emit_load_imm64(e, 2, x2_imm);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
}

static void arm64_jit_emit_reload_cached_gpr(struct arm64_jit_emitter *e, uint32_t guest_reg) {
    int host_reg = arm64_jit_host_reg_for_guest(e->block, guest_reg);
    if (host_reg >= 0) {
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) host_reg,
                ARM64_JIT_HOST_CPU, (CPU_OFFSET(regs[guest_reg]) >> 3)));
    }
}

static void arm64_jit_emit_reload_cached_base(struct arm64_jit_emitter *e, uint32_t guest_reg,
        bool sp_not_zr) {
    if (guest_reg == 31) {
        if (sp_not_zr) {
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_GUEST_SP,
                    ARM64_JIT_HOST_CPU, (CPU_OFFSET(sp) >> 3)));
        }
        return;
    }
    arm64_jit_emit_reload_cached_gpr(e, guest_reg);
}

static void arm64_jit_emit_set_guest_lr(struct arm64_jit_emitter *e, addr_t return_pc) {
    int host_lr = arm64_jit_host_reg_for_guest(e->block, 30);
    if (host_lr >= 0) {
        arm64_jit_emit_load_imm64(e, (unsigned) host_lr, return_pc);
        return;
    }
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_HELPER0, return_pc);
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(regs[30]) >> 3)));
}

static void arm64_jit_emit_helper_continue_check(struct arm64_jit_emitter *e) {
    arm64_jit_emit32(e, 0x11000410); // add w16, w0, #1 ; w16 == 0 when return == INT_NONE (-1)
    // A64 conditional branch immediates are relative to the branch instruction
    // address. Our current epilogue is 16 instructions long, so a successful
    // helper return needs a 17-instruction displacement to land at the
    // continuation path after the epilogue.
    arm64_jit_emit32(e, 0x34000230); // cbz w16, +17 insns
}

static void arm64_jit_emit_helper_continue_packed1(struct arm64_jit_emitter *e, void *helper,
        uint64_t x1_imm) {
    arm64_jit_emit_load_imm64(e, 1, x1_imm);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    arm64_jit_emit_helper_continue_check(e);
    arm64_jit_emit_epilogue(e);
}

static void arm64_jit_emit_helper_success_packed1(struct arm64_jit_emitter *e, void *helper,
        uint64_t x1_imm) {
    arm64_jit_emit_load_imm64(e, 1, x1_imm);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
}

static void arm64_jit_emit_helper_success_live_store(struct arm64_jit_emitter *e, void *helper,
        uint64_t packed, unsigned addr_reg, unsigned value_reg) {
    arm64_jit_emit_load_imm64(e, 1, packed);
    if (addr_reg != 2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(2, addr_reg));
    if (value_reg != 3)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(3, value_reg));
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
}

static void arm64_jit_emit_helper_success_live_store_pair(struct arm64_jit_emitter *e, void *helper,
        uint64_t packed, unsigned addr_reg, unsigned value0_reg, unsigned value1_reg) {
    arm64_jit_emit_load_imm64(e, 1, packed);
    if (addr_reg != 2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(2, addr_reg));
    if (value0_reg != 3)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(3, value0_reg));
    if (value1_reg != 16)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(16, value1_reg));
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 17, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(17));
}

static void arm64_jit_emit_helper_success_live_load(struct arm64_jit_emitter *e, void *helper,
        uint64_t packed1, unsigned addr_reg, int dst_host) {
    arm64_jit_emit_load_imm64(e, 1, packed1);
    if (addr_reg != 2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(2, addr_reg));
    arm64_jit_emit_load_imm64(e, 3, dst_host >= 0 ? 1 : 0);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    if (dst_host >= 0 && dst_host != 1)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(dst_host, 1));
}

static void arm64_jit_emit_helper_success_live_load_pair(struct arm64_jit_emitter *e, void *helper,
        uint64_t packed, unsigned addr_reg,
        int dst0_host, uint32_t dst0_guest,
        int dst1_host, uint32_t dst1_guest) {
    arm64_jit_emit_load_imm64(e, 1, packed);
    if (addr_reg != 2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(2, addr_reg));
    arm64_jit_emit_load_imm64(e, 3, 1);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    if (dst0_host >= 0 && dst0_host != 1)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg((unsigned) dst0_host, 1));
    if (dst0_host < 0 && dst0_guest != 31)
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(1, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[dst0_guest]) >> 3)));
    if (dst1_host >= 0 && dst1_host != 2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg((unsigned) dst1_host, 2));
    if (dst1_host < 0 && dst1_guest != 31)
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(2, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[dst1_guest]) >> 3)));
}

static void arm64_jit_emit_helper_success_live_addronly(struct arm64_jit_emitter *e, void *helper,
        uint64_t packed, unsigned addr_reg) {
    arm64_jit_emit_load_imm64(e, 1, packed);
    if (addr_reg != 2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(2, addr_reg));
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
}

static void arm64_jit_emit_helper_success_packed2(struct arm64_jit_emitter *e, void *helper,
        uint64_t x1_imm, uint64_t x2_imm) {
    arm64_jit_emit_load_imm64(e, 1, x1_imm);
    arm64_jit_emit_load_imm64(e, 2, x2_imm);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
}

static void arm64_jit_emit_helper_continue_regarg(struct arm64_jit_emitter *e, void *helper,
        addr_t guest_pc, unsigned x2_imm) {
    arm64_jit_emit_spill_cached_state(e);
    arm64_jit_emit_load_imm64(e, 1, guest_pc);
    arm64_jit_emit_load_imm64(e, 2, x2_imm);
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(0, 21));
    arm64_jit_emit_load_imm64(e, 16, (uint64_t) helper);
    arm64_jit_emit32(e, arm64_jit_enc_blr(16));
    arm64_jit_emit_helper_continue_check(e);
    arm64_jit_emit_epilogue(e);
    arm64_jit_emit_load_cached_state(e);
}

static int arm64_jit_guest_src_host_reg(const struct arm64_jit_block *block, uint32_t guest_reg, bool sp_not_zr) {
    if (guest_reg == 31)
        return sp_not_zr ? ARM64_JIT_HOST_GUEST_SP : -1;
    return arm64_jit_host_reg_for_guest(block, guest_reg);
}

static int arm64_jit_guest_src_host_reg_or_zr(const struct arm64_jit_block *block, uint32_t guest_reg) {
    if (guest_reg == 31)
        return 31;
    return arm64_jit_host_reg_for_guest(block, guest_reg);
}

static bool arm64_jit_emit_guest_src_to_host_reg(struct arm64_jit_emitter *e,
        uint32_t guest_reg, bool sp_not_zr, unsigned dst_host) {
    int src_host = arm64_jit_guest_src_host_reg(e->block, guest_reg, sp_not_zr);
    if (src_host >= 0) {
        if ((unsigned) src_host != dst_host)
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(dst_host, (unsigned) src_host));
        return true;
    }
    if (guest_reg == 31) {
        if (!sp_not_zr) {
            if (dst_host != 31)
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg(dst_host, 31));
            return true;
        }
        return false;
    }
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(dst_host, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(regs[guest_reg]) >> 3)));
    return true;
}

static void arm64_jit_patch_cond_branch_to_here(struct arm64_jit_emitter *e, uint32_t branch_off) {
    if (e->dry_run || e->buf == NULL)
        return;
    uint32_t *slot = (uint32_t *) (e->buf + branch_off);
    int32_t byte_delta = (int32_t) e->size - (int32_t) branch_off;
    int32_t word_delta = byte_delta >> 2;
    if ((*slot & 0x7e000000u) == 0x36000000u) {
        bool b5 = ((*slot >> 31) & 1) != 0;
        bool nonzero = ((*slot >> 24) & 1) != 0;
        unsigned bit40 = (*slot >> 19) & 0x1f;
        unsigned rt = *slot & 0x1f;
        *slot = arm64_jit_enc_tbz_tbnz(b5, nonzero, bit40, rt, word_delta);
    } else {
        *slot = (*slot & 0xff00001fu) | (((uint32_t) word_delta & 0x7ffffu) << 5);
    }
}

static void arm64_jit_patch_b_to_here(struct arm64_jit_emitter *e, uint32_t branch_off) {
    if (e->dry_run || e->buf == NULL)
        return;
    uint32_t *slot = (uint32_t *) (e->buf + branch_off);
    int32_t byte_delta = (int32_t) e->size - (int32_t) branch_off;
    *slot = arm64_jit_enc_b_imm(byte_delta >> 2);
}

static void arm64_jit_emit_exit_epilogue_branch(struct arm64_jit_emitter *e) {
    uint32_t branch_off = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
    if (e->block->exit_epilogue_branch_count < ARM64_JIT_MAX_FIXUPS) {
        e->block->exit_epilogue_branches[e->block->exit_epilogue_branch_count++] = branch_off;
    } else {
        e->overflowed = true;
    }
}

static void arm64_jit_emit_publish_resume_pc(struct arm64_jit_emitter *e, addr_t pc) {
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_HELPER0, pc);
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER0,
            ARM64_JIT_HOST_CTX, offsetof(struct arm64_jit_runtime, resume_pc) >> 3));
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER0,
            ARM64_JIT_HOST_CPU, CPU_OFFSET(pc) >> 3));
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_HELPER0, (uint32_t) INT_NONE);
    arm64_jit_emit32(e, arm64_jit_enc_str32_uimm(ARM64_JIT_HOST_HELPER0,
            ARM64_JIT_HOST_CTX, offsetof(struct arm64_jit_runtime, exit_interrupt) >> 2));
}

static void arm64_jit_patch_exit_epilogue_branches(struct arm64_jit_emitter *e,
        uint32_t epilogue_off) {
    if (e->dry_run || e->buf == NULL)
        return;
    for (uint32_t i = 0; i < e->block->exit_epilogue_branch_count; i++) {
        uint32_t branch_off = e->block->exit_epilogue_branches[i];
        uint32_t *slot = (uint32_t *) (e->buf + branch_off);
        int64_t byte_delta = (int64_t) epilogue_off - (int64_t) branch_off;
        if ((byte_delta & 3) != 0 ||
                byte_delta < -0x08000000ll || byte_delta > 0x07fffffcll) {
            e->overflowed = true;
            continue;
        }
        *slot = arm64_jit_enc_b_imm((int32_t) (byte_delta >> 2));
    }
}

static bool arm64_jit_read_guest_u32(struct arm64_jit_emitter *e, addr_t pc,
        uint32_t *out) {
    if (e->tlb == NULL || out == NULL)
        return false;
    return tlb_read(e->tlb, pc, out, sizeof(*out));
}

struct arm64_jit_fast_trace_build {
    struct arm64_jit_block block;
    addr_t pcs[128];
    uint32_t insns[128];
    struct arm64_jit_insn_info infos[128];
    bool synthetic_set_lr[128];
    addr_t synthetic_lr[128];
    bool synthetic_branch_guard[128];
    uint32_t synthetic_branch_insn[128];
    addr_t synthetic_branch_fallback_pc[128];
    uint32_t call_depth;
    addr_t guard_addr[16];
    uint64_t guard_value[16];
    uint32_t guard_count;
    addr_t const_reg[31];
    bool const_valid[31];
    addr_t mem_load_addr[31];
    bool mem_load_addr_valid[31];
    const char *reject_reason;
    addr_t reject_pc;
    uint32_t reject_insn;
    uint32_t synthetic_branch_guard_count;
    bool function_entry;
    bool closed_loop;
};

static void arm64_jit_fast_trace_reject(struct arm64_jit_fast_trace_build *trace,
        const char *reason, addr_t pc, uint32_t insn) {
    if (trace->reject_reason != NULL)
        return;
    trace->reject_reason = reason;
    trace->reject_pc = pc;
    trace->reject_insn = insn;
}

static bool arm64_jit_fast_trace_contains_pc(const struct arm64_jit_fast_trace_build *trace,
        addr_t pc) {
    for (uint32_t i = 0; i < trace->block.insn_count; i++) {
        if (trace->pcs[i] == pc)
            return true;
    }
    return false;
}

static bool arm64_jit_fast_trace_pending_contains(const addr_t *pending,
        uint32_t pending_count, addr_t pc) {
    for (uint32_t i = 0; i < pending_count; i++) {
        if (pending[i] == pc)
            return true;
    }
    return false;
}

static bool arm64_jit_fast_trace_enqueue_pc(const struct arm64_jit_fast_trace_build *trace,
        addr_t *pending, uint32_t *pending_count, uint32_t pending_cap, addr_t pc) {
    if (arm64_jit_fast_trace_contains_pc(trace, pc) ||
            arm64_jit_fast_trace_pending_contains(pending, *pending_count, pc))
        return true;
    if (*pending_count >= pending_cap)
        return false;
    pending[(*pending_count)++] = pc;
    return true;
}

static bool arm64_jit_fast_trace_pop_pc(addr_t *pending, uint32_t *pending_count,
        addr_t *pc_out) {
    if (*pending_count == 0)
        return false;
    *pc_out = pending[--(*pending_count)];
    return true;
}

static bool arm64_jit_fast_trace_append(struct arm64_jit_fast_trace_build *trace,
        addr_t pc, uint32_t insn, const struct arm64_jit_insn_info *info) {
    if (trace->block.insn_count >= sizeof(trace->pcs) / sizeof(trace->pcs[0]))
        return false;
    uint32_t idx = trace->block.insn_count++;
    trace->pcs[idx] = pc;
    trace->insns[idx] = insn;
    trace->infos[idx] = *info;
    return true;
}

static bool arm64_jit_fast_trace_append_set_lr(struct arm64_jit_fast_trace_build *trace,
        addr_t pc, addr_t lr) {
    if (trace->block.insn_count >= sizeof(trace->pcs) / sizeof(trace->pcs[0]))
        return false;
    uint32_t idx = trace->block.insn_count++;
    trace->pcs[idx] = pc;
    trace->insns[idx] = 0;
    memset(&trace->infos[idx], 0, sizeof(trace->infos[idx]));
    trace->infos[idx].gpr_use_count = 1;
    trace->infos[idx].gpr_uses[0].reg = 30;
    trace->infos[idx].gpr_uses[0].flags = ARM64_JIT_USE_WRITE;
    trace->synthetic_set_lr[idx] = true;
    trace->synthetic_lr[idx] = lr;
    return true;
}

static bool arm64_jit_fast_trace_append_branch_guard(struct arm64_jit_fast_trace_build *trace,
        addr_t pc, uint32_t insn, const struct arm64_jit_insn_info *info,
        addr_t fallback_pc) {
    if (trace->block.insn_count >= sizeof(trace->pcs) / sizeof(trace->pcs[0]))
        return false;
    uint32_t idx = trace->block.insn_count++;
    trace->pcs[idx] = pc;
    trace->insns[idx] = insn;
    trace->infos[idx] = *info;
    trace->infos[idx].type = INSN_BRANCH;
    trace->synthetic_branch_guard[idx] = true;
    trace->synthetic_branch_insn[idx] = insn;
    trace->synthetic_branch_fallback_pc[idx] = fallback_pc;
    trace->synthetic_branch_guard_count++;
    return true;
}

static bool arm64_jit_fast_trace_read_guest_u64(struct arm64_jit_emitter *e, addr_t pc,
        uint64_t *out) {
    if (e->tlb == NULL || out == NULL)
        return false;
    return tlb_read(e->tlb, pc, out, sizeof(*out));
}

static bool arm64_jit_fast_trace_note_guard(struct arm64_jit_fast_trace_build *trace,
        addr_t addr, uint64_t expected) {
    if ((addr & 0xfffu) > 0xff8u)
        return false;
    if (trace->guard_count >= sizeof(trace->guard_addr) / sizeof(trace->guard_addr[0]))
        return false;
    uint32_t idx = trace->guard_count++;
    trace->guard_addr[idx] = addr;
    trace->guard_value[idx] = expected;
    return true;
}

static bool arm64_jit_fast_trace_decode_adrp(uint32_t insn, addr_t pc, addr_t *out) {
    if ((insn & 0x9f000000u) != 0x90000000u)
        return false;
    uint64_t immlo = (insn >> 29) & 0x3u;
    uint64_t immhi = (insn >> 5) & 0x7ffffu;
    int64_t imm = arm64_sign_extend((immhi << 2) | immlo, 21) << 12;
    *out = (addr_t) (((uint64_t) pc & ~0xfffull) + imm);
    return true;
}

static void arm64_jit_fast_trace_track_dataflow(struct arm64_jit_emitter *e,
        struct arm64_jit_fast_trace_build *trace, const struct arm64_jit_insn_info *info,
        addr_t pc, uint32_t insn) {
    (void) e;
    if ((insn & 0x9f000000u) == 0x90000000u) { // ADRP
        uint32_t rd = ARM64_RD(insn);
        addr_t value = 0;
        if (rd < 31 && arm64_jit_fast_trace_decode_adrp(insn, pc, &value)) {
            trace->const_reg[rd] = value;
            trace->const_valid[rd] = true;
            trace->mem_load_addr_valid[rd] = false;
        }
        return;
    }
    if ((insn & 0xffc00000u) == 0x91000000u) { // ADD immediate, no shift
        uint32_t rd = ARM64_RD(insn);
        uint32_t rn = ARM64_RN(insn);
        uint32_t sh = (insn >> 22) & 0x3u;
        uint64_t imm = (insn >> 10) & 0xfffu;
        if (sh == 1)
            imm <<= 12;
        else if (sh != 0)
            imm = UINT64_MAX;
        if (rd < 31 && rn < 31 && imm != UINT64_MAX && trace->const_valid[rn]) {
            trace->const_reg[rd] = trace->const_reg[rn] + imm;
            trace->const_valid[rd] = true;
            trace->mem_load_addr_valid[rd] = false;
        } else if (rd < 31) {
            trace->const_valid[rd] = false;
            trace->mem_load_addr_valid[rd] = false;
        }
        return;
    }
    if ((insn & 0xffc00000u) == 0xf9400000u) { // LDR Xrt, [Xrn,#imm]
        uint32_t rt = ARM64_RT(insn);
        uint32_t rn = ARM64_RN(insn);
        if (rt < 31 && rn < 31 && trace->const_valid[rn]) {
            trace->mem_load_addr[rt] = trace->const_reg[rn] + (((insn >> 10) & 0xfffu) << 3);
            trace->mem_load_addr_valid[rt] = true;
            trace->const_valid[rt] = false;
        } else if (rt < 31) {
            trace->const_valid[rt] = false;
            trace->mem_load_addr_valid[rt] = false;
        }
        return;
    }
    for (uint32_t i = 0; i < info->gpr_use_count; i++) {
        const struct arm64_jit_guest_reg_use *use = &info->gpr_uses[i];
        if ((use->flags & ARM64_JIT_USE_WRITE) && use->reg < 31)
            trace->const_valid[use->reg] = false;
        if ((use->flags & ARM64_JIT_USE_WRITE) && use->reg < 31)
            trace->mem_load_addr_valid[use->reg] = false;
    }
}

static bool arm64_jit_fast_trace_resolve_indirect(struct arm64_jit_emitter *e,
        struct arm64_jit_fast_trace_build *trace, uint32_t rn, addr_t *target_out) {
    if (rn >= 31 || !trace->mem_load_addr_valid[rn])
        return false;
    uint64_t target = 0;
    addr_t guard_addr = trace->mem_load_addr[rn];
    if (!arm64_jit_fast_trace_read_guest_u64(e, guard_addr, &target) || target == 0)
        return false;
    if (!arm64_jit_fast_trace_note_guard(trace, guard_addr, target))
        return false;
    *target_out = (addr_t) target;
    return true;
}

static bool arm64_jit_fast_trace_observed_edge(addr_t source_pc, addr_t *target_out) {
    if (!arm64_jit_fast_mode() || target_out == NULL)
        return false;
    uint64_t best_count = 0;
    addr_t best_target = 0;
    for (size_t i = 0; i < ARM64_JIT_EDGE_PROFILE_SIZE; i++) {
        struct arm64_jit_edge_profile_entry *entry = &g_arm64_jit_edge_profile[i];
        if ((addr_t) atomic_load_explicit(&entry->source_pc, memory_order_relaxed) !=
                source_pc)
            continue;
        uint64_t count = atomic_load_explicit(&entry->count, memory_order_relaxed);
        if (count <= best_count)
            continue;
        best_count = count;
        best_target = (addr_t) atomic_load_explicit(&entry->target_pc,
                memory_order_relaxed);
    }
    if (best_count == 0)
        return false;
    *target_out = best_target;
    return true;
}

static bool arm64_jit_fast_trace_build_from(struct arm64_jit_emitter *e,
        struct arm64_jit_fast_trace_build *trace, addr_t pc, addr_t return_pc,
        uint32_t depth, bool *returned_out) {
    if (returned_out != NULL)
        *returned_out = false;
    if (depth > 8) {
        arm64_jit_fast_trace_reject(trace, "max-depth", pc, 0);
        return false;
    }
    if (arm64_jit_fast_trace_contains_pc(trace, pc)) {
        if (trace->function_entry && depth == 0 && trace->block.insn_count != 0) {
            trace->closed_loop = true;
            return true;
        }
        arm64_jit_fast_trace_reject(trace, "recursive-entry", pc, 0);
        return false;
    }
    addr_t pending[128];
    uint32_t pending_count = 0;
    for (;;) {
        if (trace->block.insn_count >= sizeof(trace->pcs) / sizeof(trace->pcs[0])) {
            arm64_jit_fast_trace_reject(trace, "max-insns", pc, 0);
            return false;
        }
        if (arm64_jit_fast_trace_contains_pc(trace, pc)) {
            if (trace->function_entry && depth == 0 && trace->block.insn_count != 0) {
                trace->closed_loop = true;
                return true;
            }
            arm64_jit_fast_trace_reject(trace, "recursive-frontier", pc, 0);
            return false;
        }

        uint32_t insn = 0;
        struct arm64_jit_insn_info info;
        if (!arm64_jit_read_guest_u32(e, pc, &insn) ||
                !arm64_jit_analyze_insn(insn, &info)) {
            arm64_jit_fast_trace_reject(trace, "decode", pc, insn);
            return false;
        }

        uint32_t op = (insn >> 26) & 0x3f;
        if (info.type == INSN_BRANCH && (op == 0x05 || op == 0x25)) {
            bool is_link = op == 0x25;
            addr_t target = pc + arm64_branch_imm26(insn);
            if (is_link) {
                if (depth >= 8) {
                    arm64_jit_fast_trace_reject(trace, "call-depth", pc, insn);
                    return false;
                }
                uint32_t saved_insn_count = trace->block.insn_count;
                uint32_t saved_guard_count = trace->guard_count;
                uint32_t saved_branch_guard_count = trace->synthetic_branch_guard_count;
                const char *saved_reject_reason = trace->reject_reason;
                addr_t saved_reject_pc = trace->reject_pc;
                uint32_t saved_reject_insn = trace->reject_insn;
                uint64_t saved_const_reg[32];
                bool saved_const_valid[32];
                addr_t saved_mem_load_addr[32];
                bool saved_mem_load_addr_valid[32];
                memcpy(saved_const_reg, trace->const_reg, sizeof(saved_const_reg));
                memcpy(saved_const_valid, trace->const_valid, sizeof(saved_const_valid));
                memcpy(saved_mem_load_addr, trace->mem_load_addr, sizeof(saved_mem_load_addr));
                memcpy(saved_mem_load_addr_valid, trace->mem_load_addr_valid,
                        sizeof(saved_mem_load_addr_valid));
                if (!arm64_jit_fast_trace_append_set_lr(trace, pc, pc + 4)) {
                    arm64_jit_fast_trace_reject(trace, "append-lr", pc, insn);
                    return false;
                }
                bool callee_returned = false;
                bool callee_ok = arm64_jit_fast_trace_build_from(e, trace, target, pc + 4,
                        depth + 1, &callee_returned);
                if ((!callee_ok || !callee_returned) && trace->function_entry) {
                    trace->block.insn_count = saved_insn_count;
                    trace->guard_count = saved_guard_count;
                    trace->synthetic_branch_guard_count = saved_branch_guard_count;
                    trace->reject_reason = saved_reject_reason;
                    trace->reject_pc = saved_reject_pc;
                    trace->reject_insn = saved_reject_insn;
                    memcpy(trace->const_reg, saved_const_reg, sizeof(saved_const_reg));
                    memcpy(trace->const_valid, saved_const_valid, sizeof(saved_const_valid));
                    memcpy(trace->mem_load_addr, saved_mem_load_addr,
                            sizeof(saved_mem_load_addr));
                    memcpy(trace->mem_load_addr_valid, saved_mem_load_addr_valid,
                            sizeof(saved_mem_load_addr_valid));
                    if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                        arm64_jit_fast_trace_reject(trace, "append-call", pc, insn);
                        return false;
                    }
                    pc += 4;
                    continue;
                }
                if (!callee_ok)
                    return false;
                if (!callee_returned) {
                    arm64_jit_fast_trace_reject(trace, "callee-no-ret", pc, insn);
                    return false;
                }
                pc += 4;
                continue;
            }
            if (target <= pc) {
                if (trace->function_entry && arm64_jit_fast_trace_contains_pc(trace, target)) {
                    if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                        arm64_jit_fast_trace_reject(trace, "append-loop-b", pc, insn);
                        return false;
                    }
                    if (!arm64_jit_fast_trace_pop_pc(pending, &pending_count, &pc)) {
                        if (returned_out != NULL)
                            *returned_out = true;
                        return true;
                    }
                    continue;
                } else if (trace->function_entry && depth == 0 &&
                        target >= trace->block.start_pc) {
                    pc = target;
                    continue;
                } else {
                    arm64_jit_fast_trace_reject(trace, "backward-b", pc, insn);
                    return false;
                }
            }
            if (trace->function_entry) {
                if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                    arm64_jit_fast_trace_reject(trace, "append-b", pc, insn);
                    return false;
                }
                if (!arm64_jit_fast_trace_enqueue_pc(trace, pending, &pending_count,
                            sizeof(pending) / sizeof(pending[0]), target)) {
                    arm64_jit_fast_trace_reject(trace, "pending-b", pc, insn);
                    return false;
                }
                if (!arm64_jit_fast_trace_pop_pc(pending, &pending_count, &pc)) {
                    if (returned_out != NULL)
                        *returned_out = true;
                    return true;
                }
                continue;
            }
            pc = target;
            continue;
        }

        if (info.type == INSN_BRANCH && (insn & 0xff000010u) == 0x54000000u) {
            addr_t branch_target = pc + arm64_branch_imm19(insn);
            addr_t fallthrough_pc = pc + 4;
            if (trace->function_entry) {
                if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                    arm64_jit_fast_trace_reject(trace, "append-function-bcond", pc, insn);
                    return false;
                }
                if (!arm64_jit_fast_trace_enqueue_pc(trace, pending, &pending_count,
                            sizeof(pending) / sizeof(pending[0]), branch_target)) {
                    arm64_jit_fast_trace_reject(trace, "pending-bcond", pc, insn);
                    return false;
                }
                pc = fallthrough_pc;
                continue;
            }
            if (branch_target <= pc && trace->function_entry && depth == 0 &&
                    branch_target >= trace->block.start_pc &&
                    arm64_jit_fast_trace_contains_pc(trace, branch_target)) {
                if (arm64_jit_fast_trace_contains_pc(trace, branch_target)) {
                    if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                        arm64_jit_fast_trace_reject(trace, "append-loop-bcond", pc, insn);
                        return false;
                    }
                    pc = fallthrough_pc;
                    continue;
                }
            }
            addr_t observed = 0;
            addr_t follow = fallthrough_pc;
            if (arm64_jit_fast_trace_observed_edge(pc, &observed) &&
                    (observed == branch_target || observed == fallthrough_pc))
                follow = observed;
            addr_t fallback = follow == branch_target ? fallthrough_pc : branch_target;
            uint32_t fallback_insn = 0;
            if (return_pc != 0 && arm64_jit_read_guest_u32(e, fallback, &fallback_insn) &&
                    fallback_insn == arm64_jit_enc_ret(30))
                fallback = return_pc;
            if (!arm64_jit_fast_trace_append_branch_guard(trace, pc, insn, &info, fallback)) {
                arm64_jit_fast_trace_reject(trace, "append-bcond-guard", pc, insn);
                return false;
            }
            pc = follow;
            continue;
        }

        if (info.type == INSN_BRANCH && (insn & 0x7e000000u) == 0x34000000u) {
            addr_t branch_target = pc + arm64_branch_imm19(insn);
            addr_t fallthrough_pc = pc + 4;
            if (trace->function_entry) {
                if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                    arm64_jit_fast_trace_reject(trace, "append-function-cbz", pc, insn);
                    return false;
                }
                if (!arm64_jit_fast_trace_enqueue_pc(trace, pending, &pending_count,
                            sizeof(pending) / sizeof(pending[0]), branch_target)) {
                    arm64_jit_fast_trace_reject(trace, "pending-cbz", pc, insn);
                    return false;
                }
                pc = fallthrough_pc;
                continue;
            }
            if (branch_target <= pc && trace->function_entry && depth == 0 &&
                    branch_target >= trace->block.start_pc &&
                    arm64_jit_fast_trace_contains_pc(trace, branch_target)) {
                if (arm64_jit_fast_trace_contains_pc(trace, branch_target)) {
                    if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                        arm64_jit_fast_trace_reject(trace, "append-loop-cbz", pc, insn);
                        return false;
                    }
                    pc = fallthrough_pc;
                    continue;
                }
            }
            addr_t observed = 0;
            addr_t follow = fallthrough_pc;
            if (arm64_jit_fast_trace_observed_edge(pc, &observed) &&
                    (observed == branch_target || observed == fallthrough_pc))
                follow = observed;
            addr_t fallback = follow == branch_target ? fallthrough_pc : branch_target;
            uint32_t fallback_insn = 0;
            if (return_pc != 0 && arm64_jit_read_guest_u32(e, fallback, &fallback_insn) &&
                    fallback_insn == arm64_jit_enc_ret(30))
                fallback = return_pc;
            if (!arm64_jit_fast_trace_append_branch_guard(trace, pc, insn, &info, fallback)) {
                arm64_jit_fast_trace_reject(trace, "append-cbz-guard", pc, insn);
                return false;
            }
            pc = follow;
            continue;
        }

        if (info.type == INSN_BRANCH && (insn & 0x7e000000u) == 0x36000000u) {
            addr_t branch_target = pc + arm64_branch_imm14(insn);
            addr_t fallthrough_pc = pc + 4;
            if (trace->function_entry) {
                if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                    arm64_jit_fast_trace_reject(trace, "append-function-tbz", pc, insn);
                    return false;
                }
                if (!arm64_jit_fast_trace_enqueue_pc(trace, pending, &pending_count,
                            sizeof(pending) / sizeof(pending[0]), branch_target)) {
                    arm64_jit_fast_trace_reject(trace, "pending-tbz", pc, insn);
                    return false;
                }
                pc = fallthrough_pc;
                continue;
            }
            if (branch_target <= pc && trace->function_entry && depth == 0 &&
                    branch_target >= trace->block.start_pc &&
                    arm64_jit_fast_trace_contains_pc(trace, branch_target)) {
                if (arm64_jit_fast_trace_contains_pc(trace, branch_target)) {
                    if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                        arm64_jit_fast_trace_reject(trace, "append-loop-tbz", pc, insn);
                        return false;
                    }
                    pc = fallthrough_pc;
                    continue;
                }
            }
            addr_t observed = 0;
            addr_t follow = fallthrough_pc;
            if (arm64_jit_fast_trace_observed_edge(pc, &observed) &&
                    (observed == branch_target || observed == fallthrough_pc))
                follow = observed;
            addr_t fallback = follow == branch_target ? fallthrough_pc : branch_target;
            uint32_t fallback_insn = 0;
            if (return_pc != 0 && arm64_jit_read_guest_u32(e, fallback, &fallback_insn) &&
                    fallback_insn == arm64_jit_enc_ret(30))
                fallback = return_pc;
            if (!arm64_jit_fast_trace_append_branch_guard(trace, pc, insn, &info, fallback)) {
                arm64_jit_fast_trace_reject(trace, "append-tbz-guard", pc, insn);
                return false;
            }
            pc = follow;
            continue;
        }

        if (info.type == INSN_BRANCH) {
            if ((insn & 0xfe000000u) == 0xd6000000u) {
                if (insn == arm64_jit_enc_ret(30)) {
                    if (trace->function_entry && depth == 0) {
                        if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
                            arm64_jit_fast_trace_reject(trace, "append-ret", pc, insn);
                            return false;
                        }
                        if (arm64_jit_fast_trace_pop_pc(pending, &pending_count, &pc))
                            continue;
                    }
                    if (returned_out != NULL)
                        *returned_out = true;
                    return true;
                }
                addr_t target = 0;
                if (!arm64_jit_fast_trace_resolve_indirect(e, trace, ARM64_RN(insn), &target)) {
                    arm64_jit_fast_trace_reject(trace, "unresolved-indirect", pc, insn);
                    return false;
                }
                if ((insn & ~0x3e0u) == arm64_jit_enc_blr(0) &&
                        !arm64_jit_fast_trace_append_set_lr(trace, pc, pc + 4)) {
                    arm64_jit_fast_trace_reject(trace, "append-blr-lr", pc, insn);
                    return false;
                }
                pc = target;
                continue;
            }
            arm64_jit_fast_trace_reject(trace, "unsupported-branch", pc, insn);
            return false;
        }

        if (!arm64_jit_fast_trace_append(trace, pc, insn, &info)) {
            arm64_jit_fast_trace_reject(trace, "append", pc, insn);
            return false;
        }
        arm64_jit_fast_trace_track_dataflow(e, trace, &info, pc, insn);
        if (info.terminates_fragment) {
            arm64_jit_fast_trace_reject(trace, "terminates-fragment", pc, insn);
            return false;
        }
        pc += 4;
    }
}

static bool arm64_jit_fast_trace_validate_internal_targets(
        struct arm64_jit_fast_trace_build *trace) {
    if (!trace->function_entry || trace->block.insn_count == 0)
        return true;
    addr_t end_pc = trace->block.start_pc + 4;
    for (uint32_t i = 0; i < trace->block.insn_count; i++) {
        if (trace->pcs[i] + 4 > end_pc)
            end_pc = trace->pcs[i] + 4;
    }
    for (uint32_t i = 0; i < trace->block.insn_count; i++) {
        if (trace->synthetic_set_lr[i] || trace->synthetic_branch_guard[i])
            continue;
        uint32_t insn = trace->insns[i];
        addr_t pc = trace->pcs[i];
        addr_t target = 0;
        bool fixed_branch = false;
        uint32_t op = (insn >> 26) & 0x3f;
        if (op == 0x05) {
            target = pc + arm64_branch_imm26(insn);
            fixed_branch = true;
        } else if ((insn & 0xff000010u) == 0x54000000u) {
            target = pc + arm64_branch_imm19(insn);
            fixed_branch = true;
        } else if ((insn & 0x7e000000u) == 0x34000000u) {
            target = pc + arm64_branch_imm19(insn);
            fixed_branch = true;
        } else if ((insn & 0x7e000000u) == 0x36000000u) {
            target = pc + arm64_branch_imm14(insn);
            fixed_branch = true;
        }
        if (!fixed_branch || target < trace->block.start_pc || target >= end_pc)
            continue;
        if (!arm64_jit_fast_trace_contains_pc(trace, target)) {
            arm64_jit_fast_trace_reject(trace, "missing-internal-target", pc, insn);
            return false;
        }
    }
    return true;
}

static bool arm64_jit_fast_trace_has_local_backedge(
        const struct arm64_jit_fast_trace_build *trace) {
    if (!trace->function_entry)
        return false;
    for (uint32_t i = 0; i < trace->block.insn_count; i++) {
        if (trace->synthetic_set_lr[i] || trace->synthetic_branch_guard[i])
            continue;
        uint32_t insn = trace->insns[i];
        addr_t pc = trace->pcs[i];
        addr_t target = 0;
        bool fixed_branch = false;
        uint32_t op = (insn >> 26) & 0x3f;
        if (op == 0x05) {
            target = pc + arm64_branch_imm26(insn);
            fixed_branch = true;
        } else if ((insn & 0xff000010u) == 0x54000000u) {
            target = pc + arm64_branch_imm19(insn);
            fixed_branch = true;
        } else if ((insn & 0x7e000000u) == 0x34000000u) {
            target = pc + arm64_branch_imm19(insn);
            fixed_branch = true;
        } else if ((insn & 0x7e000000u) == 0x36000000u) {
            target = pc + arm64_branch_imm14(insn);
            fixed_branch = true;
        }
        if (fixed_branch && target < pc && arm64_jit_fast_trace_contains_pc(trace, target))
            return true;
    }
    return false;
}

static bool arm64_jit_fast_trace_prepare_block(struct arm64_jit_fast_trace_build *trace,
        struct arm64_jit_block *block, addr_t source_pc, addr_t target_pc,
        uint32_t source_insn) {
    memset(block, 0, sizeof(*block));
    uint32_t count = trace->block.insn_count + (trace->function_entry ? 0 : 1);
    block->insn_pcs = calloc(count, sizeof(*block->insn_pcs));
    block->insns = calloc(count, sizeof(*block->insns));
    block->infos = calloc(count, sizeof(*block->infos));
    block->insn_host_offsets = malloc(count * sizeof(*block->insn_host_offsets));
    block->entry_code = calloc(count, sizeof(*block->entry_code));
    if (block->insn_pcs == NULL || block->insns == NULL || block->infos == NULL ||
            block->insn_host_offsets == NULL || block->entry_code == NULL)
        return false;
    for (uint32_t i = 0; i < count; i++)
        block->insn_host_offsets[i] = UINT32_MAX;
    list_init(&block->hash_chain);
    list_init(&block->page[0]);
    list_init(&block->page[1]);
    list_init(&block->jetsam);
    list_init(&block->entrypoints);
    block->insn_cap = count;
    block->insn_count = count;
    block->start_pc = source_pc;
    block->end_pc = source_pc + 4;
    block->terminal_interrupt = INT_NONE;
    block->disable_local_fixups = !trace->function_entry;
    block->is_fast_trace = true;
    (void) source_insn;
    block->fast_trace_jit_handoff_safe =
            trace->function_entry ||
            (trace->synthetic_branch_guard_count == 0 && trace->guard_count == 0);

    uint32_t dst = 0;
    if (!trace->function_entry) {
        block->insn_pcs[0] = source_pc;
        block->insns[0] = source_insn;
        memset(&block->infos[0], 0, sizeof(block->infos[0]));
        block->infos[0].gpr_use_count = 1;
        block->infos[0].gpr_uses[0].reg = 30;
        block->infos[0].gpr_uses[0].flags = ARM64_JIT_USE_WRITE;
        dst = 1;
    }

    for (uint32_t i = 0; i < trace->block.insn_count; i++) {
        block->insn_pcs[dst + i] = trace->pcs[i];
        block->insns[dst + i] = trace->insns[i];
        block->infos[dst + i] = trace->infos[i];
        if (trace->pcs[i] + 4 > block->end_pc)
            block->end_pc = trace->pcs[i] + 4;
    }
    (void) target_pc;
    arm64_jit_build_fragment_gpr_map(block);
    return true;
}

static bool arm64_jit_emit_fast_trace_guard_prelude(struct arm64_jit_emitter *e,
        const struct arm64_jit_fast_trace_build *trace, uint32_t *miss_branches,
        uint32_t *miss_branch_count, uint32_t miss_branch_cap) {
    *miss_branch_count = 0;
    for (uint32_t i = 0; i < trace->guard_count; i++) {
        if (*miss_branch_count + 2 > miss_branch_cap)
            return false;
        uint64_t expected = trace->guard_value[i];
        if (arm64_jit_fast_force_guard_fail_mode())
            expected ^= 1u;
        uint64_t tlb_index = TLB_INDEX(trace->guard_addr[i]);
        uint64_t tlb_entry_off = offsetof(struct tlb, entries) +
                tlb_index * sizeof(struct tlb_entry);
        uint64_t page = TLB_PAGE(trace->guard_addr[i]);
        uint64_t page_off = trace->guard_addr[i] & 0xfffu;
        arm64_jit_emit_load_imm64(e, 15, tlb_entry_off);
        arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(15, ARM64_JIT_HOST_TLB, 15, 0));
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(16, 15, 0));
        arm64_jit_emit_load_imm64(e, 17, page);
        arm64_jit_emit32(e, arm64_jit_enc_eor_reg64(16, 16, 17));
        miss_branches[(*miss_branch_count)++] = (uint32_t) e->size;
        arm64_jit_emit32(e, arm64_jit_enc_cbz_cbnz(true, true, 16, 0));
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(16, 15, 2));
        arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(16, 16, 17, 0));
        if (page_off != 0) {
            arm64_jit_emit_load_imm64(e, 14, page_off);
            arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(16, 16, 14, 0));
        }
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(16, 16, 0));
        arm64_jit_emit_load_imm64(e, 17, expected);
        arm64_jit_emit32(e, arm64_jit_enc_cmp_reg64(16, 17));
        miss_branches[(*miss_branch_count)++] = (uint32_t) e->size;
        arm64_jit_emit32(e, arm64_jit_enc_b_cond(COND_NE, 0));
    }
    return true;
}

static enum arm64_cond arm64_jit_inverse_cond(enum arm64_cond cond) {
    return (enum arm64_cond) ((uint32_t) cond ^ 1u);
}

static bool arm64_jit_emit_fast_trace_body(struct arm64_jit_emitter *e,
        const struct arm64_jit_fast_trace_build *trace, addr_t source_pc) {
    if (!trace->function_entry)
        arm64_jit_emit_set_guest_lr(e, source_pc + 4);
    for (uint32_t i = 0; i < trace->block.insn_count; i++) {
        addr_t pc = trace->pcs[i];
        uint32_t insn = trace->insns[i];
        const struct arm64_jit_insn_info *info = &trace->infos[i];
        uint32_t block_index = trace->function_entry ? i : i + 1;
        if (block_index < e->block->insn_count) {
            e->block->insn_host_offsets[block_index] = (uint32_t) e->size;
            arm64_jit_record_pc_map(e, pc);
        }
        if (trace->synthetic_set_lr[i]) {
            arm64_jit_emit_set_guest_lr(e, trace->synthetic_lr[i]);
            continue;
        }
        if (trace->synthetic_branch_guard[i]) {
            addr_t branch_target = pc + arm64_branch_imm19(insn);
            addr_t fallthrough_pc = pc + 4;
            addr_t fallback_pc = trace->synthetic_branch_fallback_pc[i];
            uint32_t guard_insn = insn;
            if ((insn & 0xff000010u) == 0x54000000u) {
                enum arm64_cond cond = (enum arm64_cond) (insn & 0xf);
                enum arm64_cond success_cond =
                        fallback_pc == fallthrough_pc ? cond : arm64_jit_inverse_cond(cond);
                guard_insn = arm64_jit_enc_b_cond(success_cond, 0);
            } else if ((insn & 0x7e000000u) == 0x34000000u) {
                branch_target = pc + arm64_branch_imm19(insn);
                uint32_t rt = ARM64_RT(insn);
                int host_rt = arm64_jit_guest_src_host_reg(e->block, rt, false);
                if (host_rt < 0)
                    return false;
                bool sf = ((insn >> 31) & 1) != 0;
                bool nonzero = ((insn >> 24) & 1) != 0;
                bool success_nonzero = fallback_pc == fallthrough_pc ? nonzero : !nonzero;
                guard_insn = arm64_jit_enc_cbz_cbnz(sf, success_nonzero,
                        (unsigned) host_rt, 0);
            } else if ((insn & 0x7e000000u) == 0x36000000u) {
                branch_target = pc + arm64_branch_imm14(insn);
                uint32_t rt = ARM64_RT(insn);
                int host_rt = arm64_jit_guest_src_host_reg(e->block, rt, false);
                if (host_rt < 0)
                    return false;
                bool b5 = ((insn >> 31) & 1) != 0;
                bool nonzero = ((insn >> 24) & 1) != 0;
                unsigned bit40 = (insn >> 19) & 0x1f;
                bool success_nonzero = fallback_pc == fallthrough_pc ? nonzero : !nonzero;
                guard_insn = arm64_jit_enc_tbz_tbnz(b5, success_nonzero, bit40,
                        (unsigned) host_rt, 0);
            } else {
                return false;
            }
            uint32_t success_branch = (uint32_t) e->size;
            arm64_jit_emit32(e, guard_insn);
            arm64_jit_emit_spill_cached_state(e);
            arm64_jit_emit_publish_resume_pc(e, fallback_pc);
            arm64_jit_emit_exit_epilogue_branch(e);
            arm64_jit_patch_cond_branch_to_here(e, success_branch);
            (void) branch_target;
            continue;
        }
        enum arm64_jit_emit_result res = arm64_jit_emit_one(e, info, insn, pc);
        if (trace->function_entry && res == ARM64_JIT_EMIT_TERMINATE)
            continue;
        if (res != ARM64_JIT_EMIT_CONTINUE) {
            if (arm64_jit_trace_mode()) {
                fprintf(stderr,
                        "[arm64-jit-fast] emit-body-fail pc=0x%llx insn=0x%08x res=%d index=%u count=%u function=%u\n",
                        (unsigned long long) pc, insn, res, i,
                        trace->block.insn_count,
                        trace->function_entry ? 1u : 0u);
            }
            return false;
        }
        if (!trace->synthetic_set_lr[i] && !trace->synthetic_branch_guard[i] &&
                (info->type != INSN_BRANCH || arm64_jit_branch_has_fallthrough(insn))) {
            addr_t fallthrough_pc = pc + 4;
            addr_t layout_next_pc = i + 1 < trace->block.insn_count ?
                    trace->pcs[i + 1] : 0;
            if (layout_next_pc != fallthrough_pc &&
                    arm64_jit_fast_trace_contains_pc(trace, fallthrough_pc))
                arm64_jit_emit_internal_fallthrough(e, pc, fallthrough_pc);
        }
    }
    return true;
}

static bool arm64_jit_emit_fast_trace_contents(struct arm64_jit_emitter *e,
        const struct arm64_jit_fast_trace_build *trace, addr_t source_pc) {
    struct arm64_jit_block *block = e->block;
    arm64_jit_emit_prologue(e);
    uint32_t guard_miss_branches[32];
    uint32_t guard_miss_branch_count = 0;
    if (!arm64_jit_emit_fast_trace_guard_prelude(e, trace, guard_miss_branches,
                &guard_miss_branch_count,
                sizeof(guard_miss_branches) / sizeof(guard_miss_branches[0])))
        return false;

    arm64_jit_emit_load_cached_state(e);
    if (!trace->function_entry) {
        block->insn_host_offsets[0] = (uint32_t) e->size;
        arm64_jit_record_pc_map(e, source_pc);
    }
    if (!arm64_jit_emit_fast_trace_body(e, trace, source_pc))
        return false;
    if (!trace->function_entry) {
        arm64_jit_emit_fast_trace_jit_return(e);
    }

    for (uint32_t i = 0; i < guard_miss_branch_count; i++)
        arm64_jit_patch_cond_branch_to_here(e, guard_miss_branches[i]);
    arm64_jit_emit_publish_resume_pc(e, source_pc);
    arm64_jit_emit_exit_epilogue_branch(e);

    uint32_t exit_epilogue_off = (uint32_t) e->size;
    arm64_jit_emit_epilogue(e);
    arm64_jit_patch_exit_epilogue_branches(e, exit_epilogue_off);

    block->body_code_size = (uint32_t) e->size;
    block->spill_code_offset = (uint32_t) e->size;
    block->spill_state_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_spill_cached_state(e);
    arm64_jit_emit_state_snippet_ret(e);

    block->light_spill_code_offset = (uint32_t) e->size;
    block->light_spill_state_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_light_spill_cached_state(e);
    arm64_jit_emit_state_snippet_ret(e);

    block->reload_code_offset = (uint32_t) e->size;
    block->reload_state_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_load_cached_state(e);
    arm64_jit_emit_state_snippet_ret(e);

    block->entry_thunks_offset = UINT32_MAX;
    block->c_entry_fn = e->dry_run ? NULL : e->buf;
    block->entry_code[0] = e->dry_run ? NULL : e->buf;
    block->jit_entry_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_fast_trace_jit_entry_snippet(e, trace, exit_epilogue_off,
            trace->block.start_pc);
    return true;
}

static size_t arm64_jit_estimate_fast_trace_code_size(struct arm64_jit_state *state,
        struct arm64_jit_block *block, const struct arm64_jit_fast_trace_build *trace,
        struct tlb *tlb, addr_t source_pc) {
    arm64_jit_reset_emit_metadata(block);
    struct arm64_jit_emitter dry = {
        .state = state,
        .block = block,
        .tlb = tlb,
        .buf = NULL,
        .cap = SIZE_MAX,
        .size = 0,
        .overflowed = false,
        .dry_run = true,
    };
    if (!arm64_jit_emit_fast_trace_contents(&dry, trace, source_pc) ||
            dry.overflowed || dry.size > UINT32_MAX) {
        arm64_jit_reset_emit_metadata(block);
        return 0;
    }
    arm64_jit_reset_emit_metadata(block);
    return arm64_jit_code_cap_for_estimate(dry.size);
}

static bool arm64_jit_emit_fast_trace_block(struct arm64_jit_state *state,
        struct arm64_jit_block *block, const struct arm64_jit_fast_trace_build *trace,
        struct tlb *tlb, addr_t source_pc) {
    size_t cap = arm64_jit_estimate_fast_trace_code_size(state, block, trace, tlb, source_pc);
    if (cap == 0 || cap > UINT32_MAX)
        return false;
    arm64_jit_begin_code_batch(state, cap);
    uint8_t *buf = NULL;
    if (!arm64_jit_alloc_code(state, block, cap, &buf)) {
        arm64_jit_abort_code_batch(state);
        return false;
    }
    arm64_jit_reset_emit_metadata(block);
    struct arm64_jit_emitter e = {
        .state = state,
        .block = block,
        .tlb = tlb,
        .buf = buf,
        .cap = cap,
        .size = 0,
        .overflowed = false,
        .dry_run = false,
    };
    if (!arm64_jit_emit_fast_trace_contents(&e, trace, source_pc) || e.overflowed ||
            !arm64_jit_patch_local_fixups(block, e.buf)) {
        arm64_jit_abort_code_batch(state);
        arm64_jit_free_code(block);
        arm64_jit_reset_emit_metadata(block);
        return false;
    }
    block->code_size = (uint32_t) e.size;
    if (!arm64_jit_finish_code_batch(state)) {
        arm64_jit_free_code(block);
        return false;
    }
    arm64_jit_profile_fast_trace_emit(ARM64_JIT_FAST_TRACE_EXPANDED);
    return true;
}

struct arm64_jit_block *arm64_jit_compile_fast_trace(struct arm64_jit_state *state,
        addr_t source_pc, addr_t target_pc, uint32_t kind, struct tlb *tlb) {
    if (state == NULL || tlb == NULL || !arm64_jit_fast_mode() ||
            arm64_jit_verify_mode())
        return NULL;
    uint32_t source_insn = 0;
    if (!arm64_jit_read_guest_u32(&(struct arm64_jit_emitter) { .tlb = tlb },
                source_pc, &source_insn))
        return NULL;
    uint32_t op = (source_insn >> 26) & 0x3f;
    bool is_fixed_bl = kind == ARM64_JIT_EDGE_DISPATCH && op == 0x25 &&
            source_pc + arm64_branch_imm26(source_insn) == target_pc;
    bool is_observed_blr = kind == ARM64_JIT_EDGE_BRANCH_REG &&
            (source_insn & ~0x3e0u) == arm64_jit_enc_blr(0) && target_pc != 0;
    if (!is_fixed_bl && !is_observed_blr)
        return NULL;

    struct arm64_jit_fast_trace_build trace;
    memset(&trace, 0, sizeof(trace));
    trace.block.start_pc = target_pc;
    trace.block.insn_pcs = trace.pcs;
    trace.block.insns = trace.insns;
    trace.block.infos = trace.infos;
    trace.block.insn_count = 0;
    trace.block.insn_cap = sizeof(trace.pcs) / sizeof(trace.pcs[0]);
    trace.block.disable_local_fixups = false;

    struct arm64_jit_emitter builder = {
        .state = state,
        .tlb = tlb,
        .dry_run = true,
    };
    bool returned = false;
    if (!arm64_jit_fast_trace_build_from(&builder, &trace, target_pc,
                source_pc + 4, 0, &returned) ||
            !returned ||
            trace.block.insn_count == 0) {
        if (arm64_jit_trace_mode() && trace.reject_reason != NULL) {
            fprintf(stderr,
                    "[arm64-jit-fast] reject source=0x%llx target=0x%llx kind=%u reason=%s pc=0x%llx insn=0x%08x count=%u\n",
                    (unsigned long long) source_pc,
                    (unsigned long long) target_pc,
                    kind,
                    trace.reject_reason,
                    (unsigned long long) trace.reject_pc,
                    trace.reject_insn,
                    trace.block.insn_count);
        }
        return NULL;
    }

    struct arm64_jit_block *block = calloc(1, sizeof(*block));
    if (block == NULL)
        return NULL;
    if (!arm64_jit_fast_trace_prepare_block(&trace, block, source_pc, target_pc, source_insn) ||
            !arm64_jit_emit_fast_trace_block(state, block, &trace, tlb, source_pc)) {
        arm64_jit_free_code(block);
        free(block->insn_pcs);
        free(block->insns);
        free(block->infos);
        free(block->insn_host_offsets);
        free(block->entry_code);
        free(block);
        return NULL;
    }
    if (arm64_jit_trace_mode()) {
        fprintf(stderr,
                "[arm64-jit-fast] standalone source=0x%llx target=0x%llx insns=%u guards=%u branch_guards=%u jit_handoff=%u code=%u\n",
                (unsigned long long) source_pc,
                (unsigned long long) target_pc,
                trace.block.insn_count,
                trace.guard_count,
                trace.synthetic_branch_guard_count,
                block->fast_trace_jit_handoff_safe ? 1u : 0u,
                block->code_size);
    }
    return block;
}

struct arm64_jit_block *arm64_jit_compile_fast_function(struct arm64_jit_state *state,
        addr_t entry_pc, struct tlb *tlb) {
    if (state == NULL || tlb == NULL || !arm64_jit_fast_mode() ||
            arm64_jit_verify_mode() || entry_pc == 0)
        return NULL;

    struct arm64_jit_fast_trace_build trace;
    memset(&trace, 0, sizeof(trace));
    trace.block.start_pc = entry_pc;
    trace.block.insn_pcs = trace.pcs;
    trace.block.insns = trace.insns;
    trace.block.infos = trace.infos;
    trace.block.insn_count = 0;
    trace.block.insn_cap = sizeof(trace.pcs) / sizeof(trace.pcs[0]);
    trace.block.disable_local_fixups = false;
    trace.function_entry = true;

    struct arm64_jit_emitter builder = {
        .state = state,
        .tlb = tlb,
        .dry_run = true,
    };
    bool returned = false;
    if (!arm64_jit_fast_trace_build_from(&builder, &trace, entry_pc, 0, 0, &returned) ||
            (!returned && !trace.closed_loop) || trace.block.insn_count == 0) {
        if (arm64_jit_trace_mode() && trace.reject_reason != NULL) {
            fprintf(stderr,
                    "[arm64-jit-fast] reject-function entry=0x%llx reason=%s pc=0x%llx insn=0x%08x count=%u\n",
                    (unsigned long long) entry_pc,
                    trace.reject_reason,
                    (unsigned long long) trace.reject_pc,
                    trace.reject_insn,
                    trace.block.insn_count);
        }
        return NULL;
    }
    if (!arm64_jit_fast_trace_validate_internal_targets(&trace)) {
        if (arm64_jit_trace_mode()) {
            fprintf(stderr,
                    "[arm64-jit-fast] reject-function entry=0x%llx reason=%s pc=0x%llx insn=0x%08x count=%u\n",
                    (unsigned long long) entry_pc,
                    trace.reject_reason ? trace.reject_reason : "target-validation",
                    (unsigned long long) trace.reject_pc,
                    trace.reject_insn,
                    trace.block.insn_count);
        }
        return NULL;
    }
    if (trace.guard_count != 1 || !arm64_jit_fast_trace_has_local_backedge(&trace)) {
        arm64_jit_fast_trace_reject(&trace, "not-branch-heavy-function", entry_pc, 0);
        if (arm64_jit_trace_mode()) {
            fprintf(stderr,
                    "[arm64-jit-fast] reject-function entry=0x%llx reason=%s pc=0x%llx insn=0x%08x count=%u guards=%u\n",
                    (unsigned long long) entry_pc,
                    trace.reject_reason,
                    (unsigned long long) trace.reject_pc,
                    trace.reject_insn,
                    trace.block.insn_count,
                    trace.guard_count);
        }
        return NULL;
    }

    struct arm64_jit_block *block = calloc(1, sizeof(*block));
    if (block == NULL)
        return NULL;
    bool prepared = arm64_jit_fast_trace_prepare_block(&trace, block, entry_pc, entry_pc, 0);
    bool emitted = prepared &&
            arm64_jit_emit_fast_trace_block(state, block, &trace, tlb, entry_pc);
    if (!prepared || !emitted) {
        if (arm64_jit_trace_mode()) {
            fprintf(stderr,
                    "[arm64-jit-fast] reject-function entry=0x%llx reason=%s insns=%u guards=%u branch_guards=%u\n",
                    (unsigned long long) entry_pc,
                    prepared ? "emit" : "prepare",
                    trace.block.insn_count,
                    trace.guard_count,
                    trace.synthetic_branch_guard_count);
            for (uint32_t i = 0; i < trace.block.insn_count; i++) {
                fprintf(stderr,
                        "[arm64-jit-fast]   trace[%u] pc=0x%llx insn=0x%08x synthetic_lr=%u branch_guard=%u\n",
                        i,
                        (unsigned long long) trace.pcs[i],
                        trace.insns[i],
                        trace.synthetic_set_lr[i] ? 1u : 0u,
                        trace.synthetic_branch_guard[i] ? 1u : 0u);
            }
        }
        arm64_jit_free_code(block);
        free(block->insn_pcs);
        free(block->insns);
        free(block->infos);
        free(block->insn_host_offsets);
        free(block->entry_code);
        free(block);
        return NULL;
    }
    if (arm64_jit_trace_mode()) {
        fprintf(stderr,
                "[arm64-jit-fast] function entry=0x%llx insns=%u guards=%u branch_guards=%u code=%u\n",
                (unsigned long long) entry_pc,
                trace.block.insn_count,
                trace.guard_count,
                trace.synthetic_branch_guard_count,
                block->code_size);
    }
    return block;
}

static bool arm64_jit_emit_inline_scalar_regoff_tlb(struct arm64_jit_emitter *e,
        uint32_t insn, addr_t guest_pc, bool is_load,
        unsigned addr_reg, int value_or_dst_host,
        int writeback_host, int64_t writeback_delta, bool post_index,
        uint32_t writeback_guest, bool writeback_sp_not_zr,
        void *fallback_helper, uint64_t fallback_packed) {
    uint32_t size = (insn >> 30) & 0x3;
    (void) guest_pc;

    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, addr_reg));

    // Reject page-crossing accesses; the shared helper owns split/fault cases.
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (1u << size) - 1u);
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    uint32_t page_cross_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_TMP0); // cbnz x0, fallback

    // x0 = tlb entry, x1 = guest page, x16/x17 scratch.
    arm64_jit_emit32(e, arm64_jit_enc_eor_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP2, 1, 13));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    arm64_jit_emit32(e, 0x92403000u); // and x0, x0, #0x1fff
    arm64_jit_emit32(e, arm64_jit_enc_add_imm64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TLB, 32));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP0, 5));
    arm64_jit_emit32(e, 0x9274cc51u); // and x17, x2, #0xfffffffffffff000
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0,
            is_load ? 0 : 1));
    arm64_jit_emit32(e, arm64_jit_enc_eor_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1));
    uint32_t tlb_miss_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_HELPER0); // cbnz x16, fallback
    if (!is_load)
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TLB, 1));
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 2));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));

    if (is_load) {
        unsigned dst = value_or_dst_host >= 0 ? (unsigned) value_or_dst_host : ARM64_JIT_HOST_TMP1;
        uint32_t rt = ARM64_RT(insn);
        uint32_t opc = (insn >> 22) & 0x3;
        if (opc == 2) {
            if (size == 0)
                arm64_jit_emit32(e, arm64_jit_enc_ldrsb_uimm(dst, ARM64_JIT_HOST_HELPER0, 0, true));
            else if (size == 1)
                arm64_jit_emit32(e, arm64_jit_enc_ldrsh_uimm(dst, ARM64_JIT_HOST_HELPER0, 0, true));
            else
                arm64_jit_emit32(e, arm64_jit_enc_ldrsw_uimm(dst, ARM64_JIT_HOST_HELPER0, 0));
        } else if (opc == 3) {
            if (size == 0)
                arm64_jit_emit32(e, arm64_jit_enc_ldrsb_uimm(dst, ARM64_JIT_HOST_HELPER0, 0, false));
            else
                arm64_jit_emit32(e, arm64_jit_enc_ldrsh_uimm(dst, ARM64_JIT_HOST_HELPER0, 0, false));
        } else {
            arm64_jit_emit32(e, arm64_jit_enc_ldr_size_uimm0(dst, ARM64_JIT_HOST_HELPER0, size));
        }
        if (value_or_dst_host < 0 && rt != 31) {
            arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(dst, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rt]) >> 3)));
        }
    } else {
        arm64_jit_emit32(e, arm64_jit_enc_str_size_uimm0((unsigned) value_or_dst_host,
                ARM64_JIT_HOST_HELPER0, size));
    }

    if (writeback_host >= 0) {
        unsigned wb = (unsigned) writeback_host;
        if (post_index && writeback_delta != 0) {
            uint64_t abs_delta = writeback_delta < 0 ?
                    (uint64_t) -writeback_delta : (uint64_t) writeback_delta;
            if (writeback_delta < 0)
                arm64_jit_emit32(e, arm64_jit_enc_sub_imm64(wb, ARM64_JIT_HOST_TMP2,
                        (unsigned) abs_delta));
            else
                arm64_jit_emit32(e, arm64_jit_enc_add_imm64(wb, ARM64_JIT_HOST_TMP2,
                        (unsigned) abs_delta));
        } else if (wb != ARM64_JIT_HOST_TMP2) {
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(wb, ARM64_JIT_HOST_TMP2));
        }
    }

    uint32_t done_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));

    arm64_jit_patch_cond_branch_to_here(e, page_cross_branch);
    arm64_jit_patch_cond_branch_to_here(e, tlb_miss_branch);
    if (is_load) {
        arm64_jit_emit_helper_success_live_load(e, fallback_helper,
                fallback_packed, ARM64_JIT_HOST_TMP2, value_or_dst_host);
    } else {
        arm64_jit_emit_helper_success_live_store(e, fallback_helper,
                fallback_packed, ARM64_JIT_HOST_TMP2, (unsigned) value_or_dst_host);
    }
    if (writeback_host >= 0)
        arm64_jit_emit_reload_cached_base(e, writeback_guest, writeback_sp_not_zr);
    arm64_jit_patch_b_to_here(e, done_branch);
    return true;
}

static bool arm64_jit_emit_inline_ldxr_tlb(struct arm64_jit_emitter *e,
        uint32_t insn, addr_t guest_pc, unsigned addr_reg, int dst_host) {
    uint32_t size = (insn >> 30) & 0x3;
    uint32_t rt = ARM64_RT(insn);

    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, addr_reg));

    // Reject page-crossing accesses; the C helper owns split/fault cases.
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (1u << size) - 1u);
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    uint32_t page_cross_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_TMP0); // cbnz x0, fallback

    // x0 = tlb entry, x2 = guest address, x16/x17 scratch.
    arm64_jit_emit32(e, arm64_jit_enc_eor_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP2, 1, 13));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    arm64_jit_emit32(e, 0x92403000u); // and x0, x0, #0x1fff
    arm64_jit_emit32(e, arm64_jit_enc_add_imm64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TLB, 32));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP0, 5));
    arm64_jit_emit32(e, 0x9274cc51u); // and x17, x2, #0xfffffffffffff000
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 0));
    arm64_jit_emit32(e, arm64_jit_enc_eor_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1));
    uint32_t tlb_miss_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_HELPER0); // cbnz x16, fallback
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 2));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));

    unsigned dst = dst_host >= 0 ? (unsigned) dst_host : ARM64_JIT_HOST_TMP1;
    arm64_jit_emit32(e, arm64_jit_enc_ldr_size_uimm0(dst, ARM64_JIT_HOST_HELPER0, size));
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(excl_addr) >> 3)));
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(dst, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(excl_val) >> 3)));
    if (dst_host < 0 && rt != 31) {
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(dst, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[rt]) >> 3)));
    }

    uint32_t done_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));

    arm64_jit_patch_cond_branch_to_here(e, page_cross_branch);
    arm64_jit_patch_cond_branch_to_here(e, tlb_miss_branch);
    arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_ldst_excl_success_jitabi, guest_pc, insn);
    arm64_jit_patch_b_to_here(e, done_branch);
    return true;
}

static bool arm64_jit_emit_inline_stxr_tlb(struct arm64_jit_emitter *e,
        uint32_t insn, addr_t guest_pc, unsigned addr_reg, int value_host, int status_host) {
    uint32_t size = (insn >> 30) & 0x3;
    uint32_t rs = (insn >> 16) & 0x1f;
    bool acquire_release = ((insn >> 15) & 1) != 0;
    if (value_host < 0)
        return false;

    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, addr_reg));

    // Reject page-crossing accesses; the C helper owns split/fault cases.
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (1u << size) - 1u);
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    uint32_t page_cross_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_TMP0); // cbnz x0, fallback

    // x0 = tlb entry, x2 = guest address, x16/x17 scratch.
    arm64_jit_emit32(e, arm64_jit_enc_eor_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP2, 1, 13));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    arm64_jit_emit32(e, 0x92403000u); // and x0, x0, #0x1fff
    arm64_jit_emit32(e, arm64_jit_enc_add_imm64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TLB, 32));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP0, 5));
    arm64_jit_emit32(e, 0x9274cc51u); // and x17, x2, #0xfffffffffffff000
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 1));
    arm64_jit_emit32(e, arm64_jit_enc_eor_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1));
    uint32_t tlb_miss_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_HELPER0); // cbnz x16, fallback
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TLB, 1));
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 2));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));

    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(excl_addr) >> 3)));
    arm64_jit_emit32(e, 0xd53b421e); // mrs x30, nzcv
    arm64_jit_emit32(e, arm64_jit_enc_cmp_reg64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP2));
    uint32_t monitor_fail_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_cond(COND_NE, 0));

    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(excl_val) >> 3)));
    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_HELPER1));
    unsigned desired = ARM64_JIT_HOST_TMP3;
    if ((unsigned) value_host != desired)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(desired, (unsigned) value_host));
    arm64_jit_emit32(e, arm64_jit_enc_cas_size(ARM64_JIT_HOST_HELPER1, desired,
            ARM64_JIT_HOST_HELPER0, size, acquire_release));
    if (size == 3)
        arm64_jit_emit32(e, arm64_jit_enc_cmp_reg64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP1));
    else
        arm64_jit_emit32(e, arm64_jit_enc_cmp_reg32(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP1));
    unsigned status = status_host >= 0 ? (unsigned) status_host : ARM64_JIT_HOST_TMP1;
    arm64_jit_emit32(e, arm64_jit_enc_cset32(status, COND_NE));
    uint32_t clear_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));

    arm64_jit_patch_cond_branch_to_here(e, monitor_fail_branch);
    arm64_jit_emit32(e, arm64_jit_enc_movz(status, 1, 0));

    uint32_t clear_pc = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xd51b421e); // msr nzcv, x30
    arm64_jit_emit32(e, arm64_jit_enc_movn64(ARM64_JIT_HOST_HELPER1, 0, 0));
    arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_CPU,
            (CPU_OFFSET(excl_addr) >> 3)));
    if (status_host < 0 && rs != 31) {
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(status, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[rs]) >> 3)));
    }

    uint32_t done_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));

    arm64_jit_patch_cond_branch_to_here(e, page_cross_branch);
    arm64_jit_patch_cond_branch_to_here(e, tlb_miss_branch);
    arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_ldst_excl_success_jitabi, guest_pc, insn);
    if (!e->dry_run && e->buf != NULL) {
        uint32_t *clear_slot = (uint32_t *) (e->buf + clear_branch);
        int32_t clear_delta = (int32_t) clear_pc - (int32_t) clear_branch;
        *clear_slot = arm64_jit_enc_b_imm(clear_delta >> 2);
    }
    arm64_jit_patch_b_to_here(e, done_branch);
    return true;
}

static bool arm64_jit_simd_ldst_width(uint32_t insn, uint32_t *width_out) {
    uint32_t size = (insn >> 30) & 0x3;
    uint32_t opc = (insn >> 22) & 0x3;
    if (size == 0 && (opc & 0x2)) {
        *width_out = 16; // Qt
        return true;
    }
    if (opc >= 2)
        return false;
    *width_out = 1u << size; // Bt/Ht/St/Dt
    return true;
}

static bool arm64_jit_emit_inline_simd_uimm_tlb(struct arm64_jit_emitter *e,
        uint32_t insn, bool is_load, unsigned addr_reg,
        void *fallback_helper, uint64_t fallback_packed) {
    uint32_t width = 0;
    if (!arm64_jit_simd_ldst_width(insn, &width))
        return false;

    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, addr_reg));

    // Reject page-crossing accesses; the shared helper owns split/fault cases.
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, width - 1u);
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    uint32_t page_cross_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_TMP0); // cbnz x0, fallback

    // x0 = tlb entry, x16 = guest page, x17 scratch.
    arm64_jit_emit32(e, arm64_jit_enc_eor_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP2, 1, 13));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    arm64_jit_emit32(e, 0x92403000u); // and x0, x0, #0x1fff
    arm64_jit_emit32(e, arm64_jit_enc_add_imm64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TLB, 32));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP0, 5));
    arm64_jit_emit32(e, 0x9274cc51u); // and x17, x2, #0xfffffffffffff000
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0,
            is_load ? 0 : 1));
    arm64_jit_emit32(e, arm64_jit_enc_eor_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1));
    uint32_t tlb_miss_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_HELPER0); // cbnz x16, fallback
    if (!is_load)
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TLB, 1));
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 2));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));

    arm64_jit_emit32(e, arm64_jit_enc_simd_ldst_uimm0(insn, ARM64_JIT_HOST_HELPER0));

    uint32_t done_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));

    arm64_jit_patch_cond_branch_to_here(e, page_cross_branch);
    arm64_jit_patch_cond_branch_to_here(e, tlb_miss_branch);
    if (!is_load)
        arm64_jit_emit_spill_cached_vreg(e, ARM64_RT(insn));
    arm64_jit_emit_helper_success_live_addronly(e, fallback_helper, fallback_packed, ARM64_JIT_HOST_TMP2);
    arm64_jit_patch_b_to_here(e, done_branch);
    return true;
}

static bool arm64_jit_emit_inline_scalar_pair_tlb(struct arm64_jit_emitter *e,
        uint32_t insn, bool is_load, unsigned addr_reg,
        int reg0_host, int reg1_host, uint32_t reg0_guest, uint32_t reg1_guest,
        int writeback_host, int64_t writeback_delta,
        bool post_index, void *fallback_helper, uint64_t fallback_packed) {
    uint32_t opcp = (insn >> 30) & 0x3;
    uint32_t size = opcp == 2 ? 3 : 2;
    uint32_t last_byte = (1u << (size + 1)) - 1u;

    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, addr_reg));

    // Reject page-crossing pairs; the shared helper owns split/fault cases.
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, last_byte);
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    uint32_t page_cross_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_TMP0); // cbnz x0, fallback

    // x0 = tlb entry, x2 = guest address, x16/x17 scratch.
    arm64_jit_emit32(e, arm64_jit_enc_eor_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP2, 1, 13));
    arm64_jit_emit32(e, arm64_jit_enc_lsr_imm64(ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP0, 12));
    arm64_jit_emit32(e, 0x92403000u); // and x0, x0, #0x1fff
    arm64_jit_emit32(e, arm64_jit_enc_add_imm64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TLB, 32));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_TMP0, ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP0, 5));
    arm64_jit_emit32(e, 0x9274cc51u); // and x17, x2, #0xfffffffffffff000
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0,
            is_load ? 0 : 1));
    arm64_jit_emit32(e, arm64_jit_enc_eor_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1));
    uint32_t tlb_miss_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, 0xb5000000u | ARM64_JIT_HOST_HELPER0); // cbnz x16, fallback
    if (!is_load)
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TLB, 1));
    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_TMP0, 2));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));
    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_HELPER1, ARM64_JIT_HOST_TMP2, 0, 12));
    arm64_jit_emit32(e, arm64_jit_enc_add_shift_reg64(
            ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_HELPER1, 0));

    if (is_load) {
        unsigned dst0 = reg0_host >= 0 ? (unsigned) reg0_host : 1;
        unsigned dst1 = reg1_host >= 0 ? (unsigned) reg1_host : 2;
        if (opcp == 1) {
            arm64_jit_emit32(e, arm64_jit_enc_ldrsw_uimm(dst0, ARM64_JIT_HOST_HELPER0, 0));
            arm64_jit_emit32(e, arm64_jit_enc_ldrsw_uimm(dst1, ARM64_JIT_HOST_HELPER0, 1));
        } else {
            arm64_jit_emit32(e, arm64_jit_enc_ldr_size_uimm(dst0, ARM64_JIT_HOST_HELPER0, size, 0));
            arm64_jit_emit32(e, arm64_jit_enc_ldr_size_uimm(dst1, ARM64_JIT_HOST_HELPER0, size, 1));
        }
        if (reg0_host < 0 && reg0_guest != 31) {
            arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(dst0, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[reg0_guest]) >> 3)));
        }
        if (reg1_host < 0 && reg1_guest != 31) {
            arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(dst1, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[reg1_guest]) >> 3)));
        }
    } else {
        unsigned src0 = reg0_host >= 0 ? (unsigned) reg0_host : ARM64_JIT_HOST_TMP0;
        unsigned src1 = reg1_host >= 0 ? (unsigned) reg1_host : ARM64_JIT_HOST_TMP1;
        if (reg0_host < 0 && reg0_guest == 31)
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(src0, 31));
        else if (reg0_host < 0)
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(src0, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[reg0_guest]) >> 3)));
        if (reg1_host < 0 && reg1_guest == 31)
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(src1, 31));
        else if (reg1_host < 0)
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(src1, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[reg1_guest]) >> 3)));
        arm64_jit_emit32(e, arm64_jit_enc_str_size_uimm(src0,
                ARM64_JIT_HOST_HELPER0, size, 0));
        arm64_jit_emit32(e, arm64_jit_enc_str_size_uimm(src1,
                ARM64_JIT_HOST_HELPER0, size, 1));
    }

    if (writeback_host >= 0) {
        unsigned wb = (unsigned) writeback_host;
        if (post_index && writeback_delta != 0) {
            uint64_t abs_delta = writeback_delta < 0 ? (uint64_t) -writeback_delta : (uint64_t) writeback_delta;
            if (writeback_delta < 0)
                arm64_jit_emit32(e, arm64_jit_enc_sub_imm64(wb, ARM64_JIT_HOST_TMP2, (unsigned) abs_delta));
            else
                arm64_jit_emit32(e, arm64_jit_enc_add_imm64(wb, ARM64_JIT_HOST_TMP2, (unsigned) abs_delta));
        } else if (wb != ARM64_JIT_HOST_TMP2) {
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(wb, ARM64_JIT_HOST_TMP2));
        }
    }

    uint32_t done_branch = (uint32_t) e->size;
    arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));

    arm64_jit_patch_cond_branch_to_here(e, page_cross_branch);
    arm64_jit_patch_cond_branch_to_here(e, tlb_miss_branch);
    if (is_load) {
        arm64_jit_emit_helper_success_live_load_pair(e, fallback_helper, fallback_packed,
                ARM64_JIT_HOST_TMP2, reg0_host, reg0_guest, reg1_host, reg1_guest);
    } else {
        bool saved_val1_from_x3 = false;
        if (reg1_host == 3 && reg0_host != 3) {
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(17, 3));
            saved_val1_from_x3 = true;
        }
        if (reg0_host >= 0) {
            if (reg0_host != 3)
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg(3, (unsigned) reg0_host));
        } else if (reg0_guest == 31) {
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(3, 31));
        } else {
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(3, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[reg0_guest]) >> 3)));
        }
        if (saved_val1_from_x3) {
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(16, 17));
        } else if (reg1_host >= 0) {
            if (reg1_host != 16)
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg(16, (unsigned) reg1_host));
        } else if (reg1_guest == 31) {
            arm64_jit_emit32(e, arm64_jit_enc_mov_reg(16, 31));
        } else {
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm(16, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[reg1_guest]) >> 3)));
        }
        arm64_jit_emit_helper_success_live_store_pair(e, fallback_helper, fallback_packed,
                ARM64_JIT_HOST_TMP2, 3, 16);
    }
    if (writeback_host >= 0) {
        uint32_t rn = ARM64_RN(insn);
        if (rn == 31) {
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) writeback_host,
                    ARM64_JIT_HOST_CPU, (CPU_OFFSET(sp) >> 3)));
        } else {
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) writeback_host,
                    ARM64_JIT_HOST_CPU, (CPU_OFFSET(regs[rn]) >> 3)));
        }
    }
    arm64_jit_patch_b_to_here(e, done_branch);
    return true;
}

static bool arm64_jit_emit_regoff_addr(struct arm64_jit_emitter *e, uint32_t insn,
        unsigned base_host, unsigned off_host) {
    uint32_t size = (insn >> 30) & 0x3;
    uint32_t option = (insn >> 13) & 0x7;
    uint32_t S = (insn >> 12) & 1;

    if (!(option == 2 || option == 3 || option == 6 || option == 7))
        return false;
    if (base_host != ARM64_JIT_HOST_TMP2)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, base_host));
    if (off_host != ARM64_JIT_HOST_TMP1)
        arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP1, off_host));
    if (option == 2) {
        arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP1, 0, 32));
    } else if (option == 6) {
        arm64_jit_emit32(e, 0x93407c21u); // sxtw x1, w1
    }
    if (S && size != 0) {
        arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP3, size);
        arm64_jit_emit32(e, 0x9ac32021u); // lslv x1, x1, x3
    }
    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
    return true;
}

static bool arm64_jit_local_branch_can_stay_in_fragment(const struct arm64_jit_block *block,
        addr_t guest_pc, addr_t target) {
    if (target == guest_pc)
        return false;
    (void) block;
    return true;
}

static int arm64_jit_simd_elem_size_from_imm5_emit(uint32_t imm5) {
    if (imm5 & 0x1)
        return 0;
    if (imm5 & 0x2)
        return 1;
    if (imm5 & 0x4)
        return 2;
    if (imm5 & 0x8)
        return 3;
    return -1;
}

static int arm64_jit_simd_ldst_multi_num_regs_emit(uint32_t opcode) {
    switch (opcode) {
        case 0x7:
            return 1;
        case 0xa:
            return 2;
        case 0x6:
            return 3;
        case 0x2:
            return 4;
        default:
            return 0;
    }
}

static bool arm64_jit_emit_move_wide_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x1f800000u) != 0x12800000u)
        return false;
    bool sf = ARM64_SF(insn);
    uint32_t rd = ARM64_RD(insn);
    int dst = arm64_jit_host_reg_for_guest(e->block, rd);
    if (dst < 0)
        return false;
    uint32_t opc = (insn >> 29) & 0x3;
    uint32_t hw = (insn >> 21) & 0x3;
    if (!sf && hw >= 2)
        return false;
    uint16_t imm16 = (insn >> 5) & 0xffff;
    if (opc == 0) { // MOVN
        arm64_jit_emit32(e, (sf ? 0x92800000u : 0x12800000u) |
                (hw << 21) | ((uint32_t) imm16 << 5) | (dst & 0x1f));
        return true;
    }
    if (opc == 2) { // MOVZ
        arm64_jit_emit32(e, (sf ? 0xd2800000u : 0x52800000u) |
                (hw << 21) | ((uint32_t) imm16 << 5) | (dst & 0x1f));
        return true;
    }
    if (opc == 3) { // MOVK
        arm64_jit_emit32(e, (sf ? 0xf2800000u : 0x72800000u) |
                (hw << 21) | ((uint32_t) imm16 << 5) | (dst & 0x1f));
        return true;
    }
    return false;
}

static bool arm64_jit_emit_addsub_imm_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if (!((insn & 0x1f000000u) == 0x11000000u || (insn & 0x7f000000u) == 0x31000000u))
        return false;
    bool sf = ARM64_SF(insn);
    bool setflags = (insn >> 29) & 1;
    uint32_t shift = (insn >> 22) & 0x3;
    if (shift > 1)
        return false;
    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    if (setflags) {
        int dst = arm64_jit_guest_src_host_reg_or_zr(e->block, rd);
        int src = arm64_jit_guest_src_host_reg(e->block, rn, true);
        if (dst < 0 || src < 0)
            return false;
        uint32_t emitted = insn;
        emitted &= ~((uint32_t) 0x1f);
        emitted &= ~((uint32_t) 0x1f << 5);
        emitted |= (uint32_t) dst;
        emitted |= (uint32_t) src << 5;
        arm64_jit_emit32(e, emitted);
        return true;
    }
    bool is_sub = (insn >> 30) & 1;
    int dst = (rd == 31) ? ARM64_JIT_HOST_GUEST_SP : arm64_jit_host_reg_for_guest(e->block, rd);
    int src = arm64_jit_guest_src_host_reg(e->block, rn, true);
    if (dst < 0 || src < 0)
        return false;
    uint32_t imm12 = (insn >> 10) & 0xfff;
    uint32_t sh = shift ? 1 : 0;
    uint32_t base;
    if (sf)
        base = is_sub ? 0xd1000000u : 0x91000000u;
    else
        base = is_sub ? 0x51000000u : 0x11000000u;
    arm64_jit_emit32(e, base | ((sh & 0x3) << 22) | ((imm12 & 0xfff) << 10) |
            ((src & 0x1f) << 5) | (dst & 0x1f));
    return true;
}

static void arm64_jit_emit_clear_scalar_s_upper(struct arm64_jit_emitter *e, uint32_t rd) {
    arm64_jit_emit32(e, 0x1e260010u | ((rd & 0x1f) << 5)); // fmov w16, Sd
    arm64_jit_emit32(e, 0x6f00e400u | (rd & 0x1f)); // movi Vd.2D, #0
    arm64_jit_emit32(e, 0x1e270200u | (rd & 0x1f)); // fmov Sd, w16
}

static bool arm64_jit_is_scalar_fp_to_gpr_conversion(uint32_t insn) {
    if ((insn & 0x7f20fc00u) != 0x1e200000u)
        return false;
    uint32_t ftype = (insn >> 22) & 0x3;
    if (ftype > 1)
        return false;
    uint32_t rmode = (insn >> 19) & 0x3;
    uint32_t opcode = (insn >> 16) & 0x7;
    switch (rmode) {
        case 0:
            return opcode == 0 || opcode == 1 || opcode == 4 || opcode == 5; // FCVTN/FCVTA
        case 1:
            return opcode == 0 || opcode == 1; // FCVTP
        case 2:
            return opcode == 0 || opcode == 1; // FCVTM
        case 3:
            return opcode == 0 || opcode == 1; // FCVTZ
        default:
            return false;
    }
}

static bool arm64_jit_emit_simd_fp_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    uint32_t simd_rrr = insn & ~(((uint32_t) 0x1f) | ((uint32_t) 0x1f << 5) |
            ((uint32_t) 0x1f << 16));

    switch (simd_rrr) {
        case 0x1e200800u: // FMUL Sd, Sn, Sm
        case 0x1e201800u: // FDIV Sd, Sn, Sm
        case 0x1e202800u: // FADD Sd, Sn, Sm
        case 0x1e203800u: // FSUB Sd, Sn, Sm
        case 0x1e204800u: // FMAX Sd, Sn, Sm
        case 0x1e205800u: // FMIN Sd, Sn, Sm
        case 0x1e206800u: // FMAXNM Sd, Sn, Sm
        case 0x1e207800u: // FMINNM Sd, Sn, Sm
        case 0x1e220c00u: // FCSEL Sd, Sn, Sm, cond
            arm64_jit_emit32(e, insn);
            arm64_jit_emit_clear_scalar_s_upper(e, ARM64_RD(insn));
            return true;
        case 0x1e600800u: // FMUL Dd, Dn, Dm
        case 0x1e601800u: // FDIV Dd, Dn, Dm
        case 0x1e602800u: // FADD Dd, Dn, Dm
        case 0x1e603800u: // FSUB Dd, Dn, Dm
        case 0x1e604800u: // FMAX Dd, Dn, Dm
        case 0x1e605800u: // FMIN Dd, Dn, Dm
        case 0x1e606800u: // FMAXNM Dd, Dn, Dm
        case 0x1e607800u: // FMINNM Dd, Dn, Dm
        case 0x1e600c00u: // FCSEL Dd, Dn, Dm, cond
            arm64_jit_emit32(e, insn);
            return true;
        default:
            break;
    }
    if ((insn & 0xffe00c00u) == 0x1e200c00u) { // FCSEL Sd, Sn, Sm, cond
        arm64_jit_emit32(e, insn);
        arm64_jit_emit_clear_scalar_s_upper(e, ARM64_RD(insn));
        return true;
    }
    if ((insn & 0xffe00c00u) == 0x1e600c00u) { // FCSEL Dd, Dn, Dm, cond
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e270000u || // FMOV Sd, Wn
            (insn & 0xfffffc00u) == 0x9e670000u) { // FMOV Dd, Xn
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                src = 31;
            else {
                src = ARM64_JIT_HOST_HELPER0;
                arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rn]) >> 3)));
            }
        }
        arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f << 5)) | ((uint32_t) src << 5));
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x9eaf0000u) { // FMOV Vd.D[1], Xn
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                src = 31;
            else {
                src = ARM64_JIT_HOST_HELPER0;
                arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rn]) >> 3)));
            }
        }
        arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f << 5)) | ((uint32_t) src << 5));
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e260000u || // FMOV Wd, Sn
            (insn & 0xfffffc00u) == 0x9e660000u) { // FMOV Xd, Dn
        uint32_t rd = ARM64_RD(insn);
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        if (dst >= 0 || rd >= 31) {
            unsigned host_dst = (dst >= 0) ? (unsigned) dst : 31;
            arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f)) | host_dst);
            return true;
        }
        arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f)) | ARM64_JIT_HOST_HELPER0);
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[rd]) >> 3)));
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x9eae0000u) { // FMOV Xd, Vn.D[1]
        uint32_t rd = ARM64_RD(insn);
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        if (dst >= 0 || rd >= 31) {
            unsigned host_dst = (dst >= 0) ? (unsigned) dst : 31;
            arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f)) | host_dst);
            return true;
        }
        arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f)) | ARM64_JIT_HOST_HELPER0);
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[rd]) >> 3)));
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e204000u) { // FMOV Sd, Sn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e604000u) { // FMOV Dd, Dn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe01fe0u) == 0x1e201000u) { // FMOV Sd, #imm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe01fe0u) == 0x1e601000u) { // FMOV Dd, #imm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if (arm64_jit_is_scalar_fp_to_gpr_conversion(insn)) {
        uint32_t rd = ARM64_RD(insn);
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        if (dst >= 0 || rd >= 31) {
            unsigned host_dst = (dst >= 0) ? (unsigned) dst : 31;
            arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f)) | host_dst);
            return true;
        }
        arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f)) | ARM64_JIT_HOST_HELPER0);
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm(ARM64_JIT_HOST_HELPER0, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(regs[rd]) >> 3)));
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e20c000u) { // FABS Sd, Sn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e60c000u) { // FABS Dd, Dn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e214000u) { // FNEG Sd, Sn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e614000u) { // FNEG Dd, Dn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e21c000u) { // FSQRT Sd, Sn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x1e61c000u) { // FSQRT Dd, Dn
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xff208000u) == 0x1f000000u) { // FMADD/FMSUB/FNMADD/FNMSUB Sd/Dd
        uint32_t ftype = (insn >> 22) & 0x3;
        if (ftype == 0 || ftype == 1) {
            arm64_jit_emit32(e, insn);
            if (ftype == 0)
                arm64_jit_emit_clear_scalar_s_upper(e, ARM64_RD(insn));
            return true;
        }
    }
    switch (insn & ~(((uint32_t) 0x1f) | ((uint32_t) 0x1f << 5))) {
        case 0x1e220000u: // SCVTF Sd, Wn
        case 0x1e620000u: // SCVTF Dd, Wn
        case 0x9e220000u: // SCVTF Sd, Xn
        case 0x9e620000u: // SCVTF Dd, Xn
        case 0x1e230000u: // UCVTF Sd, Wn
        case 0x1e630000u: // UCVTF Dd, Wn
        case 0x9e230000u: // UCVTF Sd, Xn
        case 0x9e630000u: { // UCVTF Dd, Xn
            uint32_t rn = ARM64_RN(insn);
            int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
            if (src < 0) {
                if (rn >= 31)
                    src = 31;
                else {
                    src = ARM64_JIT_HOST_HELPER0;
                    arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                            (CPU_OFFSET(regs[rn]) >> 3)));
                }
            }
            arm64_jit_emit32(e, (insn & ~((uint32_t) 0x1f << 5)) | ((uint32_t) src << 5));
            return true;
        }
        default:
            break;
    }
    if ((insn & 0xffe0fc1fu) == 0x1e202000u) { // FCMP Sn, Sm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe0fc1fu) == 0x1e602000u) { // FCMP Dn, Dm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe0fc1fu) == 0x1e202010u) { // FCMPE Sn, Sm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe0fc1fu) == 0x1e602010u) { // FCMPE Dn, Dm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc1fu) == 0x1e202008u || // FCMP Sn, #0.0
            (insn & 0xfffffc1fu) == 0x1e602008u || // FCMP Dn, #0.0
            (insn & 0xfffffc1fu) == 0x1e202018u || // FCMPE Sn, #0.0
            (insn & 0xfffffc1fu) == 0x1e602018u) { // FCMPE Dn, #0.0
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xff80fc00u) == 0x0f000400u || // MOVI .4H / .2S
            (insn & 0xff80fc00u) == 0x4f000400u || // MOVI .8H / .4S
            (insn & 0xff80fc00u) == 0x0f00e400u || // MOVI .8B
            (insn & 0xff80fc00u) == 0x4f00e400u || // MOVI .16B
            (insn & 0xff80fc00u) == 0x2f000400u || // MVNI .4H / .2S
            (insn & 0xff80fc00u) == 0x6f000400u || // MVNI .8H / .4S
            (insn & 0xff80fc00u) == 0x2f00e400u || // MVNI .8B
            (insn & 0xff80fc00u) == 0x6f00e400u) { // MVNI .16B
        arm64_jit_emit32(e, insn);
        return true;
    }
    {
        uint32_t simd_imm_shift = insn & 0xbf80fc00u;
        uint32_t immh = (insn >> 19) & 0xf;
        if (immh != 0 && (simd_imm_shift == 0x0f005400u || // SHL
                simd_imm_shift == 0x2f000400u || // USHR
                simd_imm_shift == 0x0f000400u || // SSHR
                simd_imm_shift == 0x2f001400u || // USRA
                simd_imm_shift == 0x0f001400u || // SSRA
                simd_imm_shift == 0x0f002400u || // SRSHR
                simd_imm_shift == 0x2f002400u || // URSHR
                simd_imm_shift == 0x0f003400u || // SRSRA
                simd_imm_shift == 0x2f003400u || // URSRA
                simd_imm_shift == 0x0f008400u || // SHRN/SHRN2
                simd_imm_shift == 0x0f008c00u || // RSHRN/RSHRN2
                simd_imm_shift == 0x2f009c00u || // UQRSHRN/UQRSHRN2
                simd_imm_shift == 0x0f009c00u || // SQRSHRN/SQRSHRN2
                simd_imm_shift == 0x2f009400u || // UQSHRN/UQSHRN2
                simd_imm_shift == 0x0f009400u || // SQSHRN/SQSHRN2
                simd_imm_shift == 0x2f008400u || // SQSHRUN/SQSHRUN2
                simd_imm_shift == 0x2f008c00u || // SQRSHRUN/SQRSHRUN2
                simd_imm_shift == 0x2f004400u || // SRI
                simd_imm_shift == 0x2f005400u)) { // SLI
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xbfe0fc00u) == 0x0e000c00u) { // DUP (general) - GPR to vector
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                return false;
            src = ARM64_JIT_HOST_HELPER0;
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rn]) >> 3)));
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f << 5);
        emitted |= (uint32_t) src << 5;
        arm64_jit_emit32(e, emitted);
        return true;
    }
    if ((insn & 0xbfe0fc00u) == 0x0e000400u) { // DUP (element) - vector to vector
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe0fc00u) == 0x5e000400u) { // DUP (element, scalar)
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe0fc00u) == 0x0f00a400u ||
            (insn & 0xffe0fc00u) == 0x0f20a400u ||
            (insn & 0xffe0fc00u) == 0x4f00a400u ||
            (insn & 0xffe0fc00u) == 0x4f20a400u ||
            (insn & 0xffe0fc00u) == 0x2f00a400u ||
            (insn & 0xffe0fc00u) == 0x2f20a400u ||
            (insn & 0xffe0fc00u) == 0x6f00a400u ||
            (insn & 0xffe0fc00u) == 0x6f20a400u) { // SSHLL/SSHLL2/USHLL/USHLL2
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe08400u) == 0x6e000400u) { // INS (element) vector-to-vector
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe0fc00u) == 0x4e003c00u) { // MOV Xd, Vn.D[0]
        uint32_t rd = ARM64_RD(insn);
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        bool storeback = false;
        if (dst < 0) {
            if (rd >= 31)
                return false;
            dst = ARM64_JIT_HOST_HELPER0;
            storeback = true;
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f);
        emitted |= (uint32_t) dst;
        arm64_jit_emit32(e, emitted);
        if (storeback) {
            arm64_jit_emit32(e, arm64_jit_enc_str64_uimm((unsigned) dst, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rd]) >> 3)));
        }
        return true;
    }
    if ((insn & 0xbfe0fc00u) == 0x0e003c00u) { // UMOV/MOV scalar from vector to GPR
        uint32_t imm5 = (insn >> 16) & 0x1f;
        uint32_t rd = ARM64_RD(insn);
        int elem_size = arm64_jit_simd_elem_size_from_imm5_emit(imm5);
        if (elem_size < 0)
            return false;
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        bool storeback = false;
        if (dst < 0) {
            if (rd >= 31)
                return false;
            dst = ARM64_JIT_HOST_HELPER0;
            storeback = true;
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f);
        emitted |= (uint32_t) dst;
        arm64_jit_emit32(e, emitted);
        if (storeback) {
            if (elem_size == 3) {
                arm64_jit_emit32(e, arm64_jit_enc_str64_uimm((unsigned) dst, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rd]) >> 3)));
            } else {
                arm64_jit_emit32(e, arm64_jit_enc_str32_uimm((unsigned) dst, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rd]) >> 3)));
            }
        }
        return true;
    }
    if ((insn & 0xffe0fc00u) == 0x4e001c00u && ((insn >> 16) & 0xf) == 0x8) { // MOV Vd.D[idx], Xn
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                return false;
            src = ARM64_JIT_HOST_HELPER0;
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rn]) >> 3)));
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f << 5);
        emitted |= (uint32_t) src << 5;
        arm64_jit_emit32(e, emitted);
        return true;
    }
    if ((insn & 0xffe7fc00u) == 0x4e041c00u) { // MOV Vd.S[idx], Wn
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                return false;
            src = ARM64_JIT_HOST_HELPER0;
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rn]) >> 3)));
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f << 5);
        emitted |= (uint32_t) src << 5;
        arm64_jit_emit32(e, emitted);
        return true;
    }
    if ((insn & 0xffe0fc00u) == 0x4e001c00u && ((insn >> 16) & 0x3) == 0x2) { // MOV Vd.H[idx], Wn
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                return false;
            src = ARM64_JIT_HOST_HELPER0;
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rn]) >> 3)));
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f << 5);
        emitted |= (uint32_t) src << 5;
        arm64_jit_emit32(e, emitted);
        return true;
    }
    if ((insn & 0xffe0fc00u) == 0x4e001c00u && ((insn >> 16) & 0x1) == 0x1) { // MOV Vd.B[idx], Wn
        uint32_t rn = ARM64_RN(insn);
        int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
        if (src < 0) {
            if (rn >= 31)
                return false;
            src = ARM64_JIT_HOST_HELPER0;
            arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(regs[rn]) >> 3)));
        }
        uint32_t emitted = insn & ~((uint32_t) 0x1f << 5);
        emitted |= (uint32_t) src << 5;
        arm64_jit_emit32(e, emitted);
        return true;
    }
    switch (simd_rrr) {
        case 0x4e201c00u: // AND Vd.16B, Vn.16B, Vm.16B
        case 0x4ea01c00u: // ORR/MOV Vd.16B, Vn.16B, Vm.16B
        case 0x6e201c00u: // EOR Vd.16B, Vn.16B, Vm.16B
        case 0x4e601c00u: // BIC Vd.16B, Vn.16B, Vm.16B
        case 0x4e208400u: // ADD Vd.16B, Vn.16B, Vm.16B
        case 0x6e208400u: // SUB Vd.16B, Vn.16B, Vm.16B
        case 0x6e208c00u: // CMEQ Vd.16B, Vn.16B, Vm.16B
        case 0x6e203400u: // CMHI Vd.16B, Vn.16B, Vm.16B
        case 0x4e203400u: // CMGT Vd.16B, Vn.16B, Vm.16B
        case 0x6e206c00u: // UMIN Vd.16B, Vn.16B, Vm.16B
        case 0x4e206400u: // SMAX Vd.16B, Vn.16B, Vm.16B
        case 0x4e000000u: // TBL Vd.16B, {Vn.16B}, Vm.16B
        case 0x4e001000u: // TBX Vd.16B, {Vn.16B}, Vm.16B
            arm64_jit_emit32(e, insn);
            return true;
        default:
            break;
    }
    switch (insn & 0xbf20fc00u) {
        case 0x0e003800u: // ZIP1
        case 0x0e007800u: // ZIP2
        case 0x0e001800u: // UZP1
        case 0x0e005800u: // UZP2
        case 0x0e002800u: // TRN1
        case 0x0e006800u: // TRN2
            arm64_jit_emit32(e, insn);
            return true;
        default:
            break;
    }
    if ((insn & 0x9f200400u) == 0x0e200400u) { // Advanced SIMD three-same
        uint32_t Q = (insn >> 30) & 1;
        uint32_t U = (insn >> 29) & 1;
        uint32_t size = (insn >> 22) & 0x3;
        uint32_t opcode = (insn >> 11) & 0x1f;
        bool valid = false;
        if (opcode == 0x03) {
            valid = true; // AND/BIC/ORR/ORN/EOR/BSL/BIT/BIF
        } else if ((U == 0 && opcode == 0x10) || (U == 1 && opcode == 0x10) ||
                (U == 1 && opcode == 0x06) || (U == 1 && opcode == 0x11) ||
                (U == 0 && opcode == 0x06)) {
            valid = !(size == 3 && Q == 0); // ADD/SUB/CMHI/CMEQ/CMGT
        } else if ((U == 1 && opcode == 0x15) || (U == 0 && opcode == 0x14)) {
            valid = !(size == 3 && Q == 0); // UMIN/SMAX
        }
        if (valid) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xbfe08400u) == 0x2e000000u) { // EXT Vd.8B/16B, Vn, Vm, #imm
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xff3f0c00u) == 0x4e280800u) { // AESE/AESD/AESMC/AESIMC
        uint32_t opcode = (insn >> 12) & 0xf;
        if (opcode >= 4 && opcode <= 7) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xbfbffc00u) == 0x0ea0f800u || // FABS Vd.2S/4S/2D, Vn
            (insn & 0xbfbffc00u) == 0x2ea0f800u) { // FNEG Vd.2S/4S/2D, Vn
        uint32_t size = (insn >> 22) & 0x3;
        uint32_t q = (insn >> 30) & 1;
        if (size == 2 || (size == 3 && q)) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xdfbffc00u) == 0x5e21d800u || // SCVTF/UCVTF SIMD scalar integer
            (insn & 0xdfbffc00u) == 0x5ea1b800u) { // FCVTZS/FCVTZU SIMD scalar integer
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffffcc00u) == 0x5e280800u) { // SHA1H/SHA1SU1/SHA256SU0
        uint32_t opcode = (insn >> 12) & 0x3;
        if (opcode <= 2) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xdf800400u) == 0x5f000400u) { // Scalar SHL/SSHR/USHR/SSRA/USRA by immediate
        uint32_t immh = (insn >> 19) & 0xf;
        uint32_t U = (insn >> 29) & 1;
        uint32_t opcode = (insn >> 11) & 0x1f;
        if (immh != 0 && ((U == 0 && (opcode == 0x0a || opcode == 0x00 || opcode == 0x02)) ||
                (U == 1 && (opcode == 0x00 || opcode == 0x02)))) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xffe04c00u) == 0x5e000000u) { // SHA1C/SHA1P/SHA1M/SHA1SU0
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffe04c00u) == 0x5e004000u) { // SHA256H/SHA256H2/SHA256SU1
        uint32_t opcode = (insn >> 12) & 0x3;
        if (opcode <= 2) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xbf20fc00u) == 0x0e20e000u) { // PMULL/PMULL2
        uint32_t size = (insn >> 22) & 0x3;
        if (size == 0 || size == 3) {
            arm64_jit_emit32(e, insn);
            return true;
        }
    }
    if ((insn & 0xfffffc00u) == 0x6e205800u) { // MVN/NOT Vd.16B, Vn.16B
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xfffffc00u) == 0x4e205800u) { // CNT Vd.16B, Vn.16B
        arm64_jit_emit32(e, insn);
        return true;
    }
    if (((insn & 0xbf3ffc00u) == 0x0e200800u && ((insn >> 22) & 0x3) < 3) || // REV64
            ((insn & 0xbf3ffc00u) == 0x2e200800u && ((insn >> 22) & 0x3) < 2)) { // REV32
        arm64_jit_emit32(e, insn);
        return true;
    }
    return false;
}

static bool arm64_jit_emit_logical_imm_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x1f800000u) != 0x12000000u)
        return false;

    uint32_t opc = (insn >> 29) & 0x3;
    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    int dst = (opc == 3) ? arm64_jit_guest_src_host_reg_or_zr(e->block, rd)
                         : arm64_jit_guest_src_host_reg(e->block, rd, true);
    int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    if (dst < 0 || src < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src << 5;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_adr_cached(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if (!((insn & 0x1f000000u) == 0x10000000u || (insn & 0x9f000000u) == 0x90000000u))
        return false;

    uint32_t rd = ARM64_RD(insn);
    int dst = arm64_jit_host_reg_for_guest(e->block, rd);
    if (dst < 0)
        return false;

    int64_t imm = arm64_adr_imm(insn);
    uint64_t base = guest_pc;
    if (insn & 0x80000000u) {
        base &= ~0xfffULL;
        imm <<= 12;
    }
    arm64_jit_emit_load_imm64(e, (unsigned) dst, base + imm);
    return true;
}

static bool arm64_jit_emit_bitfield_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    bool is_bitfield = (insn & 0x1f800000u) == 0x13000000u;
    bool is_extr = (insn & 0x7f800000u) == 0x13800000u;
    if (!is_bitfield && !is_extr)
        return false;

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = arm64_jit_guest_src_host_reg_or_zr(e->block, rd);
    int src = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    if (dst < 0 || src < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src << 5;
    if (is_extr) { // EXTR
        int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
        if (src2 < 0)
            return false;
        emitted &= ~((uint32_t) 0x1f << 16);
        emitted |= (uint32_t) src2 << 16;
    }
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_logical_shifted_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if (((insn >> 24) & 0x1f) != 0x0a)
        return false;

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = arm64_jit_guest_src_host_reg_or_zr(e->block, rd);
    int src1 = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
    if (dst < 0 || src1 < 0 || src2 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_addsub_shifted_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if (((insn >> 24) & 0x1f) != 0x0b)
        return false;
    if (((insn >> 22) & 0x3) == 3)
        return false;
    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = arm64_jit_guest_src_host_reg_or_zr(e->block, rd);
    int src1 = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
    if (dst < 0 || src1 < 0 || src2 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_dp_2src_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x5fe00000u) != 0x1ac00000u)
        return false;

    uint32_t opcode = (insn >> 10) & 0x3f;
    switch (opcode) {
        case 0x02: // UDIV
        case 0x03: // SDIV
        case 0x08: // LSLV
        case 0x09: // LSRV
        case 0x0a: // ASRV
        case 0x0b: // RORV
            break;
        default:
            return false;
    }

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = arm64_jit_guest_src_host_reg(e->block, rd, false);
    int src1 = arm64_jit_guest_src_host_reg(e->block, rn, false);
    int src2 = arm64_jit_guest_src_host_reg(e->block, rm, false);
    if (dst < 0 || src1 < 0 || src2 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_dp_1src_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if (((insn >> 30) & 1) != 1 || ((insn >> 28) & 1) != 1 || ((insn >> 21) & 0xf) != 0x6)
        return false;

    uint32_t S = (insn >> 29) & 1;
    uint32_t opcode2 = (insn >> 16) & 0x1f;
    uint32_t opcode = (insn >> 10) & 0x3f;
    if (S != 0 || opcode2 != 0)
        return false;

    switch (opcode) {
        case 0x00: // RBIT
        case 0x01: // REV16
        case 0x02: // REV / REV32
        case 0x03: // REV (64-bit only)
        case 0x04: // CLZ
        case 0x05: // CLS
            break;
        default:
            return false;
    }
    if (!ARM64_SF(insn) && opcode == 0x03)
        return false;

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    int dst = arm64_jit_guest_src_host_reg(e->block, rd, false);
    int src = arm64_jit_guest_src_host_reg(e->block, rn, false);
    if (dst < 0 || src < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src << 5;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_addsub_extended_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x1f200000u) != 0x0b200000u)
        return false;
    bool setflags = ((insn >> 29) & 1) != 0;
    uint32_t option = (insn >> 13) & 0x7;

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = setflags ? arm64_jit_guest_src_host_reg_or_zr(e->block, rd)
                       : ((rd == 31) ? ARM64_JIT_HOST_GUEST_SP : arm64_jit_host_reg_for_guest(e->block, rd));
    bool rn_is_sp = !setflags;
    if ((option & 0x3) == 3)
        rn_is_sp = true;
    int src1 = arm64_jit_guest_src_host_reg(e->block, rn, rn_is_sp);
    int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
    if (dst < 0 || src1 < 0 || src2 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_csel_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x1fe00000u) != 0x1a800000u)
        return false;
    if (((insn >> 29) & 1) != 0)
        return false;

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = arm64_jit_guest_src_host_reg_or_zr(e->block, rd);
    int src1 = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
    if (dst < 0 || src1 < 0 || src2 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_adc_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x1fe0fc00u) != 0x1a000000u)
        return false;

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    int dst = arm64_jit_guest_src_host_reg_or_zr(e->block, rd);
    int src1 = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
    if (dst < 0 || src1 < 0 || src2 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_ccmp_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x3fe00410u) != 0x3a400000u)
        return false;

    bool is_imm = ((insn >> 11) & 1) != 0;
    uint32_t rn = ARM64_RN(insn);
    int src1 = arm64_jit_guest_src_host_reg(e->block, rn, false);
    if (src1 < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted |= (uint32_t) src1 << 5;
    if (!is_imm) {
        uint32_t rm = (insn >> 16) & 0x1f;
        int src2 = arm64_jit_guest_src_host_reg(e->block, rm, false);
        if (src2 < 0)
            return false;
        emitted &= ~((uint32_t) 0x1f << 16);
        emitted |= (uint32_t) src2 << 16;
    }
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_dp_3src_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    if ((insn & 0x1f000000u) != 0x1b000000u)
        return false;

    uint32_t op54 = (insn >> 29) & 0x3;
    uint32_t op31 = (insn >> 21) & 0x7;
    uint32_t o0 = (insn >> 15) & 1;
    if (op54 != 0)
        return false;

    switch (op31) {
        case 0: // MADD/MSUB (32/64)
        case 1: // SMADDL/SMSUBL
        case 5: // UMADDL/UMSUBL
            break;
        case 2: // SMULH
        case 6: // UMULH
            if (o0 != 0)
                return false;
            break;
        default:
            return false;
    }

    uint32_t rd = ARM64_RD(insn);
    uint32_t rn = ARM64_RN(insn);
    uint32_t rm = ARM64_RM(insn);
    uint32_t ra = (insn >> 10) & 0x1f;
    int dst = arm64_jit_host_reg_for_guest(e->block, rd);
    int src1 = arm64_jit_guest_src_host_reg_or_zr(e->block, rn);
    int src2 = arm64_jit_guest_src_host_reg_or_zr(e->block, rm);
    int acc = arm64_jit_guest_src_host_reg_or_zr(e->block, ra);
    if (dst < 0 || src1 < 0 || src2 < 0 || acc < 0)
        return false;

    uint32_t emitted = insn;
    emitted &= ~((uint32_t) 0x1f);
    emitted &= ~((uint32_t) 0x1f << 5);
    emitted &= ~((uint32_t) 0x1f << 16);
    emitted &= ~((uint32_t) 0x1f << 10);
    emitted |= (uint32_t) dst;
    emitted |= (uint32_t) src1 << 5;
    emitted |= (uint32_t) src2 << 16;
    emitted |= (uint32_t) acc << 10;
    arm64_jit_emit32(e, emitted);
    return true;
}

static bool arm64_jit_emit_system_cached(struct arm64_jit_emitter *e, uint32_t insn) {
    switch (insn) {
        case 0xd503201fU: // NOP
        case 0xd503203fU: // YIELD
        case 0xd503205fU: // WFE
        case 0xd503207fU: // WFI
        case 0xd503209fU: // SEV
        case 0xd50320bfU: // SEVL
            // Treat architectural hints as guest-local no-ops for now.
            arm64_jit_emit32(e, 0xd503201fU);
            return true;
        default:
            break;
    }
    if ((insn & 0xfffff09fu) == 0xd503309fu || // DMB <option>
            (insn & 0xfffff09fu) == 0xd503309fu + 0x2000u || // DSB <option>
            insn == 0xd5033fdfu || // ISB
            (insn & 0xfffffc1fu) == 0xd503305fu) { // CLREX <imm>
        arm64_jit_emit32(e, insn);
        return true;
    }
    if ((insn & 0xffffffe0U) == 0xd53bd040U) { // mrs xt, tpidr_el0
        uint32_t rd = ARM64_RD(insn);
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        if (dst < 0)
            return false;
        arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) dst, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(tls_ptr) >> 3)));
        return true;
    }
    if ((insn & 0xffffffe0U) == 0xd51bd040U) { // msr tpidr_el0, xt
        uint32_t rt = ARM64_RT(insn);
        int src = arm64_jit_guest_src_host_reg(e->block, rt, false);
        if (src < 0)
            return false;
        arm64_jit_emit32(e, arm64_jit_enc_str64_uimm((unsigned) src, ARM64_JIT_HOST_CPU,
                (CPU_OFFSET(tls_ptr) >> 3)));
        return true;
    }
    if ((insn & 0xfffffff0U) == 0xd50340d0U || (insn & 0xfffffff0U) == 0xd50341d0U) {
        return true; // msr daifset/clr -> guest-local no-op
    }
    if ((insn & 0xfff00000U) == 0xd5300000U) { // generic MRS subset
        uint32_t op0 = (insn >> 19) & 0x3;
        uint32_t op1 = (insn >> 16) & 0x7;
        uint32_t crn = (insn >> 12) & 0xf;
        uint32_t crm = (insn >> 8) & 0xf;
        uint32_t op2 = (insn >> 5) & 0x7;
        uint32_t rd = ARM64_RD(insn);
        int dst = arm64_jit_host_reg_for_guest(e->block, rd);
        if (dst < 0)
            return false;

        if (op0 == 3 && op1 == 3 && crn == 4 && crm == 4 && op2 == 0) { // FPCR
            arm64_jit_emit32(e, arm64_jit_enc_ldr32_uimm((unsigned) dst, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(fpcr) >> 2)));
            return true;
        }
        if (op0 == 3 && op1 == 3 && crn == 4 && crm == 4 && op2 == 1) { // FPSR
            arm64_jit_emit32(e, arm64_jit_enc_ldr32_uimm((unsigned) dst, ARM64_JIT_HOST_CPU,
                    (CPU_OFFSET(fpsr) >> 2)));
            return true;
        }

        uint64_t value = 0;
        bool known = true;
        if (op0 == 3 && op1 == 3 && crn == 0 && crm == 0 && op2 == 1)
            value = 0x8444c004ULL; // CTR_EL0
        else if (op0 == 3 && op1 == 3 && crn == 0 && crm == 0 && op2 == 7)
            value = 0x14ULL; // DCZID_EL0
        else if (op0 == 3 && op1 == 3 && crn == 2 && crm == 4 && op2 == 0)
            value = 0ULL; // RNDR
        else if (op0 == 3 && op1 == 3 && crn == 2 && crm == 4 && op2 == 1)
            value = 0ULL; // RNDRRS
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 4 && op2 == 0)
            value = 0x1000220000000000ULL; // ID_AA64PFR0_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 4 && op2 == 1)
            value = 0ULL; // ID_AA64PFR1_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 6 && op2 == 0)
            value = 0x001011110121ULL; // ID_AA64ISAR0_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 6 && op2 == 1)
            value = 0x1100001110211111ULL; // ID_AA64ISAR1_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 4 && op2 == 4)
            value = 0ULL; // ID_AA64ZFR0_EL1
        else if (op0 == 3 && op1 == 3 && crn == 14 && crm == 0 && op2 == 2)
            value = 0ULL; // CNTVCT_EL0
        else if (op0 == 3 && op1 == 3 && crn == 14 && crm == 0 && op2 == 0)
            value = 24000000ULL; // CNTFRQ_EL0
        else
            known = false;

        if (!known)
            return false;
        arm64_jit_emit_load_imm64(e, (unsigned) dst, value);
        return true;
    }
    return false;
}

enum arm64_jit_emit_result arm64_jit_emit_dp_imm(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if (arm64_jit_emit_move_wide_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_adr_cached(e, insn, guest_pc))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_addsub_imm_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_logical_imm_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_bitfield_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    arm64_jit_emit_helper_continue_regarg(e, arm64_jit_helper_exec_dp_imm_jitabi, guest_pc, insn);
    return ARM64_JIT_EMIT_CONTINUE;
}

enum arm64_jit_emit_result arm64_jit_emit_dp_reg(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if (arm64_jit_emit_logical_shifted_cached(e, insn)) {
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if (arm64_jit_emit_addsub_extended_cached(e, insn)) {
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if (arm64_jit_emit_addsub_shifted_cached(e, insn)) {
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if (arm64_jit_emit_dp_3src_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_csel_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_adc_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_ccmp_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_dp_2src_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_emit_dp_1src_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    arm64_jit_emit_helper_continue_regarg(e, arm64_jit_helper_exec_dp_reg_jitabi, guest_pc, insn);
    return ARM64_JIT_EMIT_CONTINUE;
}

enum arm64_jit_emit_result arm64_jit_emit_branch(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    uint32_t op = (insn >> 26) & 0x3f;
    if (op == 0x05 || op == 0x25) {
        addr_t target = guest_pc + arm64_branch_imm26(insn);
        bool is_link = op == 0x25;
        if (!arm64_jit_local_fixup_disabled(e->block, guest_pc) &&
                !is_link && arm64_jit_local_branch_can_stay_in_fragment(e->block, guest_pc, target) &&
                arm64_jit_block_has_pc(e->block, target)) {
            if (arm64_jit_emit_local_fixup(e, guest_pc, target, ARM64_JIT_FIXUP_B)) {
                arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
                return ARM64_JIT_EMIT_TERMINATE;
            }
        }
        if (!arm64_jit_local_fixup_disabled(e->block, guest_pc) &&
                is_link && arm64_jit_block_has_pc(e->block, target)) {
            arm64_jit_emit_set_guest_lr(e, guest_pc + 4);
            if (arm64_jit_emit_local_fixup(e, guest_pc, target, ARM64_JIT_FIXUP_B)) {
                arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
                return ARM64_JIT_EMIT_TERMINATE;
            }
        }
        if (is_link) {
            arm64_jit_emit_set_guest_lr(e, guest_pc + 4);
            arm64_jit_emit_control_transfer_fast_return_imm_flags(e, guest_pc, target, 0, 1);
            return ARM64_JIT_EMIT_TERMINATE;
        }
        arm64_jit_emit_control_transfer_fast_return_imm(e, guest_pc, target, 0);
        return ARM64_JIT_EMIT_TERMINATE;
    }
    if ((insn & 0x7e000000u) == 0x34000000u) {
        if (!arm64_jit_local_fixup_disabled(e->block, guest_pc)) {
            addr_t target = guest_pc + arm64_branch_imm19(insn);
            uint32_t rt = ARM64_RT(insn);
            int host_rt = arm64_jit_guest_src_host_reg(e->block, rt, false);
            if (host_rt >= 0 && arm64_jit_local_branch_can_stay_in_fragment(e->block, guest_pc, target) &&
                    arm64_jit_block_has_pc(e->block, target)) {
                bool sf = ((insn >> 31) & 1) != 0;
                bool nonzero = ((insn >> 24) & 1) != 0;
                if (arm64_jit_emit_local_fixup(e, guest_pc, target, ARM64_JIT_FIXUP_CBZ)) {
                    arm64_jit_emit32(e, arm64_jit_enc_cbz_cbnz(sf, nonzero, (unsigned) host_rt, 0));
                    return ARM64_JIT_EMIT_CONTINUE;
                }
            }
        }
        uint32_t rt = ARM64_RT(insn);
        int host_rt = arm64_jit_guest_src_host_reg(e->block, rt, false);
        addr_t target = guest_pc + arm64_branch_imm19(insn);
        bool sf = ((insn >> 31) & 1) != 0;
        bool nonzero = ((insn >> 24) & 1) != 0;
        if (host_rt < 0) {
            host_rt = ARM64_JIT_HOST_TMP3;
            if (rt < 31)
                arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) host_rt, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rt]) >> 3)));
            else
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg((unsigned) host_rt, 31));
        }
        arm64_jit_emit_conditional_transfer_fast_return(e,
                arm64_jit_enc_cbz_cbnz(sf, nonzero, (unsigned) host_rt, 2),
                guest_pc, guest_pc + 4, target, 2);
        return ARM64_JIT_EMIT_TERMINATE;
    }
    if ((insn & 0xff000010u) == 0x54000000u) {
        if (!arm64_jit_local_fixup_disabled(e->block, guest_pc)) {
            addr_t target = guest_pc + arm64_branch_imm19(insn);
            if (arm64_jit_local_branch_can_stay_in_fragment(e->block, guest_pc, target) &&
                    arm64_jit_block_has_pc(e->block, target)) {
                if (arm64_jit_emit_local_fixup(e, guest_pc, target, ARM64_JIT_FIXUP_B_COND)) {
                    arm64_jit_emit32(e, insn);
                    return ARM64_JIT_EMIT_CONTINUE;
                }
            }
        }
        arm64_jit_emit_conditional_transfer_fast_return(e,
                arm64_jit_enc_b_cond((enum arm64_cond) (insn & 0xf), 2),
                guest_pc, guest_pc + 4, guest_pc + arm64_branch_imm19(insn), 1);
        return ARM64_JIT_EMIT_TERMINATE;
    }
    if ((insn & 0x7e000000u) == 0x36000000u) {
        if (!arm64_jit_local_fixup_disabled(e->block, guest_pc)) {
            addr_t target = guest_pc + arm64_branch_imm14(insn);
            uint32_t rt = ARM64_RT(insn);
            int host_rt = arm64_jit_guest_src_host_reg(e->block, rt, false);
            if (host_rt >= 0 && arm64_jit_local_branch_can_stay_in_fragment(e->block, guest_pc, target) &&
                    arm64_jit_block_has_pc(e->block, target)) {
                bool b5 = ((insn >> 31) & 1) != 0;
                bool nonzero = ((insn >> 24) & 1) != 0;
                unsigned bit40 = (insn >> 19) & 0x1f;
                if (arm64_jit_emit_local_fixup(e, guest_pc, target, ARM64_JIT_FIXUP_TBZ)) {
                    arm64_jit_emit32(e, arm64_jit_enc_tbz_tbnz(b5, nonzero, bit40,
                            (unsigned) host_rt, 0));
                    return ARM64_JIT_EMIT_CONTINUE;
                }
            }
        }
        uint32_t rt = ARM64_RT(insn);
        int host_rt = arm64_jit_guest_src_host_reg(e->block, rt, false);
        addr_t target = guest_pc + arm64_branch_imm14(insn);
        bool b5 = ((insn >> 31) & 1) != 0;
        bool nonzero = ((insn >> 24) & 1) != 0;
        unsigned bit40 = (insn >> 19) & 0x1f;
        if (host_rt < 0) {
            host_rt = ARM64_JIT_HOST_TMP3;
            if (rt < 31)
                arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) host_rt, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rt]) >> 3)));
            else
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg((unsigned) host_rt, 31));
        }
        arm64_jit_emit_conditional_transfer_fast_return(e,
                arm64_jit_enc_tbz_tbnz(b5, nonzero, bit40, (unsigned) host_rt, 2),
                guest_pc, guest_pc + 4, target, 3);
        return ARM64_JIT_EMIT_TERMINATE;
    }
    if ((insn & 0xfe000000u) == 0xd6000000u) {
        arm64_jit_emit_helper_return_branch_reg_fast(e, guest_pc, insn);
        return ARM64_JIT_EMIT_TERMINATE;
    }
    return ARM64_JIT_EMIT_UNSUPPORTED;
}

enum arm64_jit_emit_result arm64_jit_emit_exception(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if ((insn & 0xffe0001fu) == 0xd4000001u) { // svc #imm16
        arm64_jit_emit_helper_return(e, arm64_jit_helper_syscall_jitabi, guest_pc);
        return ARM64_JIT_EMIT_TERMINATE;
    }
    if ((insn & 0xffe0001fu) == 0xd4200000u) { // brk #imm16
        arm64_jit_emit_helper_return(e, arm64_jit_helper_verify_trap_jitabi, guest_pc);
        return ARM64_JIT_EMIT_TERMINATE;
    }

    arm64_jit_emit_helper_return(e, arm64_jit_helper_unsupported_jitabi, guest_pc);
    return ARM64_JIT_EMIT_TERMINATE;
}

enum arm64_jit_emit_result arm64_jit_emit_system(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if (arm64_jit_emit_system_cached(e, insn)) {
        return ARM64_JIT_EMIT_CONTINUE;
    }

    if ((insn & 0xffffffe0U) == 0xd53bd040U) { // mrs xt, tpidr_el0
        arm64_jit_emit_helper_continue_regarg(e, arm64_jit_helper_mrs_tpidr_jitabi, guest_pc, ARM64_RD(insn));
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if ((insn & 0xffffffe0U) == 0xd51bd040U) { // msr tpidr_el0, xt
        arm64_jit_emit_helper_continue_regarg(e, arm64_jit_helper_msr_tpidr_jitabi, guest_pc, ARM64_RT(insn));
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if ((insn & 0xfffffff0U) == 0xd50340d0U || (insn & 0xfffffff0U) == 0xd50341d0U) { // msr daifset/clr
        arm64_jit_emit_helper_continue_regarg(e, arm64_jit_helper_msr_daif_jitabi, guest_pc, 0);
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if ((insn & 0xfff00000U) == 0xd5300000U) { // generic MRS
        uint32_t op0 = (insn >> 19) & 0x3;
        uint32_t op1 = (insn >> 16) & 0x7;
        uint32_t crn = (insn >> 12) & 0xf;
        uint32_t crm = (insn >> 8) & 0xf;
        uint32_t op2 = (insn >> 5) & 0x7;
        int sysreg_id = -1;
        if (op0 == 3 && op1 == 3 && crn == 0 && crm == 0 && op2 == 1)
            sysreg_id = 1; // CTR_EL0
        else if (op0 == 3 && op1 == 3 && crn == 0 && crm == 0 && op2 == 7)
            sysreg_id = 2; // DCZID_EL0
        else if (op0 == 3 && op1 == 3 && crn == 4 && crm == 4 && op2 == 0)
            sysreg_id = 3; // FPCR
        else if (op0 == 3 && op1 == 3 && crn == 4 && crm == 4 && op2 == 1)
            sysreg_id = 4; // FPSR
        else if (op0 == 3 && op1 == 3 && crn == 2 && crm == 4 && op2 == 0)
            sysreg_id = 5; // RNDR
        else if (op0 == 3 && op1 == 3 && crn == 2 && crm == 4 && op2 == 1)
            sysreg_id = 6; // RNDRRS
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 4 && op2 == 0)
            sysreg_id = 7; // ID_AA64PFR0_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 4 && op2 == 1)
            sysreg_id = 8; // ID_AA64PFR1_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 6 && op2 == 0)
            sysreg_id = 9; // ID_AA64ISAR0_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 6 && op2 == 1)
            sysreg_id = 10; // ID_AA64ISAR1_EL1
        else if (op0 == 3 && op1 == 0 && crn == 0 && crm == 4 && op2 == 4)
            sysreg_id = 11; // ID_AA64ZFR0_EL1
        else if (op0 == 3 && op1 == 3 && crn == 14 && crm == 0 && op2 == 2)
            sysreg_id = 12; // CNTVCT_EL0
        else if (op0 == 3 && op1 == 3 && crn == 14 && crm == 0 && op2 == 0)
            sysreg_id = 13; // CNTFRQ_EL0

        if (sysreg_id >= 0) {
            uint64_t packed = (uint32_t) guest_pc |
                    ((uint64_t) ARM64_RD(insn) << 32) |
                    ((uint64_t) (unsigned) sysreg_id << 40);
            arm64_jit_emit_helper_continue_packed1(e, arm64_jit_helper_mrs_sysreg_jitabi, packed);
            return ARM64_JIT_EMIT_CONTINUE;
        }
    }

    arm64_jit_emit_helper_return(e, arm64_jit_helper_unsupported_jitabi, guest_pc);
    return ARM64_JIT_EMIT_TERMINATE;
}

enum arm64_jit_emit_result arm64_jit_emit_ld_st(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if ((insn & 0x3f000000u) == 0x08000000u) {
        uint32_t size = (insn >> 30) & 0x3;
        uint32_t o2 = (insn >> 23) & 1;
        uint32_t L = (insn >> 22) & 1;
        uint32_t o1 = (insn >> 21) & 1;
        uint32_t rs = (insn >> 16) & 0x1f;
        uint32_t rn = ARM64_RN(insn);
        uint32_t rt = ARM64_RT(insn);
        if (!o2 && !o1 && L && rs == 31) {
            int dst_host = arm64_jit_host_reg_for_guest(e->block, rt);
            if (arm64_jit_emit_guest_src_to_host_reg(e, rn, true, ARM64_JIT_HOST_TMP2)) {
                arm64_jit_emit_inline_ldxr_tlb(e, insn, guest_pc, ARM64_JIT_HOST_TMP2, dst_host);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        if (!o2 && !o1 && !L) {
            int value_host = arm64_jit_host_reg_for_guest(e->block, rt);
            int status_host = rs == 31 ? -1 : arm64_jit_host_reg_for_guest(e->block, rs);
            if (arm64_jit_emit_guest_src_to_host_reg(e, rn, true, ARM64_JIT_HOST_TMP2) &&
                    arm64_jit_emit_guest_src_to_host_reg(e, rt, false, ARM64_JIT_HOST_TMP3)) {
                if (value_host < 0)
                    value_host = ARM64_JIT_HOST_TMP3;
                arm64_jit_emit_inline_stxr_tlb(e, insn, guest_pc, ARM64_JIT_HOST_TMP2,
                        value_host, status_host);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        (void) size;
        arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_ldst_excl_success_jitabi, guest_pc, insn);
        return ARM64_JIT_EMIT_CONTINUE;
    }

    if ((insn & 0xbfbf0000u) == 0x0c000000u ||
            (insn & 0xbfa00000u) == 0x0c800000u) {
        uint32_t Lm = (insn >> 22) & 1;
        if (!Lm) {
            uint32_t rtm = ARM64_RT(insn);
            uint32_t opcode_m = (insn >> 12) & 0xf;
            int num_m = arm64_jit_simd_ldst_multi_num_regs_emit(opcode_m);
            for (int i = 0; i < num_m; i++)
                arm64_jit_emit_spill_cached_vreg(e, (rtm + (uint32_t) i) & 0x1f);
        }
        arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_simd_ldst_multi_success_jitabi, guest_pc, insn);
        return ARM64_JIT_EMIT_CONTINUE;
    }

    if ((insn & 0x3a000000u) == 0x28000000u) {
        uint32_t Vp = (insn >> 26) & 1;
        uint32_t opcp = (insn >> 30) & 0x3;
        uint32_t modep = (insn >> 23) & 0x7;
        uint32_t Lp = (insn >> 22) & 1;
        uint32_t rtp = ARM64_RT(insn);
        uint32_t rt2p = (insn >> 10) & 0x1f;
        uint32_t rnp = ARM64_RN(insn);
        if (Vp == 1 && modep == 2 && opcp <= 2) { // vector offset pair load/store
            int base_host = arm64_jit_guest_src_host_reg(e->block, rnp, true);
            if (base_host >= 0) {
                int32_t imm7 = (int32_t) ((insn >> 15) & 0x7f);
                if (imm7 & 0x40)
                    imm7 |= ~0x7f;
                int64_t offset = imm7 * ((int64_t) 4 << opcp);
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                if (offset != 0) {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (uint64_t) offset);
                    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                }
                if (!Lp) {
                    arm64_jit_emit_spill_cached_vreg(e, rtp);
                    arm64_jit_emit_spill_cached_vreg(e, rt2p);
                }
                arm64_jit_emit_helper_success_live_addronly(e, arm64_jit_helper_ldst_pair_vec_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn, ARM64_JIT_HOST_TMP2);
                if (Lp) {
                    arm64_jit_emit_load_cached_vreg(e, rtp);
                    arm64_jit_emit_load_cached_vreg(e, rt2p);
                }
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        if (Vp == 0 && Lp == 0 && (modep == 1 || modep == 2 || modep == 3) &&
                (opcp == 0 || opcp == 2)) { // scalar pair store
            int base_host = arm64_jit_guest_src_host_reg(e->block, rnp, true);
            int val0_host = arm64_jit_host_reg_for_guest(e->block, rtp);
            int val1_host = arm64_jit_host_reg_for_guest(e->block, rt2p);
            bool writeback = modep == 1 || modep == 3;
            bool overlap = writeback && rnp != 31 && (rnp == rtp || rnp == rt2p);
            if (!overlap && base_host >= 0) {
                int32_t imm7 = (int32_t) ((insn >> 15) & 0x7f);
                if (imm7 & 0x40)
                    imm7 |= ~0x7f;
                int64_t scale = (opcp == 2) ? 8 : 4;
                int64_t offset = imm7 * scale;
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                if ((modep == 2 || modep == 3) && offset != 0) {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (uint64_t) offset);
                    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                }
                arm64_jit_emit_inline_scalar_pair_tlb(e, insn, false,
                        ARM64_JIT_HOST_TMP2, val0_host, val1_host, rtp, rt2p,
                        writeback ? base_host : -1, writeback ? offset : 0,
                        modep == 1,
                        arm64_jit_helper_ldst_pair_store_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        if (Vp == 0 && Lp == 1 && (modep == 1 || modep == 2 || modep == 3) &&
                (opcp == 0 || opcp == 1 || opcp == 2)) { // scalar pair load
            int base_host = arm64_jit_guest_src_host_reg(e->block, rnp, true);
            int dst0_host = arm64_jit_host_reg_for_guest(e->block, rtp);
            int dst1_host = arm64_jit_host_reg_for_guest(e->block, rt2p);
            bool writeback = modep == 1 || modep == 3;
            bool overlap = writeback && rnp != 31 && (rnp == rtp || rnp == rt2p);
            if (!overlap && base_host >= 0 &&
                    (!writeback || ((rtp == 31 || dst0_host >= 0) && (rt2p == 31 || dst1_host >= 0)))) {
                int32_t imm7 = (int32_t) ((insn >> 15) & 0x7f);
                if (imm7 & 0x40)
                    imm7 |= ~0x7f;
                int64_t scale = (opcp == 2) ? 8 : 4;
                int64_t offset = imm7 * scale;
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                if ((modep == 2 || modep == 3) && offset != 0) {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (uint64_t) offset);
                    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                }
                arm64_jit_emit_inline_scalar_pair_tlb(e, insn, true,
                        ARM64_JIT_HOST_TMP2, dst0_host, dst1_host, rtp, rt2p,
                        writeback ? base_host : -1, writeback ? offset : 0,
                        modep == 1,
                        arm64_jit_helper_ldst_pair_load_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        if (Vp && !Lp) {
            arm64_jit_emit_spill_cached_vreg(e, rtp);
            arm64_jit_emit_spill_cached_vreg(e, rt2p);
        }
        arm64_jit_emit_helper_continue_regarg(e, arm64_jit_helper_ldst_pair_jitabi, guest_pc, insn);
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if (!((insn >> 26) & 1) && (insn & 0x3b200000u) == 0x38000000u) {
        uint32_t opc9 = (insn >> 22) & 0x3;
        uint32_t mode9 = (insn >> 10) & 0x3;
        uint32_t rn9 = ARM64_RN(insn);
        uint32_t rt9 = ARM64_RT(insn);
        if (opc9 == 1 && (mode9 == 0 || mode9 == 1 || mode9 == 3)) { // scalar load
            int base_host = arm64_jit_guest_src_host_reg(e->block, rn9, true);
            int dst_host = arm64_jit_host_reg_for_guest(e->block, rt9);
            bool writeback = mode9 == 1 || mode9 == 3;
            bool overlap = writeback && rn9 != 31 && rn9 == rt9;
            if (!overlap && base_host >= 0) {
                int32_t imm9 = (int32_t) ((insn >> 12) & 0x1ff);
                if (imm9 & 0x100)
                    imm9 |= ~0x1ff;
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                if (mode9 != 1 && imm9 != 0) {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (uint64_t) (int64_t) imm9);
                    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                }
                arm64_jit_emit_inline_scalar_regoff_tlb(e, insn, guest_pc, true,
                        ARM64_JIT_HOST_TMP2, dst_host,
                        writeback ? base_host : -1, writeback ? imm9 : 0, mode9 == 1,
                        rn9, true,
                        arm64_jit_helper_ldst_imm9_load_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        if (opc9 == 0 && (mode9 == 0 || mode9 == 1 || mode9 == 3)) { // scalar store
            int base_host = arm64_jit_guest_src_host_reg(e->block, rn9, true);
            int value_host = arm64_jit_guest_src_host_reg_or_zr(e->block, rt9);
            if (base_host >= 0 && value_host >= 0) {
                int32_t imm9 = (int32_t) ((insn >> 12) & 0x1ff);
                if (imm9 & 0x100)
                    imm9 |= ~0x1ff;
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                if (mode9 != 1 && imm9 != 0) {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (uint64_t) (int64_t) imm9);
                    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                }
                if (value_host != ARM64_JIT_HOST_TMP3)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP3, (unsigned) value_host));
                arm64_jit_emit_inline_scalar_regoff_tlb(e, insn, guest_pc, false,
                        ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP3,
                        (mode9 == 1 || mode9 == 3) ? base_host : -1,
                        (mode9 == 1 || mode9 == 3) ? imm9 : 0, mode9 == 1,
                        rn9, true,
                        arm64_jit_helper_ldst_imm9_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_ldst_imm9_success_jitabi, guest_pc, insn);
        if (mode9 == 1 || mode9 == 3)
            arm64_jit_emit_reload_cached_base(e, rn9, true);
        return ARM64_JIT_EMIT_CONTINUE;
    }
    if ((insn & 0x3b200c00u) == 0x38200800u) {
        uint32_t opc_ro = (insn >> 22) & 0x3;
        uint32_t V_ro = (insn >> 26) & 1;
        uint32_t rn_ro = ARM64_RN(insn);
        uint32_t rm_ro = ARM64_RM(insn);
        uint32_t rt_ro = ARM64_RT(insn);
        uint32_t option_ro = (insn >> 13) & 0x7;
        uint32_t S_ro = (insn >> 12) & 1;
        uint32_t size_ro = (insn >> 30) & 0x3;
        if (V_ro && (option_ro == 3 || option_ro == 2 || option_ro == 6 || option_ro == 7) && rm_ro != 31) {
            int base_host = arm64_jit_guest_src_host_reg(e->block, rn_ro, true);
            int off_host = arm64_jit_guest_src_host_reg(e->block, rm_ro, false);
            if (base_host >= 0 && off_host >= 0) {
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                if (off_host != ARM64_JIT_HOST_TMP1)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP1, (unsigned) off_host));
                if (option_ro == 2) {
                    arm64_jit_emit32(e, arm64_jit_enc_ubfx64(ARM64_JIT_HOST_TMP1, ARM64_JIT_HOST_TMP1, 0, 32));
                } else if (option_ro == 6) {
                    arm64_jit_emit32(e, 0x93407c21u); // sxtw x1, w1
                }
                if (S_ro) {
                    uint32_t size_ro = (insn >> 30) & 0x3;
                    uint32_t scale_ro = (size_ro == 0 && (opc_ro & 2)) ? 4 : size_ro;
                    if (scale_ro != 0) {
                        arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP3, scale_ro);
                        arm64_jit_emit32(e, 0x9ac32021u); // lslv x1, x1, x3
                    }
                }
                arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                if ((opc_ro & 1) == 0)
                    arm64_jit_emit_spill_cached_vreg(e, rt_ro);
                arm64_jit_emit_helper_success_live_addronly(e, arm64_jit_helper_simd_ldst_regoff_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn,
                        ARM64_JIT_HOST_TMP2);
                return ARM64_JIT_EMIT_CONTINUE;
            }
        }
        if (!V_ro && (opc_ro == 1 || opc_ro == 2 || opc_ro == 3) &&
                (option_ro == 2 || option_ro == 3 || option_ro == 6 || option_ro == 7) &&
                rm_ro != 31 &&
                !(opc_ro == 3 && size_ro == 2) &&
                !(opc_ro == 3 && size_ro == 3)) { // scalar load, no-writeback regoff
            int dst_host = arm64_jit_host_reg_for_guest(e->block, rt_ro);
            if (arm64_jit_emit_guest_src_to_host_reg(e, rn_ro, true, ARM64_JIT_HOST_TMP2) &&
                    arm64_jit_emit_guest_src_to_host_reg(e, rm_ro, false, ARM64_JIT_HOST_TMP1)) {
                if (arm64_jit_emit_regoff_addr(e, insn, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP1)) {
                    arm64_jit_emit_inline_scalar_regoff_tlb(e, insn, guest_pc, true,
                            ARM64_JIT_HOST_TMP2, dst_host,
                            -1, 0, false, 0, false,
                            arm64_jit_helper_ldst_regoff_load_live,
                            ((uint64_t) (uint32_t) guest_pc << 32) | insn);
                    return ARM64_JIT_EMIT_CONTINUE;
                }
            }
        }
        if (!V_ro && opc_ro == 0 &&
                (option_ro == 2 || option_ro == 3 || option_ro == 6 || option_ro == 7) &&
                rm_ro != 31) { // scalar store, no-writeback regoff
            if (arm64_jit_emit_guest_src_to_host_reg(e, rn_ro, true, ARM64_JIT_HOST_TMP2) &&
                    arm64_jit_emit_guest_src_to_host_reg(e, rm_ro, false, ARM64_JIT_HOST_TMP1)) {
                if (arm64_jit_emit_regoff_addr(e, insn, ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP1)) {
                    if (arm64_jit_emit_guest_src_to_host_reg(e, rt_ro, false, ARM64_JIT_HOST_TMP3)) {
                        arm64_jit_emit_inline_scalar_regoff_tlb(e, insn, guest_pc, false,
                                ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP3,
                                -1, 0, false, 0, false,
                                arm64_jit_helper_ldst_regoff_live,
                                ((uint64_t) (uint32_t) guest_pc << 32) | insn);
                        return ARM64_JIT_EMIT_CONTINUE;
                    }
                }
            }
        }
        arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_ldst_regoff_success_jitabi, guest_pc, insn);
        return ARM64_JIT_EMIT_CONTINUE;
    }

    if (((insn >> 26) & 1) == 1 && (insn & 0x3b200000u) == 0x38000000u) {
        uint32_t opc_v9 = (insn >> 22) & 0x3;
        uint32_t mode_v9 = (insn >> 10) & 0x3;
        uint32_t rn_v9 = ARM64_RN(insn);
        uint32_t rt_v9 = ARM64_RT(insn);
        int base_host = arm64_jit_guest_src_host_reg(e->block, rn_v9, true);
        if (base_host >= 0 && mode_v9 != 2) {
            int32_t imm9 = (int32_t) ((insn >> 12) & 0x1ff);
            if (imm9 & 0x100)
                imm9 |= ~0x1ff;
            if (base_host != ARM64_JIT_HOST_TMP2)
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
            if (mode_v9 != 1 && imm9 != 0) {
                arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, (uint64_t) (int64_t) imm9);
                arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
            }
            if ((opc_v9 & 1) == 0)
                arm64_jit_emit_spill_cached_vreg(e, rt_v9);
            arm64_jit_emit_helper_success_live_addronly(e, arm64_jit_helper_simd_ldst_imm_unsigned_live,
                    ((uint64_t) (uint32_t) guest_pc << 32) | insn,
                    ARM64_JIT_HOST_TMP2);
            if (mode_v9 != 0 && base_host >= 0) {
                arm64_jit_emit32(e, arm64_jit_enc_ldr64_uimm((unsigned) base_host, ARM64_JIT_HOST_CPU,
                        (CPU_OFFSET(regs[rn_v9]) >> 3)));
            }
            if ((opc_v9 & 1) != 0)
                arm64_jit_emit_load_cached_vreg(e, rt_v9);
            return ARM64_JIT_EMIT_CONTINUE;
        }
        uint32_t fallback_opc_v9 = (insn >> 22) & 0x3;
        if ((fallback_opc_v9 & 1) == 0)
            arm64_jit_emit_spill_cached_vreg(e, ARM64_RT(insn));
        arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_ldst_imm9_success_jitabi, guest_pc, insn);
        if (((insn >> 10) & 0x3) == 1 || ((insn >> 10) & 0x3) == 3)
            arm64_jit_emit_reload_cached_base(e, ARM64_RN(insn), true);
        return ARM64_JIT_EMIT_CONTINUE;
    }

    uint32_t size = (insn >> 30) & 0x3;
    uint32_t V = (insn >> 26) & 1;
    uint32_t opc = (insn >> 22) & 0x3;
    uint32_t rn = ARM64_RN(insn);
    uint32_t rt = ARM64_RT(insn);
    uint32_t imm12 = (insn >> 10) & 0xfff;

    if (V && (insn & 0x3b000000u) == 0x39000000u) {
        int base_host = arm64_jit_guest_src_host_reg(e->block, rn, true);
        if (base_host >= 0) {
            if (base_host != ARM64_JIT_HOST_TMP2)
                arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
            uint32_t scale = (size == 0 && (opc & 2)) ? 4 : size;
            uint64_t offset = (uint64_t) imm12 << scale;
            if (offset != 0) {
                if (offset <= 4095) {
                    arm64_jit_emit32(e, 0x91000000u |
                            (((uint32_t) offset & 0xfff) << 10) |
                            ((ARM64_JIT_HOST_TMP2 & 0x1f) << 5) |
                            (ARM64_JIT_HOST_TMP2 & 0x1f));
                } else {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP1, offset);
                    arm64_jit_emit32(e, 0x8b010042u); // add x2, x2, x1
                }
            }
            bool is_load = (opc & 1) != 0;
            if (!arm64_jit_emit_inline_simd_uimm_tlb(e, insn, is_load,
                        ARM64_JIT_HOST_TMP2, arm64_jit_helper_simd_ldst_imm_unsigned_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn)) {
                if (!is_load)
                    arm64_jit_emit_spill_cached_vreg(e, rt);
                arm64_jit_emit_helper_success_live_addronly(e, arm64_jit_helper_simd_ldst_imm_unsigned_live,
                        ((uint64_t) (uint32_t) guest_pc << 32) | insn, ARM64_JIT_HOST_TMP2);
            }
            return ARM64_JIT_EMIT_CONTINUE;
        }
        if ((opc & 1) == 0)
            arm64_jit_emit_spill_cached_vreg(e, rt);
        arm64_jit_emit_helper_success_regarg(e, arm64_jit_helper_simd_ldst_imm_unsigned_success_jitabi, guest_pc, insn);
        return ARM64_JIT_EMIT_CONTINUE;
    }

    // Unsigned-immediate scalar load/store examples for stage 1.
    if ((insn & 0x3b000000u) == 0x39000000u) {
        bool is_load = opc != 0;
        uint32_t load_mode = opc;
        if (is_load) {
            uint64_t packed1 = (rt & 0x1f) |
                    ((uint64_t) (rn & 0x1f) << 5) |
                    ((uint64_t) (size & 0x3) << 10) |
                    ((uint64_t) (imm12 & 0xfff) << 12) |
                    ((uint64_t) (load_mode & 0x3) << 24);
            uint64_t packed1_live = ((uint64_t) (uint32_t) guest_pc << 32) | packed1;
            int base_host = arm64_jit_guest_src_host_reg(e->block, rn, true);
            int dst_host = arm64_jit_host_reg_for_guest(e->block, rt);
            if (base_host >= 0) {
                if (base_host != ARM64_JIT_HOST_TMP3)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP3, (unsigned) base_host));
                uint64_t offset = (uint64_t) imm12 << size;
                if (offset != 0) {
                    if (offset <= 4095) {
                        arm64_jit_emit32(e, 0x91000000u |
                                (((uint32_t) offset & 0xfff) << 10) |
                                ((ARM64_JIT_HOST_TMP3 & 0x1f) << 5) |
                                (ARM64_JIT_HOST_TMP3 & 0x1f));
                } else {
                    arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP2, offset);
                    arm64_jit_emit32(e, 0x8b020063u); // add x3, x3, x2
                }
            }
                if (opc == 1) {
                    arm64_jit_emit_inline_scalar_regoff_tlb(e, insn, guest_pc, true,
                            ARM64_JIT_HOST_TMP3, dst_host,
                            -1, 0, false, 0, false,
                            arm64_jit_helper_ldr_imm_unsigned_live, packed1_live);
                } else {
                    arm64_jit_emit_helper_success_live_load(e, arm64_jit_helper_ldr_imm_unsigned_live,
                            packed1_live, ARM64_JIT_HOST_TMP3, dst_host);
                }
                return ARM64_JIT_EMIT_CONTINUE;
            }
            arm64_jit_emit_helper_success_packed2(e, arm64_jit_helper_ldr_imm_unsigned_success_jitabi,
                    guest_pc, packed1);
            return ARM64_JIT_EMIT_CONTINUE;
        }
        if (opc == 0) {
            uint64_t packed = (uint32_t) guest_pc |
                    ((uint64_t) (rt & 0x1f) << 32) |
                    ((uint64_t) (rn & 0x1f) << 37) |
                    ((uint64_t) (size & 0x3) << 42) |
                    ((uint64_t) (imm12 & 0xfff) << 44);
            int base_host = arm64_jit_guest_src_host_reg(e->block, rn, true);
            int value_host = arm64_jit_guest_src_host_reg_or_zr(e->block, rt);
            if (base_host >= 0 && value_host >= 0) {
                // guest_addr = base + (imm12 << size)
                if (base_host != ARM64_JIT_HOST_TMP2)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP2, (unsigned) base_host));
                uint64_t offset = (uint64_t) imm12 << size;
                if (offset != 0) {
                    if (offset <= 4095) {
                        arm64_jit_emit32(e, 0x91000000u |
                                (((uint32_t) offset & 0xfff) << 10) |
                                ((ARM64_JIT_HOST_TMP2 & 0x1f) << 5) |
                                (ARM64_JIT_HOST_TMP2 & 0x1f));
                    } else {
                        arm64_jit_emit_load_imm64(e, ARM64_JIT_HOST_TMP3, offset);
                        arm64_jit_emit32(e, 0x8b030042u); // add x2, x2, x3
                    }
                }
                if (value_host != ARM64_JIT_HOST_TMP3)
                    arm64_jit_emit32(e, arm64_jit_enc_mov_reg(ARM64_JIT_HOST_TMP3, (unsigned) value_host));
                arm64_jit_emit_inline_scalar_regoff_tlb(e, insn, guest_pc, false,
                        ARM64_JIT_HOST_TMP2, ARM64_JIT_HOST_TMP3,
                        -1, 0, false, 0, false,
                        arm64_jit_helper_str_imm_unsigned_live, packed);
                return ARM64_JIT_EMIT_CONTINUE;
            }
            arm64_jit_emit_helper_success_packed1(e, arm64_jit_helper_str_imm_unsigned_success_jitabi, packed);
            return ARM64_JIT_EMIT_CONTINUE;
        }
    }

    arm64_jit_emit_helper_return(e, arm64_jit_helper_unsupported_jitabi, guest_pc);
    return ARM64_JIT_EMIT_TERMINATE;
}

enum arm64_jit_emit_result arm64_jit_emit_simd_fp(struct arm64_jit_emitter *e, uint32_t insn, addr_t guest_pc) {
    if (arm64_jit_emit_simd_fp_cached(e, insn))
        return ARM64_JIT_EMIT_CONTINUE;
    if (arm64_jit_trace_mode()) {
        fprintf(stderr, "[arm64-jit] unsupported simd_fp pc=0x%llx insn=0x%08x\n",
                (unsigned long long) guest_pc, insn);
    }
    arm64_jit_emit_helper_return(e, arm64_jit_helper_unsupported_jitabi, guest_pc);
    return ARM64_JIT_EMIT_TERMINATE;
}

static enum arm64_jit_emit_result arm64_jit_emit_one(struct arm64_jit_emitter *e,
        const struct arm64_jit_insn_info *info, uint32_t insn, addr_t guest_pc) {
    switch (info->type) {
        case INSN_DP_IMM:
            return arm64_jit_emit_dp_imm(e, insn, guest_pc);
        case INSN_DP_REG:
            return arm64_jit_emit_dp_reg(e, insn, guest_pc);
        case INSN_BRANCH:
            return arm64_jit_emit_branch(e, insn, guest_pc);
        case INSN_EXCEPTION:
            return arm64_jit_emit_exception(e, insn, guest_pc);
        case INSN_SYSTEM:
            return arm64_jit_emit_system(e, insn, guest_pc);
        case INSN_LD_ST:
            return arm64_jit_emit_ld_st(e, insn, guest_pc);
        case INSN_SIMD_FP:
            return arm64_jit_emit_simd_fp(e, insn, guest_pc);
        default:
            return ARM64_JIT_EMIT_UNSUPPORTED;
    }
}

static bool arm64_jit_branch_has_fallthrough(uint32_t insn) {
    if ((insn & 0x7e000000u) == 0x34000000u)
        return true;
    if ((insn & 0xff000010u) == 0x54000000u)
        return true;
    if ((insn & 0x7e000000u) == 0x36000000u)
        return true;
    return false;
}

static void arm64_jit_emit_internal_fallthrough(struct arm64_jit_emitter *e,
        addr_t branch_pc, addr_t target_pc) {
    if (arm64_jit_block_has_pc(e->block, target_pc)) {
        if (arm64_jit_emit_local_fixup(e, branch_pc, target_pc, ARM64_JIT_FIXUP_B)) {
            arm64_jit_emit32(e, arm64_jit_enc_b_imm(0));
            return;
        }
    }
    arm64_jit_emit_control_transfer_fast_return_imm(e, branch_pc, target_pc, 0);
}

static void arm64_jit_reset_emit_metadata(struct arm64_jit_block *block) {
    block->spill_state_fn = NULL;
    block->reload_state_fn = NULL;
    block->light_spill_state_fn = NULL;
    block->c_entry_fn = NULL;
    block->jit_entry_fn = NULL;
    block->code_size = 0;
    block->pc_map_count = 0;
    block->verify_site_count = 0;
    block->fixup_count = 0;
    block->exit_epilogue_branch_count = 0;
    block->body_code_size = 0;
    block->spill_code_offset = UINT32_MAX;
    block->reload_code_offset = UINT32_MAX;
    block->light_spill_code_offset = UINT32_MAX;
    block->entry_thunks_offset = UINT32_MAX;
    for (uint32_t i = 0; i < block->insn_count; i++) {
        block->insn_host_offsets[i] = UINT32_MAX;
        block->entry_code[i] = NULL;
    }
}

static bool arm64_jit_emit_block_contents(struct arm64_jit_emitter *e) {
    struct arm64_jit_block *block = e->block;
    arm64_jit_emit_prologue(e);
    arm64_jit_emit_load_cached_state(e);
    bool island_open = true;
    for (uint32_t i = 0; i < block->insn_count; i++) {
        addr_t guest_pc = block->insn_pcs[i];
        uint32_t insn = block->insns[i];
        block->insn_host_offsets[i] = (uint32_t) e->size;
        arm64_jit_record_pc_map(e, guest_pc);
        arm64_jit_emit_verify_entry_brk(e, guest_pc, insn);
        const struct arm64_jit_insn_info *info = &block->infos[i];
        enum arm64_jit_emit_result res = arm64_jit_emit_one(e, info, insn, guest_pc);
        if (res == ARM64_JIT_EMIT_UNSUPPORTED) {
            arm64_jit_emit_helper_return(e, arm64_jit_helper_unsupported_jitabi, guest_pc);
            island_open = false;
            continue;
        }
        if (res == ARM64_JIT_EMIT_TERMINATE) {
            island_open = false;
            continue;
        }
        island_open = true;
        if (i + 1 < block->insn_count &&
                (info->type != INSN_BRANCH || arm64_jit_branch_has_fallthrough(insn))) {
            addr_t fallthrough_pc = guest_pc + 4;
            addr_t layout_next_pc = block->insn_pcs[i + 1];
            if (layout_next_pc != fallthrough_pc) {
                arm64_jit_emit_internal_fallthrough(e, guest_pc, fallthrough_pc);
            }
        }
    }
    if (island_open) {
        addr_t source_pc = block->insn_count != 0 ?
                block->insn_pcs[block->insn_count - 1] : block->start_pc;
        arm64_jit_emit_control_transfer_fast_return_imm(e, source_pc, block->end_pc, 0);
    }

    uint32_t exit_epilogue_off = (uint32_t) e->size;
    arm64_jit_emit_epilogue(e);
    arm64_jit_patch_exit_epilogue_branches(e, exit_epilogue_off);

    block->body_code_size = (uint32_t) e->size;

    block->spill_code_offset = (uint32_t) e->size;
    block->spill_state_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_spill_cached_state(e);
    arm64_jit_emit_state_snippet_ret(e);

    block->light_spill_code_offset = (uint32_t) e->size;
    block->light_spill_state_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_light_spill_cached_state(e);
    arm64_jit_emit_state_snippet_ret(e);

    block->reload_code_offset = (uint32_t) e->size;
    block->reload_state_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_load_cached_state(e);
    arm64_jit_emit_state_snippet_ret(e);

    if (!e->dry_run && !arm64_jit_patch_local_fixups(block, e->buf))
        return false;

    block->entry_thunks_offset = (uint32_t) e->size;
    arm64_jit_emit_entry_dispatch_table(e);

    uint32_t c_entry_offset = (uint32_t) e->size;
    block->c_entry_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_c_entry_snippet(e);

    uint32_t jit_entry_offset = (uint32_t) e->size;
    block->jit_entry_fn = e->dry_run ? NULL : e->buf + e->size;
    arm64_jit_emit_jit_entry_snippet(e);

    for (uint32_t i = 0; i < block->insn_count; i++) {
        uint32_t off = block->insn_host_offsets[i];
        if (off == UINT32_MAX)
            continue;
        block->entry_code[i] = e->dry_run ? NULL : e->buf + c_entry_offset;
    }
    (void) jit_entry_offset;
    return true;
}

static size_t arm64_jit_code_cap_for_estimate(size_t estimate) {
    const size_t slack = 1024;
    if (estimate > SIZE_MAX - slack)
        return 0;
    return estimate + slack;
}

size_t arm64_jit_estimate_block_code_size(struct arm64_jit_state *state,
        struct arm64_jit_block *block, struct tlb *tlb) {
    arm64_jit_reset_emit_metadata(block);
    struct arm64_jit_emitter dry = {
        .state = state,
        .block = block,
        .tlb = tlb,
        .buf = NULL,
        .cap = SIZE_MAX,
        .size = 0,
        .overflowed = false,
        .dry_run = true,
    };
    if (!arm64_jit_emit_block_contents(&dry) || dry.overflowed ||
            dry.size > UINT32_MAX) {
        arm64_jit_reset_emit_metadata(block);
        return 0;
    }
    arm64_jit_reset_emit_metadata(block);
    return arm64_jit_code_cap_for_estimate(dry.size);
}

void arm64_jit_emit_block(struct arm64_jit_state *state, struct arm64_jit_block *block,
        struct tlb *tlb) {
    size_t min_cap = 0;
    size_t cap = 0;
    arm64_jit_free_code(block);

retry_without_local_fixups:
    cap = arm64_jit_estimate_block_code_size(state, block, tlb);
    if (cap == 0 || cap > UINT32_MAX) {
        arm64_jit_reset_emit_metadata(block);
        return;
    }
    if (cap < min_cap)
        cap = min_cap;

retry_with_current_cap:
    arm64_jit_reset_emit_metadata(block);
    uint8_t *buf = NULL;
    if (!arm64_jit_alloc_code(state, block, cap, &buf))
        return;

    struct arm64_jit_emitter e = {
        .state = state,
        .block = block,
        .tlb = tlb,
        .buf = buf,
        .cap = cap,
        .size = 0,
        .overflowed = false,
        .dry_run = false,
    };

    if (!arm64_jit_emit_block_contents(&e)) {
        arm64_jit_free_code(block);
        goto retry_without_local_fixups;
    }

    if (e.overflowed) {
        if (arm64_jit_trace_mode()) {
            fprintf(stderr, "[arm64-jit] emit retry: buffer overflow start=0x%llx cap=%zu size=%zu\n",
                    (unsigned long long) block->start_pc, cap, e.size);
        }
        arm64_jit_free_code(block);
        if (cap > SIZE_MAX / 2 || cap > UINT32_MAX / 2) {
            arm64_jit_reset_emit_metadata(block);
            return;
        }
        cap *= 2;
        min_cap = cap;
        goto retry_with_current_cap;
    }

    block->code_size = (uint32_t) e.size;
    if (!arm64_jit_protect_code(block)) {
        if (arm64_jit_trace_mode()) {
            fprintf(stderr, "[arm64-jit] emit abort: protect failed start=0x%llx size=%zu\n",
                    (unsigned long long) block->start_pc, e.size);
        }
        arm64_jit_free_code(block);
        return;
    }

    if (arm64_jit_trace_mode()) {
        fprintf(stderr, "[arm64-jit] emitted start=0x%llx size=%zu\n",
                (unsigned long long) block->start_pc, e.size);
    }
}

#endif
