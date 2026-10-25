/* Host-side unit test for the drag-coefficient disassembly scanner.
 *
 * Feeds synthetic ARM64 _SetUIAnimationDragCoefficient bodies into
 * animspeed_scan_drag() and checks the decoded global address, offsets,
 * and float-vs-double / gated-vs-ungated classification.
 *
 * Build & run (no device needed):
 *   cc -std=c99 -Wall -Wno-unused-function -I. tests/test_discovery.c \
 *       -o /tmp/test_discovery && /tmp/test_discovery
 *
 * (-Wno-unused-function: the header also provides the dlsym-based entry
 * point used by the tweak itself; the test only exercises the scan core.)
 */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "drag_discovery.h"

/* --- instruction builders (unsigned-offset forms) --- */
static uint32_t adrp(int rd) {                       /* ADRP Rd, . (page offset 0) */
    return 0x90000000u | (uint32_t)rd;
}
static uint32_t add_imm(int rd, int rn, uint32_t imm12) {
    return 0x91000000u | ((imm12 & 0xfff) << 10) | ((uint32_t)(rn & 31) << 5) | (uint32_t)(rd & 31);
}
static uint32_t ldr_w(int rt, int rn, uint32_t imm12) { /* LDR Wt, [Xn, #imm] */
    return 0xB9400000u | ((imm12 & 0xfff) << 10) | ((uint32_t)(rn & 31) << 5) | (uint32_t)(rt & 31);
}
static uint32_t ldr_x(int rt, int rn, uint32_t imm12) { /* LDR Xt, [Xn, #imm] */
    return 0xF9400000u | ((imm12 & 0xfff) << 10) | ((uint32_t)(rn & 31) << 5) | (uint32_t)(rt & 31);
}
static uint32_t str_s(int rt, int rn, uint32_t imm12) { /* STR St, [Xn, #imm] (float) */
    return 0xBD000000u | ((imm12 & 0xfff) << 10) | ((uint32_t)(rn & 31) << 5) | (uint32_t)(rt & 31);
}
static uint32_t str_d(int rt, int rn, uint32_t imm12) { /* STR Dt, [Xn, #imm] (double) */
    return 0xFD000000u | ((imm12 & 0xfff) << 10) | ((uint32_t)(rn & 31) << 5) | (uint32_t)(rt & 31);
}
static uint32_t str_w(int rt, int rn, uint32_t imm12) { /* STR Wt, [Xn, #imm] (sentinel) */
    return 0xB9000000u | ((imm12 & 0xfff) << 10) | ((uint32_t)(rn & 31) << 5) | (uint32_t)(rt & 31);
}
#define RET 0xD65F03C0u
#define NOP 0xD503201Fu

static int failures = 0;
#define CHECK(cond, ...) do { \
    if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
} while (0)

/* Page-aligned buffer so ADRP-with-zero-offset math is deterministic. */
static uint32_t *alloc_code(int nwords, uint64_t *page_out) {
    void *p = NULL;
    if (posix_memalign(&p, 4096, (size_t)nwords * 4) != 0) { perror("posix_memalign"); exit(1); }
    memset(p, 0, (size_t)nwords * 4);
    *page_out = (uint64_t)p & ~0xfffULL;
    return (uint32_t *)p;
}

/* iOS 17 style: ungated 32-bit float store. */
static void test_float_ungated(void) {
    int start_failures = failures;
    uint64_t page; uint32_t *c = alloc_code(8, &page);
    c[0] = adrp(8);
    c[1] = add_imm(8, 8, 0x120);
    c[2] = str_s(0, 8, 0x10);
    c[3] = RET;

    animspeed_drag_t d; memset(&d, 0, sizeof d);
    CHECK(animspeed_scan_drag(c, (uint64_t)c, &d), "float: scan should succeed");
    CHECK(d.g == page + 0x120, "float: g=%llx want %llx",
          (unsigned long long)d.g, (unsigned long long)(page + 0x120));
    CHECK(d.valOff == (0x10u << 2), "float: valOff=%u want %u", d.valOff, 0x10u << 2);
    CHECK(d.isFloat && !d.gated, "float: want isFloat && !gated");
    free(c);
    printf("float/ungated: %s\n", failures == start_failures ? "ok" : "FAIL");
}

/* iOS 18+ style: double store behind a revision gate. */
static void test_double_gated(void) {
    int start_failures = failures;
    uint64_t page; uint32_t *c = alloc_code(16, &page);
    c[0] = adrp(9);
    c[1] = ldr_w(10, 9, 0x80);      /* revVar = page + 0x80*4 = page+0x200 */
    c[2] = adrp(11);
    c[3] = ldr_x(12, 11, 0x41);     /* revOnce = page + 0x41*8 = page+0x208 */
    c[4] = adrp(8);
    c[5] = add_imm(8, 8, 0x100);
    c[6] = str_d(0, 8, 0x18);       /* g = page+0x100, valOff = 0x18*8 */
    c[7] = str_w(1, 8, 0);          /* sentinel on the same base -> revOff */
    c[8] = RET;

    animspeed_drag_t d; memset(&d, 0, sizeof d);
    CHECK(animspeed_scan_drag(c, (uint64_t)c, &d), "double: scan should succeed");
    CHECK(d.g == page + 0x100, "double: g=%llx want %llx",
          (unsigned long long)d.g, (unsigned long long)(page + 0x100));
    CHECK(d.valOff == (0x18u << 3), "double: valOff=%u want %u", d.valOff, 0x18u << 3);
    CHECK(!d.isFloat && d.gated, "double: want !isFloat && gated");
    CHECK(d.revVar == page + 0x200, "double: revVar=%llx", (unsigned long long)d.revVar);
    CHECK(d.revOnce == page + 0x208, "double: revOnce=%llx", (unsigned long long)d.revOnce);
    CHECK(d.revOff == 0, "double: revOff=%u want 0", d.revOff);
    free(c);
    printf("double/gated: %s\n", failures == start_failures ? "ok" : "FAIL");
}


/* iOS 18+ style, ADRP-only base: no ADD between ADRP and the stores.
 * The sentinel STR Wt uses the ADRP page base directly; the scanner must
 * resolve it the same way it resolves the STR Dt base (pv-or-pg), not
 * require an ADD-computed value. */
static void test_double_gated_adrp_only(void) {
    int start_failures = failures;
    uint64_t page; uint32_t *c = alloc_code(16, &page);
    c[0] = adrp(9);
    c[1] = ldr_w(10, 9, 0x80);      /* revVar = page + 0x200 */
    c[2] = adrp(11);
    c[3] = ldr_x(12, 11, 0x41);     /* revOnce = page + 0x208 */
    c[4] = adrp(8);                 /* no ADD: base is the page itself */
    c[5] = str_d(0, 8, 0x18);       /* g = page, valOff = 0x18*8 */
    c[6] = str_w(1, 8, 0x08);       /* sentinel on the same base -> revOff = 0x20 */
    c[7] = RET;

    animspeed_drag_t d; memset(&d, 0, sizeof d);
    CHECK(animspeed_scan_drag(c, (uint64_t)c, &d), "adrp-only: scan should succeed");
    CHECK(d.g == page, "adrp-only: g=%llx want %llx",
          (unsigned long long)d.g, (unsigned long long)page);
    CHECK(d.valOff == (0x18u << 3), "adrp-only: valOff=%u want %u", d.valOff, 0x18u << 3);
    CHECK(!d.isFloat && d.gated, "adrp-only: want !isFloat && gated");
    CHECK(d.revOff == (0x08u << 2), "adrp-only: revOff=%u want %u", d.revOff, 0x08u << 2);
    free(c);
    printf("double/gated ADRP-only: %s\n", failures == start_failures ? "ok" : "FAIL");
}

/* Garbage body: scanner must report failure, not a bogus address. */
static void test_no_match(void) {
    int start_failures = failures;
    uint64_t page; uint32_t *c = alloc_code(8, &page);
    for (int i = 0; i < 7; i++) c[i] = NOP;
    c[7] = RET;

    animspeed_drag_t d; memset(&d, 0, sizeof d);
    CHECK(!animspeed_scan_drag(c, (uint64_t)c, &d), "nomatch: scan should fail");
    free(c);
    printf("no-match: %s\n", failures == start_failures ? "ok" : "FAIL");
}

int main(void) {
    int before;
    before = failures; test_float_ungated();
    before = failures; test_double_gated();
    before = failures; test_double_gated_adrp_only();
    before = failures; test_no_match();
    (void)before;
    if (failures) { printf("%d FAILURE(S)\n", failures); return 1; }
    printf("all tests passed\n");
    return 0;
}
