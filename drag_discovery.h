// drag_discovery.h — UIAnimationDragCoefficient global discovery.
//
// Locates the UIKitCore global behind _SetUIAnimationDragCoefficient by
// disassembling the setter and finding the STR that stores the value:
//   iOS 17      — plain 32-bit float (STR St), ungated.
//   iOS 18+     — double (STR Dt) behind a revision gate (two LDRs + a
//                 STR Wt sentinel that marks the revision offset).
//
// The scan core (animspeed_scan_drag) is pure C with no UIKit dependency,
// so it is unit-testable on the host — see tests/test_discovery.c.
// Discovery code ported from SBTweaker by kolbicz (MIT); see NOTICE in Tweak.m.

#ifndef ANIMSPEED_DRAG_DISCOVERY_H
#define ANIMSPEED_DRAG_DISCOVERY_H

#include <stdint.h>
#include <stdbool.h>
#include <dlfcn.h>

typedef struct {
    uint64_t g, revVar, revOnce;
    uint32_t valOff, revOff;
    bool gated, isFloat;
} animspeed_drag_t;

static uint64_t animspeed_strip_fp(void *p) {
    uint64_t v = (uint64_t)p;
#if defined(__arm64e__)
    // Function pointers on arm64e carry a PAC signature; strip it first.
    if (v >> 47) {
#if defined(__has_builtin) && __has_builtin(__builtin_ptrauth_strip)
        v = (uint64_t)__builtin_ptrauth_strip((void *)v, 0);
#else
        __asm__ volatile("xpaci %0" : "+r"(v));
#endif
    }
#endif
    return v;
}

// Scan one _SetUIAnimationDragCoefficient body.
// code: instruction words; pc_base: runtime address of code[0].
static bool animspeed_scan_drag(const uint32_t *code, uint64_t pc_base,
                               animspeed_drag_t *o) {
    const uint32_t *c = code;
    uint64_t pc = pc_base;
    uint64_t pg[32] = {0}, pv[32] = {0}, g = 0, rV = 0, rO = 0;
    uint32_t vOff = 0, rOff = 0;
    bool isFloat = false;

    for (int i = 0; i < 80; i++) {
        uint32_t in = c[i];
        int rd = in & 31, rn = (in >> 5) & 31;
        uint64_t ipc = pc + (uint64_t)i * 4;
        if (in == 0xd65f03c0 || in == 0xd65f0bff || in == 0xd65f0fff) break; // RET
        if ((in & 0x9f000000) == 0x90000000) {                              // ADRP
            int64_t lo = (in >> 29) & 3, hi = (in >> 5) & 0x7ffff;
            int64_t off = ((hi << 2) | lo) << 12;
            off = (off << 31) >> 31;
            pg[rd] = (ipc & ~0xfffULL) + off;
            pv[rd] = 0;
        } else if ((in & 0xff800000) == 0x91000000 && pg[rn]) {              // ADD imm
            // ADD (immediate) has a 1-bit shift field at bit 22: 0 = LSL #0,
            // 1 = LSL #12. Ignoring it silently mis-computed the base whenever
            // the setter reached a global more than 4KB from the ADRP page
            // (e.g. ADD X8, X8, #1, LSL #12 -> page + 0x1000, not page + 1),
            // pointing the writer at the wrong address.
            uint32_t imm = (in >> 10) & 0xfff;
            pv[rd] = pg[rn] + ((in & 0x00400000) ? (imm << 12) : imm);
        } else if ((in & 0xffc00000) == 0xf9400000 && pg[rn] && !rO) {       // LDR Xt
            rO = pg[rn] + (((in >> 10) & 0xfff) << 3);
        } else if ((in & 0xffc00000) == 0xb9400000 && pg[rn] && !rV) {       // LDR Wt
            rV = pg[rn] + (((in >> 10) & 0xfff) << 2);
        } else if ((in & 0xff800000) == 0xfd000000 && !g) {                 // STR Dt (double)
            uint64_t base = pv[rn] ? pv[rn] : pg[rn];
            if (base) { g = base; vOff = ((in >> 10) & 0xfff) << 3; isFloat = false; }
        } else if ((in & 0xffc00000) == 0xbd000000 && !g) {                 // STR St (float)
            uint64_t base = pv[rn] ? pv[rn] : pg[rn];
            if (base) { g = base; vOff = ((in >> 10) & 0xfff) << 2; isFloat = true; }
        } else if ((in & 0xff800000) == 0xb9000000 && g) {                 // STR Wt sentinel
            // Resolve the base exactly like the STR branches above (ADD value
            // if present, else the ADRP page): requiring pv[rn] == g missed
            // the sentinel whenever the setter used ADRP alone, leaving
            // revOff = 0 and making the writer stamp the revision value
            // onto the coefficient base itself.
            uint64_t base = pv[rn] ? pv[rn] : pg[rn];
            if (base == g) {
                rOff = ((in >> 10) & 0xfff) << 2;
                break;
            }
        }
    }

    if (!g) return false;

    bool gated = (rV && rO && (rO == rV + 8 || rV == rO + 8));
    o->g = g; o->revVar = rV; o->revOnce = rO;
    o->valOff = (gated && !vOff) ? 8 : vOff;
    o->revOff = rOff; o->gated = gated; o->isFloat = isFloat;
    return true;
}

// Resolve _SetUIAnimationDragCoefficient in this process and scan it.
static bool animspeed_find_drag(animspeed_drag_t *o) {
    void *fp = dlsym(RTLD_DEFAULT, "_SetUIAnimationDragCoefficient");
    if (!fp) {
        void *h = dlopen("/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore", RTLD_LAZY);
        if (h) fp = dlsym(h, "_SetUIAnimationDragCoefficient");
        if (!fp) return false;
    }

    uint64_t pc = animspeed_strip_fp(fp);
    const uint32_t *c = (const uint32_t *)pc;

    // Follow a leading B (branch stub) if present.
    for (int i = 0; i < 4; i++) {
        if ((c[i] & 0xfc000000) == 0x14000000) {
            pc += (uint64_t)i * 4 + (int64_t)((int32_t)(c[i] << 6) >> 4);
            c = (const uint32_t *)pc;
            break;
        }
    }

    return animspeed_scan_drag(c, pc, o);
}

#endif // ANIMSPEED_DRAG_DISCOVERY_H
