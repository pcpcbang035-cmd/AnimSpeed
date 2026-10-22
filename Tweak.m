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
#import <math.h>
#import "drag_discovery.h"

#define PREFS_PATH "/var/mobile/Library/Preferences/com.ho.animspeed.plist"

// ---------------------------------------------------------------------------
// UIAnimationDragCoefficient global discovery lives in drag_discovery.h
// (ported from SBTweaker, MIT — see the NOTICE block above). The scan core
// is pure C and unit-tested on the host (tests/test_discovery.c).
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Diagnostic load marker — the anti-placebo device.
// Don't trust feel; trust a file on disk. After a successful init, the tweak
// writes a small marker recording what it did. On a device where injection
// works, check it with Filza:
//
//   /var/mobile/Library/Preferences/com.ho.animspeed.loaded
//
// Marker contents:
//   mult=80.000        requested speed multiplier
//   coef=0.012500      coefficient actually written (1/mult)
//   drag_write=ok      ok | failed | skipped (skipped = stock 1.0, untouched)
//   <device timestamp>
//
// Toggle: set DiagnosticMarker = false in com.ho.animspeed.plist to disable.

#define MARKER_PATH "/var/mobile/Library/Preferences/com.ho.animspeed.loaded"

static bool AnimSpeedMarkerEnabled(NSDictionary *prefs) {
    id flag = [prefs objectForKey:@"DiagnosticMarker"];
    if (!flag) return true; // default: on
    return [flag boolValue];
}

static void AnimSpeedWriteMarker(double mult, double coef, const char *result) {
    @try {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@PREFS_PATH];
        if (!AnimSpeedMarkerEnabled(prefs)) return;
        NSString *content = [NSString stringWithFormat:
            @"mult=%.3f\ncoef=%.6f\ndrag_write=%s\n%@\n",
            mult, coef, result, [[NSDate date] description]];
        [content writeToFile:@MARKER_PATH atomically:YES
                    encoding:NSUTF8StringEncoding error:NULL];
    } @catch (...) {
    }
}

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
            const char *dragResult = "skipped";
            if (fabs(coef - 1.0) > 1e-9) {
                dragResult = animspeed_write_drag_coefficient(coef) ? "ok" : "failed";
            }
            // Diagnostic marker: prove on disk that the tweak actually ran.
            AnimSpeedWriteMarker(mult, coef, dragResult);
        } @catch (...) {
        }
    }
}
