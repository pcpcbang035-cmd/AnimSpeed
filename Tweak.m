//
//  AnimSpeed — system-wide iOS animation speedup (SpringBoard tweak)
//  Copyright (c) 2026 Ho. Released under the MIT License (see LICENSE).
//
//  How it works:
//  iOS scales every UIKit animation duration by UIAnimationDragCoefficient,
//  a global inside UIKitCore (1.0 = stock). This tweak locates that global by
//  disassembling _SetUIAnimationDragCoefficient and writes 1/N into it directly,
//  where N is the desired speed multiplier.
//
//  The global-discovery code (find_drag / write_drag_coefficient) is ported from
//  SBTweaker by kolbicz, also MIT licensed:
//      https://github.com/kolbicz/sbtweaker
//  Copyright (c) kolbicz — see NOTICE below.
//
//  ---------------------------------------------------------------------------
//  NOTICE (required by the MIT license of the ported code):
//
//  Portions of this file are derived from SBTweaker:
//
//      MIT License
//      Copyright (c) kolbicz
//
//      Permission is hereby granted, free of charge, to any person obtaining a
//      copy of this software and associated documentation files (the
//      "Software"), to deal in the Software without restriction, including
//      without limitation the rights to use, copy, modify, merge, publish,
//      distribute, sublicense, and/or sell copies of the Software, and to
//      permit persons to whom the Software is furnished to do so, subject to
//      the following conditions:
//
//      The above copyright notice and this permission notice shall be included
//      in all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//      EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//      IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//      CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//      TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//      SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//  ---------------------------------------------------------------------------
//
//  Configuration:
//  /var/mobile/Library/Preferences/com.ho.animspeed.plist -> Speed (double).
//  If the file or key is missing, the default multiplier is used.
//

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdint.h>
#import <stdbool.h>
#import <math.h>

#define PREFS_PATH "/var/mobile/Library/Preferences/com.ho.animspeed.plist"

// ---------------------------------------------------------------------------
// UIAnimationDragCoefficient global discovery (ported from SBTweaker, MIT)
// ---------------------------------------------------------------------------

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

// Disassemble _SetUIAnimationDragCoefficient to find the global it writes to.
// iOS 17: 32-bit float, ungated. iOS 18+: double behind a revision gate.
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
            pv[rd] = pg[rn] + ((in >> 10) & 0xfff);
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
        } else if ((in & 0xff800000) == 0xb9000000 && g && pv[rn] == g) {   // STR Wt sentinel
            rOff = ((in >> 10) & 0xfff) << 2;
            break;
        }
    }

    if (!g) return false;

    bool gated = (rV && rO && (rO == rV + 8 || rV == rO + 8));
    o->g = g; o->revVar = rV; o->revOnce = rO;
    o->valOff = (gated && !vOff) ? 8 : vOff;
    o->revOff = rOff; o->gated = gated; o->isFloat = isFloat;
    return true;
}

// Write the drag coefficient into the UIKitCore global. Returns success.
static bool animspeed_write_drag_coefficient(double v) {
    animspeed_drag_t d;
    if (!animspeed_find_drag(&d)) return false;
    @try {
        if (d.gated) { // iOS 18+: satisfy the revision gate, then write the double
            uint32_t *revVar = (uint32_t *)d.revVar;
            if ((int)*revVar < 1) *revVar = 1;
            *(uint32_t *)(d.g + d.revOff) = 0x7fffffff;
            *(double *)(d.g + d.valOff) = v;
        } else if (d.isFloat) { // iOS 17: plain 32-bit float
            *(float *)(d.g + d.valOff) = (float)v;
        } else {
            *(double *)(d.g + d.valOff) = v;
        }
    } @catch (...) {
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Tweak entry point
// ---------------------------------------------------------------------------

static double AnimSpeedLoadMultiplier(void) {
    double mult = 80.0; // default: 80x
    @try {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@PREFS_PATH];
        double v = [[d objectForKey:@"Speed"] doubleValue];
        if (v > 0 && v <= 10000.0) mult = v;
    } @catch (...) {
    }
    return mult;
}

__attribute__((constructor)) static void AnimSpeedInit(void) {
    @autoreleasepool {
        @try {
            double mult = AnimSpeedLoadMultiplier();
            double coef = 1.0 / mult;
            if (coef < 0.0001) coef = 0.0001;
            // 1.0 is stock: never touch the global in that case, so we can't
            // clobber another tweak's override.
            if (fabs(coef - 1.0) > 1e-9) {
                animspeed_write_drag_coefficient(coef);
            }
        } @catch (...) {
        }
    }
}
