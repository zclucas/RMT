/* Independent mascot host: load .p2lrt, layered window, named pipe.
   MIT runtime via p2l_runtime.dll. Notices: THIRD_PARTY_NOTICES.txt. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SCALE 0.38f
#define MAX_CMD 8
#define CMD_LEN 512
#define SAY_MAX 8
#define SAY_LEN 96
#define HIT_ALPHA 24

static const wchar_t PIPE_NAME[] = {
    0x5C, 0x5C, L'.', 0x5C, L'p', L'i', L'p', L'e', 0x5C,
    L'R', L'M', L'T', L'_', L'L', L'2', L'd', L'H', L'o', L's', L't', 0};

typedef struct P2lRig P2lRig;
typedef uint32_t (*fn_u32_void)(void);
typedef const char *(*fn_cstr_void)(void);
typedef P2lRig *(*fn_load)(const uint8_t *, size_t, char *, size_t);
typedef void (*fn_rig)(P2lRig *);
typedef void (*fn_update)(P2lRig *, float);
typedef void (*fn_canvas)(const P2lRig *, float *, float *);
typedef uint32_t (*fn_count)(const P2lRig *);
typedef const char *(*fn_clip_str)(const P2lRig *, uint32_t);
typedef void (*fn_play)(P2lRig *, int32_t);
typedef void (*fn_expr)(P2lRig *, int32_t);
typedef void (*fn_look)(P2lRig *, float, float);
typedef void (*fn_lip)(P2lRig *, float);
typedef void (*fn_behaviors)(P2lRig *, uint32_t);
typedef bool (*fn_strength)(P2lRig *, float, float, float);
typedef bool (*fn_render)(P2lRig *, uint8_t *, uint32_t, uint32_t, const float *, uint32_t);
typedef int32_t (*fn_hit)(const P2lRig *, float, float);
typedef bool (*fn_clip_done)(const P2lRig *);

static fn_u32_void p2l_abi_version;
static fn_cstr_void p2l_version;
static fn_load p2l_rig_load;
static fn_rig p2l_rig_free;
static fn_rig p2l_physics_stabilize;
static fn_update p2l_update;
static fn_canvas p2l_canvas;
static fn_count p2l_clip_count;
static fn_clip_str p2l_clip_id;
static fn_clip_str p2l_clip_name;
static fn_clip_str p2l_clip_group;
static fn_play p2l_play;
static fn_count p2l_expression_count;
static fn_clip_str p2l_expression_id;
static fn_clip_str p2l_expression_name;
static fn_expr p2l_expression;
static fn_look p2l_look_at;
static fn_lip p2l_lip_sync;
static fn_behaviors p2l_behaviors;
static fn_strength p2l_behavior_strength;
static fn_render p2l_render;
static fn_hit p2l_hit_test;
static fn_clip_str p2l_hit_area_id;
static fn_clip_str p2l_hit_area_name;
static fn_clip_done p2l_clip_finished;

static HMODULE g_dll;
static P2lRig *g_rig;
static CRITICAL_SECTION g_lock;
static char g_cmds[MAX_CMD][CMD_LEN];
static int g_ncmd;
static volatile int g_quit;
static volatile DWORD g_parent_pid;
static HWND g_hwnd;
static int g_drag, g_dx, g_dy, g_model_press;
static int g_mw, g_mh, g_vw, g_vh;
static int g_dpi = 96, g_pad_top = 56, g_fs_hide;
static uint8_t *g_rgba;
static uint8_t *g_bgra;
static int g_talking, g_need_idle;
static DWORD g_idle_at;
static char g_say_lines[SAY_MAX][SAY_LEN];
static char g_say_hint[SAY_LEN];
static char g_head_lines[SAY_MAX][SAY_LEN];
static char g_body_lines[SAY_MAX][SAY_LEN];
static int g_head_n, g_body_n, g_head_last, g_body_last;
static int g_say_n, g_say_i, g_say_hover, g_say_press;
static DWORD g_say_until, g_say_hold, g_say_born;
static RECT g_say_rc;
static int g_press_x, g_press_y;
static int g_ui_alpha = 255;
static int dip(int v);

static void *must_sym(const char *name) {
    void *p = (void *)GetProcAddress(g_dll, name);
    if (!p) {
        char msg[160];
        wsprintfA(msg, "p2l_runtime.dll missing %s", name);
        MessageBoxA(NULL, msg, "L2dHost", MB_ICONERROR);
        ExitProcess(1);
    }
    return p;
}

static int ieq(const char *a, const char *b) {
    if (!a || !b)
        return 0;
    while (*a && *b) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z')
            ca += 32;
        if (cb >= 'A' && cb <= 'Z')
            cb += 32;
        if (ca != cb)
            return 0;
        a++;
        b++;
    }
    return *a == 0 && *b == 0;
}

static int icontains(const char *s, const char *sub) {
    int i, j;
    if (!s || !sub || !sub[0])
        return 0;
    for (i = 0; s[i]; i++) {
        for (j = 0; sub[j]; j++) {
            char ca = s[i + j], cb = sub[j];
            if (!ca)
                return 0;
            if (ca >= 'A' && ca <= 'Z')
                ca += 32;
            if (cb >= 'A' && cb <= 'Z')
                cb += 32;
            if (ca != cb)
                break;
        }
        if (!sub[j])
            return 1;
    }
    return 0;
}

static int split_lines(const char *src, char dst[][SAY_LEN], int maxn) {
    const char *p;
    int n, c = 0;
    if (!src || !src[0])
        return 0;
    p = src;
    while (*p && c < maxn) {
        n = 0;
        while (*p && *p != '|' && n + 1 < SAY_LEN)
            dst[c][n++] = *p++;
        dst[c][n] = 0;
        if (n)
            c++;
        if (*p == '|')
            p++;
    }
    return c;
}

static void tips_init(void) {
    g_head_n = split_lines("头发要乱了|摸头是奖励吗|再摸要收费了|耳朵很敏感的", g_head_lines, SAY_MAX);
    g_body_n = split_lines("不要戳那里|有话好好说|我在认真工作|嗯？干什么", g_body_lines, SAY_MAX);
    g_head_last = g_body_last = -1;
}

static void tips_set(const char *head, const char *body) {
    int n;
    n = split_lines(head, g_head_lines, SAY_MAX);
    if (n > 0)
        g_head_n = n;
    n = split_lines(body, g_body_lines, SAY_MAX);
    if (n > 0)
        g_body_n = n;
}

static int json_str(const char *j, const char *key, char *out, int cap) {
    char pat[80];
    const char *p;
    int n = 0, klen = (int)strlen(key);
    if (klen > 60)
        return 0;
    pat[0] = '"';
    memcpy(pat + 1, key, (size_t)klen);
    pat[1 + klen] = '"';
    pat[2 + klen] = 0;
    p = strstr(j, pat);
    if (!p)
        return 0;
    p = strchr(p + klen + 2, ':');
    if (!p)
        return 0;
    p++;
    while (*p == ' ' || *p == '\t')
        p++;
    if (*p != '"')
        return 0;
    p++;
    while (*p && *p != '"' && n + 1 < cap) {
        if (*p == '\\' && p[1])
            p++;
        out[n++] = *p++;
    }
    out[n] = 0;
    return n > 0;
}

static int json_num(const char *j, const char *key, float *out) {
    char pat[80];
    const char *p;
    int klen = (int)strlen(key);
    if (klen > 60)
        return 0;
    pat[0] = '"';
    memcpy(pat + 1, key, (size_t)klen);
    pat[1 + klen] = '"';
    pat[2 + klen] = 0;
    p = strstr(j, pat);
    if (!p)
        return 0;
    p = strchr(p + klen + 2, ':');
    if (!p)
        return 0;
    *out = (float)atof(p + 1);
    return 1;
}

static int find_clip(const char *name) {
    uint32_t i, n;
    if (!g_rig || !name || !name[0])
        return -1;
    n = p2l_clip_count(g_rig);
    for (i = 0; i < n; i++) {
        if (ieq(p2l_clip_group(g_rig, i), name) || ieq(p2l_clip_id(g_rig, i), name) ||
            ieq(p2l_clip_name(g_rig, i), name))
            return (int)i;
    }
    return -1;
}

static int find_expr(const char *name) {
    uint32_t i, n;
    if (!g_rig || !name || !name[0])
        return -1;
    n = p2l_expression_count(g_rig);
    for (i = 0; i < n; i++) {
        if (ieq(p2l_expression_id(g_rig, i), name) || ieq(p2l_expression_name(g_rig, i), name))
            return (int)i;
    }
    return -1;
}

static void say_clear(void) {
    g_say_n = 0;
    g_say_i = 0;
    g_say_until = 0;
    g_say_born = 0;
    g_say_hover = 0;
    g_say_press = 0;
    g_say_hint[0] = 0;
    g_say_rc.left = g_say_rc.top = g_say_rc.right = g_say_rc.bottom = 0;
}

static void say_arm(void) {
    g_say_until = GetTickCount() + (g_say_hold ? g_say_hold : 4500);
}

static void say_set(const char *text, const char *lines, const char *hint, float ms) {
    const char *p;
    int n;
    say_clear();
    if (!text || !text[0])
        return;
    g_say_hold = (DWORD)(ms > 800.f ? ms : 4500.f);
    if (hint && hint[0])
        lstrcpynA(g_say_hint, hint, SAY_LEN);
    p = (lines && lines[0]) ? lines : text;
    while (*p && g_say_n < SAY_MAX) {
        n = 0;
        while (*p && *p != '|' && n + 1 < SAY_LEN)
            g_say_lines[g_say_n][n++] = *p++;
        g_say_lines[g_say_n][n] = 0;
        if (n)
            g_say_n++;
        if (*p == '|')
            p++;
    }
    if (g_say_n < 1) {
        lstrcpynA(g_say_lines[0], text, SAY_LEN);
        g_say_n = 1;
    }
    g_say_i = 0;
    for (n = 0; n < g_say_n; n++) {
        if (ieq(g_say_lines[n], text)) {
            g_say_i = n;
            break;
        }
    }
    say_arm();
    g_say_born = GetTickCount();
}

static int say_hit(int x, int y) {
    if (g_say_n <= 0)
        return 0;
    return x >= g_say_rc.left && x < g_say_rc.right && y >= g_say_rc.top && y < g_say_rc.bottom;
}

static void go_idle(void) {
    int idle;
    if (!g_rig)
        return;
    idle = find_clip("Idle");
    if (idle >= 0)
        p2l_play(g_rig, idle);
    p2l_expression(g_rig, -1);
    p2l_lip_sync(g_rig, 0.f);
    g_talking = 0;
    g_need_idle = 0;
    g_idle_at = 0;
}

static void arm_idle(DWORD ms) {
    g_need_idle = 1;
    g_idle_at = GetTickCount() + (ms ? ms : 6000);
}

static void tick_idle(void) {
    int done = 0;
    if (!g_need_idle || !g_rig)
        return;
    if (p2l_clip_finished && p2l_clip_finished(g_rig))
        done = 1;
    if (g_talking && g_say_n <= 0)
        done = 1;
    if (g_idle_at && GetTickCount() >= g_idle_at)
        done = 1;
    if (done)
        go_idle();
}

static void say_play_kind(const char *kind) {
    int idx, expr;
    if (!g_rig || !kind || !kind[0])
        return;
    if (ieq(kind, "start")) {
        idx = find_clip("Talk");
        if (idx < 0)
            idx = find_clip("talk");
        if (idx >= 0)
            p2l_play(g_rig, idx);
        p2l_expression(g_rig, find_expr("smile"));
        p2l_lip_sync(g_rig, 0.55f);
        g_talking = 1;
        arm_idle(8000);
        return;
    }
    if (ieq(kind, "end")) {
        idx = find_clip("Nod");
        if (idx < 0)
            idx = find_clip("Idle");
        if (idx >= 0)
            p2l_play(g_rig, idx);
        p2l_lip_sync(g_rig, 0.0f);
        g_talking = 0;
        arm_idle(5000);
        return;
    }
    if (ieq(kind, "head")) {
        idx = find_clip("Nod");
        if (idx >= 0)
            p2l_play(g_rig, idx);
        p2l_expression(g_rig, find_expr("shy"));
        p2l_lip_sync(g_rig, 0.0f);
        g_talking = 0;
        arm_idle(5000);
        return;
    }
    if (ieq(kind, "body")) {
        idx = find_clip("Shake");
        if (idx < 0)
            idx = find_clip("Nod");
        if (idx >= 0)
            p2l_play(g_rig, idx);
        expr = find_expr("surprised");
        if (expr < 0)
            expr = find_expr("angry");
        p2l_expression(g_rig, expr);
        p2l_lip_sync(g_rig, 0.0f);
        g_talking = 0;
        arm_idle(5000);
    }
}

static void say_pick(char lines[][SAY_LEN], int n, int *last, const char *kind) {
    int i;
    if (n < 1)
        return;
    i = (int)(GetTickCount() % (DWORD)n);
    if (n > 1 && i == *last)
        i = (i + 1) % n;
    *last = i;
    say_set(lines[i], NULL, NULL, 4500.f);
    say_play_kind(kind);
}

static void on_model_click(int x, int y) {
    float cw = 0, ch = 0, cx, cy;
    int32_t idx;
    const char *id;
    if (!g_rig || !p2l_hit_test)
        return;
    y -= g_pad_top;
    if (x < 0 || y < 0 || x >= g_mw || y >= g_mh)
        return;
    p2l_canvas(g_rig, &cw, &ch);
    if (cw < 1.f)
        cw = 1024.f;
    if (ch < 1.f)
        ch = 1024.f;
    cx = (float)x * cw / (float)g_mw;
    cy = (float)y * ch / (float)g_mh;
    idx = p2l_hit_test(g_rig, cx, cy);
    if (idx < 0)
        return;
    id = p2l_hit_area_id ? p2l_hit_area_id(g_rig, (uint32_t)idx) : NULL;
    if (!id || !id[0])
        id = p2l_hit_area_name ? p2l_hit_area_name(g_rig, (uint32_t)idx) : NULL;
    if (icontains(id, "head"))
        say_pick(g_head_lines, g_head_n, &g_head_last, "head");
    else
        say_pick(g_body_lines, g_body_n, &g_body_last, "body");
}

static float clampf(float v, float lo, float hi) {
    if (v < lo)
        return lo;
    if (v > hi)
        return hi;
    return v;
}

static void follow_mouse(HWND hwnd) {
    POINT pt;
    RECT rc;
    float dx, dy, r, lx, ly;
    int fx, fy;
    if (!g_rig || !p2l_look_at || !hwnd)
        return;
    GetCursorPos(&pt);
    GetWindowRect(hwnd, &rc);
    fx = rc.left + g_vw / 2;
    fy = rc.top + g_pad_top + g_mh * 28 / 100;
    dx = (float)(pt.x - fx);
    dy = (float)(pt.y - fy);
    r = (float)g_mw * 0.9f;
    if (r < 240.f)
        r = 240.f;
    lx = clampf(dx / r, -1.f, 1.f);
    ly = clampf(-dy / r, -1.f, 1.f);
    p2l_look_at(g_rig, lx, ly);
}

static void blend_px(int x, int y, int r, int g, int b, int a) {
    size_t i;
    int sr, sg, sb, sa, dr, dg, db, da, inv, oa;
    if (x < 0 || y < 0 || x >= g_vw || y >= g_vh || a <= 0)
        return;
    a = a * g_ui_alpha / 255;
    if (a <= 0)
        return;
    if (a > 255)
        a = 255;
    i = ((size_t)y * (size_t)g_vw + (size_t)x) * 4;
    sa = a;
    sr = r * sa / 255;
    sg = g * sa / 255;
    sb = b * sa / 255;
    db = g_bgra[i + 0];
    dg = g_bgra[i + 1];
    dr = g_bgra[i + 2];
    da = g_bgra[i + 3];
    inv = 255 - sa;
    g_bgra[i + 0] = (uint8_t)(sb + db * inv / 255);
    g_bgra[i + 1] = (uint8_t)(sg + dg * inv / 255);
    g_bgra[i + 2] = (uint8_t)(sr + dr * inv / 255);
    oa = sa + da * inv / 255;
    g_bgra[i + 3] = (uint8_t)(oa > 255 ? 255 : oa);
}

static float rr_sdf(float px, float py, float x0, float y0, float x1, float y1, float rad) {
    float cx = (x0 + x1) * 0.5f;
    float cy = (y0 + y1) * 0.5f;
    float hw = (x1 - x0) * 0.5f;
    float hh = (y1 - y0) * 0.5f;
    float dx = fabsf(px - cx) - (hw - rad);
    float dy = fabsf(py - cy) - (hh - rad);
    float ox = dx > 0.f ? dx : 0.f;
    float oy = dy > 0.f ? dy : 0.f;
    float m = dx > dy ? dx : dy;
    return sqrtf(ox * ox + oy * oy) + (m < 0.f ? m : 0.f) - rad;
}

static SIZE measure_utf8(const char *utf8, int size) {
    SIZE sz = {0, 0};
    wchar_t wbuf[256];
    HDC dc;
    HFONT font, of;
    RECT rc;
    if (!utf8 || !utf8[0])
        return sz;
    if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wbuf, 256) <= 0)
        return sz;
    dc = CreateCompatibleDC(NULL);
    if (!dc)
        return sz;
    font = CreateFontW(-size, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
                       L"Microsoft YaHei UI");
    of = (HFONT)SelectObject(dc, font);
    rc.left = rc.top = rc.right = rc.bottom = 0;
    DrawTextW(dc, wbuf, -1, &rc, DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX);
    sz.cx = rc.right - rc.left;
    sz.cy = rc.bottom - rc.top;
    SelectObject(dc, of);
    DeleteObject(font);
    DeleteDC(dc);
    return sz;
}

static void draw_tail(int cx, int y0, int tw, int th) {
    int y, x, half;
    for (y = 0; y < th; y++) {
        half = (tw * (th - y)) / (2 * th);
        if (half < 1)
            half = 1;
        for (x = cx - half; x <= cx + half; x++) {
            int edge = (x == cx - half || x == cx + half || y == th - 1);
            if (edge)
                blend_px(x, y0 + y, 224, 186, 140, 150);
            else
                blend_px(x, y0 + y, 236, 217, 188, 220);
        }
    }
}

static void draw_round_chip(float x0, float y0, float x1, float y1, float rad) {
    int minx = (int)x0 - 4, miny = (int)y0 - 2, maxx = (int)x1 + 6, maxy = (int)y1 + 8;
    int x, y;
    if (rad < 2.f)
        rad = 2.f;
    for (y = miny; y < maxy; y++) {
        for (x = minx; x < maxx; x++) {
            float px = (float)x + 0.5f;
            float py = (float)y + 0.5f;
            float sdf = rr_sdf(px, py, x0, y0, x1, y1, rad);
            float sh = rr_sdf(px - 1.f, py - 3.f, x0, y0, x1, y1, rad + 0.4f);
            float shc = clampf(1.4f - sh, 0.f, 1.f);
            if (shc > 0.f && sdf > -0.2f)
                blend_px(x, y, 191, 158, 118, (int)(shc * 42.f + 0.5f));
            float fill = clampf(0.55f - sdf, 0.f, 1.f);
            if (fill > 0.f)
                blend_px(x, y, 236, 217, 188, (int)(fill * 220.f + 0.5f));
            float edge = clampf(1.15f - fabsf(sdf), 0.f, 1.f);
            if (edge > 0.f)
                blend_px(x, y, 224, 186, 140, (int)(edge * 150.f + 0.5f));
        }
    }
}

static void draw_utf8(int x, int y, int w, int h, const char *utf8, int r, int g, int b, int size) {
    wchar_t wbuf[256];
    BITMAPINFO bmi;
    void *bits = NULL;
    HDC dc;
    HBITMAP hb, old;
    HFONT font, of;
    HBRUSH br;
    RECT rc;
    uint8_t *p;
    int xx, yy;
    if (!utf8 || !utf8[0] || w < 8 || h < 8)
        return;
    if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wbuf, 256) <= 0)
        return;
    memset(&bmi, 0, sizeof bmi);
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w;
    bmi.bmiHeader.biHeight = -h;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    dc = CreateCompatibleDC(NULL);
    hb = CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!dc || !hb || !bits) {
        if (hb)
            DeleteObject(hb);
        if (dc)
            DeleteDC(dc);
        return;
    }
    old = (HBITMAP)SelectObject(dc, hb);
    rc.left = rc.top = 0;
    rc.right = w;
    rc.bottom = h;
    br = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(dc, &rc, br);
    DeleteObject(br);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    font = CreateFontW(-size, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
                       L"Microsoft YaHei UI");
    of = (HFONT)SelectObject(dc, font);
    DrawTextW(dc, wbuf, -1, &rc, DT_CENTER | DT_VCENTER | DT_WORDBREAK | DT_NOPREFIX | DT_END_ELLIPSIS);
    SelectObject(dc, of);
    DeleteObject(font);
    p = (uint8_t *)bits;
    for (yy = 0; yy < h; yy++) {
        for (xx = 0; xx < w; xx++) {
            uint8_t *s = p + ((size_t)yy * (size_t)w + (size_t)xx) * 4;
            int cov = s[0];
            if (s[1] > cov)
                cov = s[1];
            if (s[2] > cov)
                cov = s[2];
            if (cov < 8)
                continue;
            blend_px(x + xx, y + yy, r, g, b, cov);
        }
    }
    SelectObject(dc, old);
    DeleteObject(hb);
    DeleteDC(dc);
}

static void draw_balloon(void) {
    int bx, by, bw, bh, fade;
    DWORD now;
    if (g_say_n <= 0)
        return;
    now = GetTickCount();
    if (!g_say_hover && g_say_until && now > g_say_until) {
        say_clear();
        return;
    }
    fade = 255;
    if (g_say_born && now >= g_say_born) {
        DWORD inn = now - g_say_born;
        if (inn < 180)
            fade = (int)(inn * 255 / 180);
    }
    if (!g_say_hover && g_say_until && g_say_until - now < 750) {
        int left = (int)(g_say_until - now);
        int fo = left * 255 / 750;
        if (fo < 0)
            fo = 0;
        if (fo < fade)
            fade = fo;
    }
    g_ui_alpha = fade;
    {
        SIZE main, hint;
        int pad_x = dip(10), pad_y = dip(6), gap, tail = dip(7), fs = dip(13), hs = dip(10);
        main = measure_utf8(g_say_lines[g_say_i], fs);
        hint.cx = hint.cy = 0;
        if (g_say_hint[0])
            hint = measure_utf8(g_say_hint, hs);
        gap = g_say_hint[0] ? dip(1) : 0;
        if (main.cx < 1)
            main.cx = dip(48);
        if (main.cy < 1)
            main.cy = dip(16);
        bw = main.cx > hint.cx ? main.cx : hint.cx;
        bw += pad_x * 2;
        if (bw < dip(64))
            bw = dip(64);
        if (bw > g_vw - dip(20))
            bw = g_vw - dip(20);
        bh = pad_y + main.cy + gap + hint.cy + pad_y;
        bx = (g_vw - bw) / 2;
        by = dip(4);
        if (by + bh + tail > g_pad_top - 2)
            by = 2;
        g_say_rc.left = bx;
        g_say_rc.top = by;
        g_say_rc.right = bx + bw;
        g_say_rc.bottom = by + bh + tail;
        draw_round_chip((float)bx, (float)by, (float)(bx + bw), (float)(by + bh), (float)dip(10));
        draw_tail(bx + bw / 2, by + bh - 2, dip(12), tail);
        draw_utf8(bx + pad_x, by + pad_y, bw - pad_x * 2, main.cy, g_say_lines[g_say_i], 90, 64, 48, fs);
        if (g_say_hint[0])
            draw_utf8(bx + pad_x, by + pad_y + main.cy + gap, bw - pad_x * 2, hint.cy > 0 ? hint.cy : dip(12), g_say_hint,
                      168, 132, 108, hs);
    }
    g_ui_alpha = 255;
}

static DWORD parse_parent_pid(const wchar_t *cmd) {
    DWORD pid = 0;
    if (!cmd)
        return 0;
    while (*cmd) {
        if (*cmd >= L'0' && *cmd <= L'9') {
            while (*cmd >= L'0' && *cmd <= L'9') {
                pid = pid * 10u + (DWORD)(*cmd - L'0');
                cmd++;
            }
            return pid;
        }
        cmd++;
    }
    return 0;
}

static DWORD WINAPI parent_thread(LPVOID unused) {
    HANDLE h = NULL;
    DWORD watched = 0;
    (void)unused;
    while (!g_quit) {
        DWORD pid = g_parent_pid;
        if (pid != watched) {
            if (h) {
                CloseHandle(h);
                h = NULL;
            }
            watched = pid;
            if (pid)
                h = OpenProcess(SYNCHRONIZE, FALSE, pid);
            if (pid && !h) {
                g_quit = 1;
                if (g_hwnd)
                    PostMessageW(g_hwnd, WM_CLOSE, 0, 0);
                break;
            }
        }
        if (!h) {
            Sleep(200);
            continue;
        }
        if (WaitForSingleObject(h, 250) == WAIT_OBJECT_0) {
            g_quit = 1;
            if (g_hwnd)
                PostMessageW(g_hwnd, WM_CLOSE, 0, 0);
            break;
        }
    }
    if (h)
        CloseHandle(h);
    return 0;
}

static int pipe_try_send(const char *line) {
    int i;
    for (i = 0; i < 8; i++) {
        HANDLE h = CreateFileW(PIPE_NAME, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        DWORD n = 0;
        if (h != INVALID_HANDLE_VALUE) {
            WriteFile(h, line, (DWORD)lstrlenA(line), &n, NULL);
            CloseHandle(h);
            return 1;
        }
        Sleep(50);
    }
    return 0;
}

static int handoff_existing(DWORD pid) {
    HWND exist = FindWindowW(L"RMT_L2dHost", NULL);
    char msg[96];
    int i;
    if (!exist)
        return 0;
    if (pid)
        wsprintfA(msg, "{\"cmd\":\"ping\",\"pid\":%u}\n", pid);
    else
        lstrcpyA(msg, "{\"cmd\":\"ping\"}\n");
    if (pipe_try_send(msg))
        return 1;
    PostMessageW(exist, WM_CLOSE, 0, 0);
    for (i = 0; i < 20 && IsWindow(exist); i++)
        Sleep(50);
    return FindWindowW(L"RMT_L2dHost", NULL) != NULL;
}

static void apply_cmd(const char *line) {
    char cmd[64] = {0}, name[96] = {0}, text[SAY_LEN] = {0}, lines[CMD_LEN] = {0}, hint[SAY_LEN] = {0};
    float x, y, open, ms;
    if (!json_str(line, "cmd", cmd, 64))
        return;
    if (ieq(cmd, "quit")) {
        g_quit = 1;
        if (g_hwnd)
            PostMessageW(g_hwnd, WM_CLOSE, 0, 0);
        return;
    }
    if (ieq(cmd, "ping")) {
        float pid = 0;
        if (json_num(line, "pid", &pid) && pid > 0.f)
            g_parent_pid = (DWORD)pid;
        return;
    }
    if (ieq(cmd, "tips")) {
        char head[CMD_LEN] = {0}, body[CMD_LEN] = {0};
        json_str(line, "head", head, CMD_LEN);
        json_str(line, "body", body, CMD_LEN);
        tips_set(head, body);
        return;
    }
    if (ieq(cmd, "say")) {
        char kind[32] = {0};
        ms = 4500;
        json_str(line, "text", text, SAY_LEN);
        json_str(line, "lines", lines, CMD_LEN);
        json_str(line, "hint", hint, SAY_LEN);
        json_str(line, "kind", kind, 32);
        json_num(line, "ms", &ms);
        if (!text[0])
            say_clear();
        else
            say_set(text, lines, hint, ms);
        say_play_kind(kind);
        return;
    }
    if (!g_rig)
        return;
    if (ieq(cmd, "motion") && json_str(line, "name", name, 96)) {
        int idx = find_clip(name);
        if (idx < 0 && ieq(name, "talk"))
            idx = find_clip("Talk");
        if (idx < 0 && ieq(name, "idle"))
            idx = find_clip("Idle");
        if (idx >= 0)
            p2l_play(g_rig, idx);
        g_talking = ieq(name, "talk");
        if (g_talking)
            p2l_lip_sync(g_rig, 0.55f);
        if (ieq(name, "idle"))
            go_idle();
        else
            arm_idle(6000);
        return;
    }
    if (ieq(cmd, "expression") && json_str(line, "name", name, 96)) {
        p2l_expression(g_rig, find_expr(name));
        return;
    }
    if (ieq(cmd, "look_at")) {
        x = y = 0;
        json_num(line, "x", &x);
        json_num(line, "y", &y);
        p2l_look_at(g_rig, x, y);
        return;
    }
    if (ieq(cmd, "lipsync")) {
        open = 0;
        json_num(line, "open", &open);
        p2l_lip_sync(g_rig, open);
    }
}

static DWORD WINAPI pipe_thread(LPVOID unused) {
    (void)unused;
    while (!g_quit) {
        HANDLE pipe = CreateNamedPipeW(PIPE_NAME, PIPE_ACCESS_INBOUND,
                                       PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0, NULL);
        char buf[2048];
        DWORD n = 0;
        if (pipe == INVALID_HANDLE_VALUE) {
            Sleep(400);
            continue;
        }
        if (!ConnectNamedPipe(pipe, NULL) && GetLastError() != ERROR_PIPE_CONNECTED) {
            CloseHandle(pipe);
            continue;
        }
        while (!g_quit && ReadFile(pipe, buf, sizeof(buf) - 1, &n, NULL) && n) {
            char *line, *ctx = NULL;
            buf[n] = 0;
            line = strtok_s(buf, "\r\n", &ctx);
            while (line) {
                EnterCriticalSection(&g_lock);
                if (g_ncmd < MAX_CMD) {
                    strncpy_s(g_cmds[g_ncmd], CMD_LEN, line, _TRUNCATE);
                    g_ncmd++;
                }
                LeaveCriticalSection(&g_lock);
                line = strtok_s(NULL, "\r\n", &ctx);
            }
        }
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
    }
    return 0;
}

static void drain_cmds(void) {
    char local[MAX_CMD][CMD_LEN];
    int n, i;
    EnterCriticalSection(&g_lock);
    n = g_ncmd;
    memcpy(local, g_cmds, sizeof(local[0]) * n);
    g_ncmd = 0;
    LeaveCriticalSection(&g_lock);
    for (i = 0; i < n; i++)
        apply_cmd(local[i]);
}

static wchar_t *exe_dir(void) {
    static wchar_t dir[MAX_PATH];
    int i, last = 0;
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    for (i = 0; dir[i]; i++) {
        if (dir[i] == 0x5C)
            last = i;
    }
    dir[last] = 0;
    return dir;
}

static void path_join(wchar_t *out, const wchar_t *a, const wchar_t *b) {
    int n;
    lstrcpyW(out, a);
    n = lstrlenW(out);
    if (n && out[n - 1] != 0x5C) {
        out[n] = 0x5C;
        out[n + 1] = 0;
    }
    lstrcatW(out, b);
}

static void clamp_pos(int *x, int *y) {
    int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    int m = 48;
    if (vw < 1)
        vw = GetSystemMetrics(SM_CXSCREEN);
    if (vh < 1)
        vh = GetSystemMetrics(SM_CYSCREEN);
    if (*x + g_vw < vx + m)
        *x = vx + m - g_vw;
    if (*y + g_vh < vy + m)
        *y = vy + m - g_vh;
    if (*x > vx + vw - m)
        *x = vx + vw - m;
    if (*y > vy + vh - m)
        *y = vy + vh - m;
}

static int load_pos(int *x, int *y) {
    wchar_t path[MAX_PATH];
    char buf[64] = {0};
    HANDLE f;
    DWORD n = 0;
    path_join(path, exe_dir(), L"L2dHost.pos");
    f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return 0;
    if (!ReadFile(f, buf, sizeof buf - 1, &n, NULL) || n < 3) {
        CloseHandle(f);
        return 0;
    }
    CloseHandle(f);
    buf[n] = 0;
    return sscanf(buf, "%d %d", x, y) == 2;
}

static int dip(int v) {
    return (v * g_dpi + 48) / 96;
}

static void enable_dpi(void) {
    HMODULE user = GetModuleHandleW(L"user32.dll");
    HMODULE shcore;
    typedef BOOL(WINAPI * fn_ctx)(HANDLE);
    fn_ctx setctx;
    if (user) {
        setctx = (fn_ctx)GetProcAddress(user, "SetProcessDpiAwarenessContext");
        if (setctx) {
            if (setctx((HANDLE)(intptr_t)-4))
                return;
            setctx((HANDLE)(intptr_t)-3);
            return;
        }
    }
    shcore = LoadLibraryW(L"Shcore.dll");
    if (shcore) {
        typedef HRESULT(WINAPI * fn_aw)(int);
        fn_aw setaw = (fn_aw)GetProcAddress(shcore, "SetProcessDpiAwareness");
        if (setaw)
            setaw(2);
        FreeLibrary(shcore);
        return;
    }
    SetProcessDPIAware();
}

static int monitor_dpi_at(int x, int y) {
    POINT pt;
    HMONITOR mon;
    UINT dx = 96, dy = 96;
    HMODULE shcore;
    typedef HRESULT(WINAPI * fn_mon)(HMONITOR, int, UINT *, UINT *);
    fn_mon getdpi;
    HDC dc;
    int dpi;
    pt.x = x;
    pt.y = y;
    mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
    shcore = LoadLibraryW(L"Shcore.dll");
    if (shcore) {
        getdpi = (fn_mon)GetProcAddress(shcore, "GetDpiForMonitor");
        if (getdpi && getdpi(mon, 0, &dx, &dy) >= 0 && dx >= 96) {
            FreeLibrary(shcore);
            return (int)dx;
        }
        FreeLibrary(shcore);
    }
    dc = GetDC(NULL);
    dpi = GetDeviceCaps(dc, LOGPIXELSX);
    ReleaseDC(NULL, dc);
    return dpi < 96 ? 96 : dpi;
}

static int pixel_alpha(int x, int y) {
    size_t i;
    if (!g_bgra || x < 0 || y < 0 || x >= g_vw || y >= g_vh)
        return 0;
    i = ((size_t)y * (size_t)g_vw + (size_t)x) * 4;
    return g_bgra[i + 3];
}

static int is_other_fullscreen(void) {
    HWND fg;
    RECT wr;
    MONITORINFO mi;
    wchar_t cls[64];
    static HRESULT(WINAPI * quns)(int *) = NULL;
    static int quns_tried;
    int st = 0;
    if (!quns_tried) {
        HMODULE shell = LoadLibraryW(L"shell32.dll");
        quns_tried = 1;
        if (shell)
            quns = (HRESULT(WINAPI *)(int *))GetProcAddress(shell, "SHQueryUserNotificationState");
    }
    if (quns && quns(&st) >= 0 && (st == 3 || st == 4))
        return 1;
    fg = GetForegroundWindow();
    if (!fg || fg == g_hwnd)
        return 0;
    GetClassNameW(fg, cls, 64);
    if (!lstrcmpiW(cls, L"Progman") || !lstrcmpiW(cls, L"WorkerW") || !lstrcmpiW(cls, L"Shell_TrayWnd") ||
        !lstrcmpiW(cls, L"RMT_L2dHost"))
        return 0;
    GetWindowRect(fg, &wr);
    mi.cbSize = sizeof mi;
    if (!GetMonitorInfoW(MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST), &mi))
        return 0;
    if (wr.left > mi.rcMonitor.left + 4 || wr.top > mi.rcMonitor.top + 4 || wr.right < mi.rcMonitor.right - 4 ||
        wr.bottom < mi.rcMonitor.bottom - 4)
        return 0;
    return 1;
}

static void tick_fullscreen(HWND hwnd) {
    int hide;
    if (!hwnd || g_drag)
        return;
    hide = is_other_fullscreen();
    if (hide == g_fs_hide)
        return;
    g_fs_hide = hide;
    ShowWindow(hwnd, hide ? SW_HIDE : SW_SHOWNOACTIVATE);
}

static void save_pos(HWND hwnd) {
    wchar_t path[MAX_PATH];
    char line[64];
    RECT rc;
    HANDLE f;
    DWORD n = 0;
    if (!hwnd)
        return;
    GetWindowRect(hwnd, &rc);
    path_join(path, exe_dir(), L"L2dHost.pos");
    wsprintfA(line, "%d %d\n", rc.left, rc.top);
    f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return;
    WriteFile(f, line, (DWORD)lstrlenA(line), &n, NULL);
    CloseHandle(f);
}

static int read_file(const wchar_t *path, uint8_t **bytes, size_t *len) {
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    DWORD got = 0;
    LARGE_INTEGER sz;
    if (f == INVALID_HANDLE_VALUE)
        return 0;
    if (!GetFileSizeEx(f, &sz) || sz.QuadPart <= 0 || sz.QuadPart > 80 * 1024 * 1024) {
        CloseHandle(f);
        return 0;
    }
    *len = (size_t)sz.QuadPart;
    *bytes = (uint8_t *)malloc(*len);
    if (!*bytes || !ReadFile(f, *bytes, (DWORD)*len, &got, NULL) || got != (DWORD)*len) {
        free(*bytes);
        *bytes = NULL;
        CloseHandle(f);
        return 0;
    }
    CloseHandle(f);
    return 1;
}

static int find_p2lrt(wchar_t *out) {
    wchar_t pattern[MAX_PATH];
    WIN32_FIND_DATAW fd;
    HANDLE h;
    path_join(pattern, exe_dir(), L"RuoMengTu.p2lrt");
    if (GetFileAttributesW(pattern) != INVALID_FILE_ATTRIBUTES) {
        lstrcpyW(out, pattern);
        return 1;
    }
    path_join(pattern, exe_dir(), L"*.p2lrt");
    h = FindFirstFileW(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE)
        return 0;
    path_join(out, exe_dir(), fd.cFileName);
    FindClose(h);
    return 1;
}

static int load_runtime(void) {
    wchar_t dll_path[MAX_PATH], model_path[MAX_PATH];
    uint8_t *bytes = NULL;
    size_t len = 0;
    char err[256] = {0};
    uint32_t abi;
    float cw = 0, ch = 0;
    int idle;
    path_join(dll_path, exe_dir(), L"p2l_runtime.dll");
    g_dll = LoadLibraryW(dll_path);
    if (!g_dll) {
        MessageBoxW(NULL, L"p2l_runtime.dll not found next to L2dHost.exe", L"L2dHost", MB_ICONERROR);
        return 0;
    }
    p2l_abi_version = (fn_u32_void)must_sym("p2l_abi_version");
    p2l_version = (fn_cstr_void)must_sym("p2l_version");
    p2l_rig_load = (fn_load)must_sym("p2l_rig_load");
    p2l_rig_free = (fn_rig)must_sym("p2l_rig_free");
    p2l_physics_stabilize = (fn_rig)must_sym("p2l_physics_stabilize");
    p2l_update = (fn_update)must_sym("p2l_update");
    p2l_canvas = (fn_canvas)must_sym("p2l_canvas");
    p2l_clip_count = (fn_count)must_sym("p2l_clip_count");
    p2l_clip_id = (fn_clip_str)must_sym("p2l_clip_id");
    p2l_clip_name = (fn_clip_str)must_sym("p2l_clip_name");
    p2l_clip_group = (fn_clip_str)must_sym("p2l_clip_group");
    p2l_play = (fn_play)must_sym("p2l_play");
    p2l_expression_count = (fn_count)must_sym("p2l_expression_count");
    p2l_expression_id = (fn_clip_str)must_sym("p2l_expression_id");
    p2l_expression_name = (fn_clip_str)must_sym("p2l_expression_name");
    p2l_expression = (fn_expr)must_sym("p2l_expression");
    p2l_look_at = (fn_look)must_sym("p2l_look_at");
    p2l_lip_sync = (fn_lip)must_sym("p2l_lip_sync");
    p2l_behaviors = (fn_behaviors)must_sym("p2l_behaviors");
    p2l_behavior_strength = (fn_strength)GetProcAddress(g_dll, "p2l_behavior_strength");
    p2l_render = (fn_render)must_sym("p2l_render");
    p2l_hit_test = (fn_hit)must_sym("p2l_hit_test");
    p2l_hit_area_id = (fn_clip_str)GetProcAddress(g_dll, "p2l_hit_area_id");
    p2l_hit_area_name = (fn_clip_str)GetProcAddress(g_dll, "p2l_hit_area_name");
    p2l_clip_finished = (fn_clip_done)GetProcAddress(g_dll, "p2l_clip_finished");
    abi = p2l_abi_version();
    if ((abi >> 16) != 1 || (abi & 0xffffu) < 3) {
        MessageBoxA(NULL, "p2l_runtime.dll ABI too old (need 1.3+)", "L2dHost", MB_ICONERROR);
        return 0;
    }
    if (!find_p2lrt(model_path) || !read_file(model_path, &bytes, &len)) {
        MessageBoxW(NULL, L"No .p2lrt model next to L2dHost.exe", L"L2dHost", MB_ICONERROR);
        return 0;
    }
    g_rig = p2l_rig_load(bytes, len, err, sizeof err);
    free(bytes);
    if (!g_rig) {
        MessageBoxA(NULL, err[0] ? err : "failed to load .p2lrt", "L2dHost", MB_ICONERROR);
        return 0;
    }
    p2l_behaviors(g_rig, 1u | 2u | 4u | 8u);
    if (p2l_behavior_strength)
        p2l_behavior_strength(g_rig, 1.f, 1.f, 1.6f);
    p2l_physics_stabilize(g_rig);
    tips_init();
    idle = find_clip("Idle");
    if (idle >= 0)
        p2l_play(g_rig, idle);
    p2l_canvas(g_rig, &cw, &ch);
    if (cw < 1)
        cw = 1024;
    if (ch < 1)
        ch = 1024;
    {
        float scale = SCALE * (float)g_dpi / 96.f;
        g_pad_top = dip(56);
        if (g_pad_top < 40)
            g_pad_top = 40;
        g_mw = (int)(cw * scale + 0.5f);
        g_mh = (int)(ch * scale + 0.5f);
    }
    if (g_mw < 64)
        g_mw = 64;
    if (g_mh < 64)
        g_mh = 64;
    g_vw = g_mw;
    g_vh = g_mh + g_pad_top;
    g_rgba = (uint8_t *)calloc((size_t)g_mw * g_mh, 4);
    g_bgra = (uint8_t *)calloc((size_t)g_vw * g_vh, 4);
    return g_rgba && g_bgra;
}

static void rgba_to_bgra_premul(void) {
    int x, y;
    memset(g_bgra, 0, (size_t)g_vw * g_vh * 4);
    for (y = 0; y < g_mh; y++) {
        for (x = 0; x < g_mw; x++) {
            size_t s = ((size_t)y * (size_t)g_mw + (size_t)x) * 4;
            size_t d = ((size_t)(y + g_pad_top) * (size_t)g_vw + (size_t)x) * 4;
            uint8_t r = g_rgba[s + 0];
            uint8_t g = g_rgba[s + 1];
            uint8_t b = g_rgba[s + 2];
            uint8_t a = g_rgba[s + 3];
            g_bgra[d + 0] = b;
            g_bgra[d + 1] = g;
            g_bgra[d + 2] = r;
            g_bgra[d + 3] = a;
        }
    }
}

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    int x = (int)(short)LOWORD(lp);
    int y = (int)(short)HIWORD(lp);
    if (msg == WM_NCHITTEST) {
        POINT pt;
        pt.x = x;
        pt.y = y;
        ScreenToClient(hwnd, &pt);
        if (g_drag)
            return HTCLIENT;
        if (say_hit(pt.x, pt.y))
            return HTCLIENT;
        if (pixel_alpha(pt.x, pt.y) < HIT_ALPHA)
            return HTTRANSPARENT;
        return HTCLIENT;
    }
    if (msg == WM_LBUTTONDOWN) {
        POINT pt;
        RECT rc;
        g_press_x = x;
        g_press_y = y;
        g_drag = 0;
        g_say_press = say_hit(x, y);
        g_model_press = !g_say_press;
        SetCapture(hwnd);
        GetCursorPos(&pt);
        GetWindowRect(hwnd, &rc);
        g_dx = pt.x - rc.left;
        g_dy = pt.y - rc.top;
        return 0;
    }
    if (msg == WM_MOUSEMOVE) {
        if (!g_drag && (g_say_press || g_model_press)) {
            int dx = x - g_press_x, dy = y - g_press_y;
            if (dx * dx + dy * dy > 64) {
                POINT pt;
                RECT rc;
                g_drag = 1;
                GetCursorPos(&pt);
                GetWindowRect(hwnd, &rc);
                g_dx = pt.x - rc.left;
                g_dy = pt.y - rc.top;
            }
        }
        if (g_drag) {
            POINT pt;
            GetCursorPos(&pt);
            SetWindowPos(hwnd, NULL, pt.x - g_dx, pt.y - g_dy, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            return 0;
        }
        g_say_hover = say_hit(x, y);
        if (g_say_n > 0) {
            TRACKMOUSEEVENT tme;
            tme.cbSize = sizeof tme;
            tme.dwFlags = TME_LEAVE;
            tme.hwndTrack = hwnd;
            tme.dwHoverTime = 0;
            TrackMouseEvent(&tme);
        }
        return 0;
    }
    if (msg == WM_MOUSELEAVE) {
        g_say_hover = 0;
        if (g_say_n > 0)
            say_arm();
        return 0;
    }
    if (msg == WM_LBUTTONUP) {
        int dragged = g_drag;
        if (!g_drag) {
            if (g_say_press && say_hit(x, y))
                say_clear();
            else if (g_model_press)
                on_model_click(x, y);
        }
        g_say_press = 0;
        g_model_press = 0;
        g_drag = 0;
        ReleaseCapture();
        if (dragged)
            save_pos(hwnd);
        return 0;
    }
    if (msg == WM_RBUTTONUP) {
        if (say_hit(x, y))
            say_clear();
        return 0;
    }
    if (msg == WM_DESTROY) {
        save_pos(hwnd);
        g_quit = 1;
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmd, int show) {
    WNDCLASSW wc;
    RECT work;
    HWND hwnd;
    HDC screen, mem;
    BITMAPINFO bmi;
    void *bits = NULL;
    HBITMAP hbmp, old;
    BLENDFUNCTION blend;
    SIZE size;
    POINT src_pt, dst;
    MSG msg;
    LARGE_INTEGER freq, last, now;
    float xf[6];
    (void)prev;
    (void)show;
    enable_dpi();
    g_parent_pid = parse_parent_pid(cmd);
    if (handoff_existing(g_parent_pid))
        return 0;
    InitializeCriticalSection(&g_lock);
    {
        RECT wr;
        int wx, wy;
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &wr, 0);
        wx = wr.right - 240;
        wy = wr.bottom - 240;
        load_pos(&wx, &wy);
        g_dpi = monitor_dpi_at(wx, wy);
    }
    if (!load_runtime())
        return 1;
    CreateThread(NULL, 0, parent_thread, NULL, 0, NULL);
    CreateThread(NULL, 0, pipe_thread, NULL, 0, NULL);

    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc = wndproc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.lpszClassName = L"RMT_L2dHost";
    RegisterClassW(&wc);
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    {
        int wx = work.right - g_vw - 24, wy = work.bottom - g_vh - 24;
        if (load_pos(&wx, &wy))
            clamp_pos(&wx, &wy);
        hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, wc.lpszClassName,
                               L"RMT L2D Host", WS_POPUP, wx, wy, g_vw, g_vh, NULL, NULL, inst, NULL);
    }
    g_hwnd = hwnd;
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);

    screen = GetDC(NULL);
    mem = CreateCompatibleDC(screen);
    memset(&bmi, 0, sizeof bmi);
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = g_vw;
    bmi.bmiHeader.biHeight = -g_vh;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    hbmp = CreateDIBSection(mem, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    old = (HBITMAP)SelectObject(mem, hbmp);
    blend.BlendOp = AC_SRC_OVER;
    blend.BlendFlags = 0;
    blend.SourceConstantAlpha = 255;
    blend.AlphaFormat = AC_SRC_ALPHA;
    size.cx = g_vw;
    size.cy = g_vh;
    src_pt.x = src_pt.y = 0;
    {
        float cw = 0, ch = 0;
        p2l_canvas(g_rig, &cw, &ch);
        xf[0] = (float)g_mw / (cw > 1 ? cw : 1024.f);
        xf[1] = 0;
        xf[2] = 0;
        xf[3] = (float)g_mh / (ch > 1 ? ch : 1024.f);
        xf[4] = 0;
        xf[5] = 0;
    }
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&last);

    while (!g_quit) {
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                g_quit = 1;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        QueryPerformanceCounter(&now);
        if ((now.QuadPart - last.QuadPart) * 30 >= freq.QuadPart) {
            float dt = (float)(now.QuadPart - last.QuadPart) / (float)freq.QuadPart;
            RECT rc;
            last = now;
            if (dt > 0.1f)
                dt = 0.1f;
            drain_cmds();
            tick_fullscreen(hwnd);
            if (g_fs_hide) {
                Sleep(50);
                continue;
            }
            follow_mouse(hwnd);
            p2l_update(g_rig, dt);
            memset(g_rgba, 0, (size_t)g_mw * g_mh * 4);
            p2l_render(g_rig, g_rgba, (uint32_t)g_mw, (uint32_t)g_mh, xf, 0);
            rgba_to_bgra_premul();
            draw_balloon();
            tick_idle();
            if (bits)
                memcpy(bits, g_bgra, (size_t)g_vw * g_vh * 4);
            GetWindowRect(hwnd, &rc);
            dst.x = rc.left;
            dst.y = rc.top;
            UpdateLayeredWindow(hwnd, screen, &dst, &size, mem, &src_pt, 0, &blend, ULW_ALPHA);
        } else {
            Sleep(8);
        }
    }

    SelectObject(mem, old);
    DeleteObject(hbmp);
    DeleteDC(mem);
    ReleaseDC(NULL, screen);
    if (g_rig)
        p2l_rig_free(g_rig);
    if (g_dll)
        FreeLibrary(g_dll);
    free(g_rgba);
    free(g_bgra);
    DeleteCriticalSection(&g_lock);
    return 0;
}
