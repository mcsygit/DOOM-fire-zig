// TEST YOUR (TTY) MIGHT: DOOM FIRE!
// (c) 2022, 2023, 2024, 2025  const void*
// Updated for Zig 0.17
//
// Please see GPL3 license at bottom of source.

const builtin = @import("builtin");
const std = @import("std");

const allocator = std.heap.page_allocator;

var g_tty_win: ?std.os.windows.HANDLE = null;

var rand_prng: std.Random.DefaultPrng = undefined;
var rand: std.Random = undefined;

var target_fps: u32 = 0; // 0 = uncapped

pub fn getMilliTimestamp() i64 {
    if (builtin.os.tag == .windows) {
        var count: i64 = 0;
        var freq: i64 = 0;
        _ = win32.QueryPerformanceCounter(&count);
        _ = win32.QueryPerformanceFrequency(&freq);
        if (freq == 0) return 0;
        return @divTrunc(count * 1000, freq);
    } else {
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
        return @as(i64, ts.sec) * 1000 + @divTrunc(ts.nsec, 1_000_000);
    }
}

pub fn sleepMs(ms: u32) void {
    if (builtin.os.tag == .windows) {
        win32.Sleep(ms);
    } else {
        std.Thread.sleep(@as(u64, ms) * 1_000_000);
    }
}

pub fn initRNG() !void {
    const seed: u64 = @bitCast(getMilliTimestamp());
    rand_prng = std.Random.DefaultPrng.init(seed);
    rand = rand_prng.random();
}

// Print string directly to console/terminal
pub fn emit(s: []const u8) !void {
    if (builtin.os.tag == .windows) {
        if (g_tty_win) |h| {
            var sz: win32.DWORD = 0;
            _ = win32.WriteConsoleA(h, s.ptr, @intCast(s.len), &sz, null);
        }
    } else {
        _ = try std.posix.write(std.posix.STDOUT_FILENO, s);
    }
}

// Format a string then print
pub fn emitFmt(comptime s: []const u8, args: anytype) !void {
    const t = try std.fmt.allocPrint(allocator, s, args);
    defer allocator.free(t);
    try emit(t);
}

///////////////////////////////////
// TTY/Terminal Helpers
///////////////////////////////////

const TIOCGWINSZ = std.c.T.IOCGWINSZ;

const TermSz = struct { height: usize, width: usize };
var term_sz: TermSz = .{ .height = 0, .width = 0 };

const esc = "\x1B";
const csi = esc ++ "[";

const line_prior = csi ++ "1F";
const line_next = csi ++ "1E";
const line_start = csi ++ "1G";
const line_clear_to_eol = csi ++ "0K";
const line_new = line_clear_to_eol ++ line_next ++ line_start;
const line_up = line_prior ++ line_start;
const nl = if (builtin.os.tag == .windows) line_new else "\n";

const cursor_save = esc ++ "7";
const cursor_load = esc ++ "8";

const cursor_show = csi ++ "?25h";
const cursor_hide = csi ++ "?25l";
const cursor_home = csi ++ "1;1H";

const screen_reset = csi ++ "!p";
const screen_clear = csi ++ "2J";
const screen_buf_on = csi ++ "?1049h";
const screen_buf_off = csi ++ "?1049l";

const char_set_ascii = esc ++ "(B";
const char_set_ansi = esc ++ "(0";

const color_reset = csi ++ "0m";
const color_fg = "38;5;";
const color_bg = "48;5;";

const color_fg_def = csi ++ color_fg ++ "15m";
const color_bg_def = csi ++ color_bg ++ "0m";
const color_def = color_bg_def ++ color_fg_def;
const color_italic = csi ++ "3m";
const color_not_italic = csi ++ "23m";

const term_on = screen_buf_on ++ cursor_hide ++ cursor_home ++ color_def ++ screen_clear;
const term_off = screen_buf_off ++ cursor_show ++ nl;

const sep = if (builtin.os.tag == .windows) "|" else "▏";

const MAX_COLOR = 256;
const LAST_COLOR = MAX_COLOR - 1;

var fg: [MAX_COLOR][]u8 = undefined;
var bg: [MAX_COLOR][]u8 = undefined;

pub fn initColor() !void {
    var color_idx: u32 = 0;
    while (color_idx < MAX_COLOR) : (color_idx += 1) {
        fg[color_idx] = try std.fmt.allocPrint(allocator, "{s}38;5;{d}m", .{ csi, color_idx });
        bg[color_idx] = try std.fmt.allocPrint(allocator, "{s}48;5;{d}m", .{ csi, color_idx });
    }
}

pub fn getTermSzWin() !TermSz {
    var info: win32.CONSOLE_SCREEN_BUFFER_INFO = std.mem.zeroes(win32.CONSOLE_SCREEN_BUFFER_INFO);

    if (g_tty_win) |h| {
        if (0 == win32.GetConsoleScreenBufferInfo(h, &info)) {
            return error.Unexpected;
        }
        return TermSz{
            .height = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
            .width = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
        };
    }
    return TermSz{ .height = 24, .width = 80 };
}

pub fn getTermSzLinux() !TermSz {
    var winsz = std.c.winsize{ .col = 0, .row = 0, .xpixel = 0, .ypixel = 0 };
    const rv = std.c.ioctl(std.posix.STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&winsz));
    if (rv >= 0 and winsz.row > 0 and winsz.col > 0) {
        return TermSz{ .height = winsz.row, .width = winsz.col };
    }

    const tty_file = std.fs.cwd().openFile("/dev/tty", .{}) catch return TermSz{ .height = 24, .width = 80 };
    defer tty_file.close();

    const tty_rv = std.c.ioctl(tty_file.handle, TIOCGWINSZ, @intFromPtr(&winsz));
    if (tty_rv >= 0 and winsz.row > 0 and winsz.col > 0) {
        return TermSz{ .height = winsz.row, .width = winsz.col };
    }
    return TermSz{ .height = 24, .width = 80 };
}

pub fn getTermSz() !TermSz {
    return if (builtin.os.tag == .windows) try getTermSzWin() else try getTermSzLinux();
}

pub fn initTermSize() !void {
    term_sz = try getTermSz();
}

pub fn initTermWin() !void {
    g_tty_win = win32.GetStdHandle(win32.STD_OUTPUT_HANDLE);
    if (g_tty_win == std.os.windows.INVALID_HANDLE_VALUE or g_tty_win == null) {
        return error.Unexpected;
    }

    var consoleMode: win32.DWORD = 0;
    if (0 == win32.GetConsoleMode(g_tty_win.?, &consoleMode)) {
        return error.Unexpected;
    }

    consoleMode |= win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING | win32.DISABLE_NEWLINE_AUTO_RETURN;

    if (0 == win32.SetConsoleMode(g_tty_win.?, consoleMode)) {
        return error.Unexpected;
    }

    _ = win32.SetConsoleOutputCP(win32.CP_UTF8);
}

pub fn initTerm() !void {
    try initColor();

    if (builtin.os.tag == .windows) {
        try initTermWin();
    }

    try initTermSize();
    try initRNG();

    try emit(term_on);
    if (builtin.os.tag == .windows) {
        try emit(char_set_ascii);
    }
}

pub fn complete() !void {
    try emit(term_off);
    try emit("Complete!" ++ nl);
}

/////////////////
// doom-fire
/////////////////

pub fn pause() !void {
    try emit(color_reset);
    try emit("Press return to continue...");

    var b: [1]u8 = undefined;
    if (builtin.os.tag == .windows) {
        const stdin_h = win32.GetStdHandle(win32.STD_INPUT_HANDLE);
        var read_chars: win32.DWORD = 0;
        _ = win32.ReadConsoleA(stdin_h.?, &b, 1, &read_chars, null);
    } else {
        _ = std.posix.read(std.posix.STDIN_FILENO, &b) catch 0;
    }

    if (b[0] == 'q') {
        try complete();
        std.process.exit(0);
    }
}

pub fn checkTermSz() !void {
    const min_w = 120;
    const min_h = 22;
    var w_ok = true;
    var h_ok = true;

    if (term_sz.width < min_w) {
        w_ok = false;
    }
    if (term_sz.height < min_h) {
        h_ok = false;
    }

    if (w_ok and h_ok) {
        return;
    } else {
        try emit(fg[9]);

        if (w_ok and !h_ok) {
            try emitFmt("Screen may be too short - height is {d} and need {d}.", .{ term_sz.height, min_h });
        } else if (!w_ok and h_ok) {
            try emitFmt("Screen may be too narrow - width is {d} and need {d}.", .{ term_sz.width, min_w });
        } else {
            try emitFmt("Screen is too small - have {d} x {d} and need {d} x {d}", .{ term_sz.width, term_sz.height, min_w, min_h });
        }

        try emit(nl);
        try emit(nl);

        try emit(bg[1]);
        try emit(fg[15]);
        try emit("There may be rendering issues on the next screen; to correct, <q><enter>, resize and try again.");
        try emit(line_clear_to_eol);
        try emit(color_reset);
        try emit(nl ++ nl ++ "Continue?" ++ nl ++ nl);

        try pause();

        try emit(color_reset);
        try emit(cursor_home);
        try emit(screen_clear);
    }
}

pub fn showTermSz() !void {
    try emit(color_def);
    try emitFmt("Screen size: {d}w x {d}h", .{ term_sz.width, term_sz.height });
    try emit(nl);
    try emit(nl);
}

pub fn showLabel(label: []const u8) !void {
    try emit(color_def);
    try emitFmt("{s}{s}:", .{ color_def, label });
    try emit(nl);
}

pub fn showStdColors() !void {
    try showLabel("Standard colors");

    try emit(fg[15]);
    var color_idx: u8 = 0;
    while (color_idx < 8) : (color_idx += 1) {
        try emit(bg[color_idx]);
        if (color_idx == 7) {
            try emit(fg[0]);
        }
        try emitFmt("{s} {d:2}  ", .{ sep, color_idx });
    }
    try emit(color_def);
    try emit(nl);

    try emit(fg[15]);
    while (color_idx < 16) : (color_idx += 1) {
        try emit(bg[color_idx]);
        if (color_idx == 15) {
            try emit(fg[0]);
        }
        try emitFmt("{s} {d:2}  ", .{ sep, color_idx });
    }
    try emit(color_def);
    try emit(nl);
    try emit(nl);
}

pub fn show216Colors() !void {
    try showLabel("216 colors");

    var color_addendum: u8 = 0;
    var bg_idx: u8 = 0;
    var fg_idx: u8 = 0;

    var color_shift: u8 = 0;
    while (color_shift < 6) : (color_shift += 1) {
        color_addendum = color_shift * 36 + 16;

        var color_idx: u8 = 0;
        while (color_idx < 36) : (color_idx += 1) {
            bg_idx = color_idx + color_addendum;

            if (color_idx > 17) {
                fg_idx = 0;
            } else {
                fg_idx = 15;
            }

            try emit(bg[bg_idx]);
            try emit(fg[fg_idx]);
            try emitFmt("{d:3}", .{bg_idx});
        }
        try emit(color_def);
        try emit(nl);
    }
    try emit(color_def);
    try emit(nl);
}

pub fn showGrayscale() !void {
    try showLabel("Grayscale");

    var fg_idx: u8 = 15;
    try emit(fg[fg_idx]);

    var bg_idx: u32 = 232;
    while (bg_idx < 256) : (bg_idx += 1) {
        if (bg_idx > 243) {
            fg_idx = 0;
            try emit(fg[fg_idx]);
        }

        try emit(bg[bg_idx]);
        try emitFmt("{s}{d} ", .{ sep, bg_idx });
    }
    try emit(color_def);
    try emit(nl);
    try emit(color_def);
    try emit(nl);
}

pub fn scrollMarquee() !void {
    const bg_idx: u8 = 222;
    const marquee_row = if (builtin.os.tag == .windows) nl else line_clear_to_eol ++ nl;
    const marquee_bg = marquee_row ++ marquee_row ++ marquee_row ++ marquee_row;

    try emit(cursor_save);
    try emit(bg[bg_idx]);
    try emit(marquee_bg);

    const txt = [_][]const u8{
        "  Things move along so rapidly nowadays that people saying " ++ color_italic ++ "It can't be done" ++ color_not_italic ++ " are always being interrupted",
        "  by somebody doing it.                                                                                                " ++ color_italic ++ "-- Puck, 1902" ++ color_not_italic,
        "  Test your might!",
        "  " ++ color_italic ++ "-- Mortal Kombat" ++ color_not_italic,
        "  How much is the fish?",
        "             " ++ color_italic ++ "-- Scooter" ++ color_not_italic,
    };
    const txt_len: u8 = txt.len / 2;

    const fade_seq = [_]u8{ 222, 221, 220, 215, 214, 184, 178, 130, 235, 58, 16 };
    const fade_len: u8 = fade_seq.len;

    var fade_idx: u8 = 0;
    var txt_idx: u8 = 0;

    while (txt_idx < txt_len) : (txt_idx += 1) {
        fade_idx = 0;
        while (fade_idx < fade_len) : (fade_idx += 1) {
            try emit(cursor_load);
            try emit(bg[bg_idx]);
            try emit(nl);

            try emit(fg[fade_seq[fade_idx]]);
            try emit(txt[txt_idx * 2]);
            try emit(line_clear_to_eol);
            try emit(nl);
            try emit(txt[txt_idx * 2 + 1]);
            try emit(line_clear_to_eol);
            try emit(nl);

            sleepMs(10);
        }

        sleepMs(1000);

        fade_idx = fade_len - 1;
        while (fade_idx > 0) : (fade_idx -= 1) {
            try emit(cursor_load);
            try emit(bg[bg_idx]);
            try emit(nl);

            try emit(fg[fade_seq[fade_idx]]);
            try emit(txt[txt_idx * 2]);
            try emit(line_clear_to_eol);
            try emit(nl);
            try emit(txt[txt_idx * 2 + 1]);
            try emit(line_clear_to_eol);
            try emit(nl);
            sleepMs(10);
        }
        try emit(nl);
    }
}

pub fn showTermCap() !void {
    try showTermSz();
    try showStdColors();
    try show216Colors();
    try showGrayscale();
    try scrollMarquee();

    try pause();
}

const px = "▀";

var bs: []u8 = undefined;
var bs_idx: u64 = 0;
var bs_len: u64 = 0;
var bs_sz_min: u64 = 0;
var bs_sz_max: u64 = 0;
var bs_sz_avg: u64 = 0;
var bs_frame_tic: u64 = 0;
var t_start: i64 = 0;
var t_now: i64 = 0;
var t_dur: f64 = 0.0;
var fps: f64 = 0.0;

pub fn initBuf() !void {
    const px_char_sz = px.len;
    const px_color_sz = bg[LAST_COLOR].len + fg[LAST_COLOR].len;
    const px_sz = px_color_sz + px_char_sz;
    const screen_sz: u64 = @as(u64, px_sz * term_sz.width * term_sz.width);
    const overflow_sz: u64 = px_char_sz * 100;
    const bs_sz: u64 = screen_sz + overflow_sz;

    bs = try allocator.alloc(u8, bs_sz * 2);
    t_start = getMilliTimestamp();
    resetBuf();
}

pub fn resetBuf() void {
    bs_idx = 0;
    bs_len = 0;
}

pub fn drawBuf(s: []const u8) void {
    for (s) |b| {
        bs[bs_idx] = b;
        bs_idx += 1;
        bs_len += 1;
    }
}

pub fn paintBuf() !void {
    if (bs_len > 1) {
        try emit(bs[0 .. bs_len - 1]);
    }
    t_now = getMilliTimestamp();
    bs_frame_tic += 1;
    if (bs_sz_min == 0) {
        bs_sz_min = bs_len;
        bs_sz_max = bs_len;
        bs_sz_avg = bs_len;
    } else {
        if (bs_len < bs_sz_min) {
            bs_sz_min = bs_len;
        }
        if (bs_len > bs_sz_max) {
            bs_sz_max = bs_len;
        }
        bs_sz_avg = bs_sz_avg * (bs_frame_tic - 1) / bs_frame_tic + bs_len / bs_frame_tic;
    }

    t_dur = @as(f64, @floatFromInt(t_now - t_start)) / 1000.0;
    if (t_dur > 0) {
        fps = @as(f64, @floatFromInt(bs_frame_tic)) / t_dur;
    }

    try emit(fg[0]);
    try emitFmt("mem: {Bi:.2} min / {Bi:.2} avg / {Bi:.2} max [ {d:.2} fps ]", .{
        bs_sz_min,
        bs_sz_avg,
        bs_sz_max,
        fps,
    });
}

pub fn freeBuf() void {
    allocator.free(bs);
}

pub fn showDoomFire() !void {
    const FIRE_H: u64 = @as(u64, @intCast(term_sz.height)) * 2;
    const FIRE_W: u64 = @as(u64, @intCast(term_sz.width));
    const FIRE_SZ: u64 = FIRE_H * FIRE_W;
    const FIRE_LAST_ROW: u64 = (FIRE_H - 1) * FIRE_W;

    const fire_palette = [_]u8{ 0, 233, 234, 52, 53, 88, 89, 94, 95, 96, 130, 131, 132, 133, 172, 214, 215, 220, 220, 221, 3, 226, 227, 230, 195, 230 };
    const fire_black: u8 = 0;
    const fire_white: u8 = fire_palette.len - 1;

    var screen_buf: []u8 = try allocator.alloc(u8, FIRE_SZ);
    defer allocator.free(screen_buf);

    var buf_idx: u64 = 0;
    while (buf_idx < FIRE_SZ) : (buf_idx += 1) {
        screen_buf[buf_idx] = fire_black;
    }

    buf_idx = 0;
    while (buf_idx < FIRE_W) : (buf_idx += 1) {
        screen_buf[FIRE_LAST_ROW + buf_idx] = fire_white;
    }

    try emit(cursor_home);
    try emit(color_reset);
    try emit(color_def);
    try emit(screen_clear);

    var doFire_x: u64 = 0;
    var doFire_y: u64 = 0;
    var doFire_idx: u64 = 0;

    var spread_px: u8 = 0;
    var spread_rnd_idx: u8 = 0;
    var spread_dst: u64 = 0;

    const init_frame = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ cursor_home, bg[0], fg[0] });
    defer allocator.free(init_frame);

    var frame_x: u64 = 0;
    var frame_y: u64 = 0;
    var px_hi: u8 = fire_black;
    var px_lo: u8 = fire_black;
    var px_prev_hi = px_hi;
    var px_prev_lo = px_lo;

    try initBuf();
    defer freeBuf();

    if (builtin.os.tag == .windows) {
        _ = win32.timeBeginPeriod(1);
    }
    defer if (builtin.os.tag == .windows) {
        _ = win32.timeEndPeriod(1);
    };

    const target_frame_ms: i64 = if (target_fps > 0) @divTrunc(1000, @as(i64, target_fps)) else 0;

    while (true) {
        const frame_start = getMilliTimestamp();

        doFire_x = 0;
        while (doFire_x < FIRE_W) : (doFire_x += 1) {
            doFire_y = 0;
            while (doFire_y < FIRE_H) : (doFire_y += 1) {
                doFire_idx = doFire_y * FIRE_W + doFire_x;

                spread_px = screen_buf[doFire_idx];

                if ((spread_px == 0) and (doFire_idx >= FIRE_W)) {
                    screen_buf[doFire_idx - FIRE_W] = 0;
                } else {
                    spread_rnd_idx = rand.intRangeAtMost(u8, 0, 3);
                    if (doFire_idx >= (spread_rnd_idx + 1)) {
                        spread_dst = doFire_idx - spread_rnd_idx + 1;
                    } else {
                        spread_dst = doFire_idx;
                    }
                    if (spread_dst >= FIRE_W) {
                        if (spread_px > (spread_rnd_idx & 1)) {
                            screen_buf[spread_dst - FIRE_W] = spread_px - (spread_rnd_idx & 1);
                        } else {
                            screen_buf[spread_dst - FIRE_W] = 0;
                        }
                    }
                }
            }
        }

        resetBuf();
        drawBuf(init_frame);

        frame_y = 0;
        while (frame_y < FIRE_H) : (frame_y += 2) {
            frame_x = 0;
            while (frame_x < FIRE_W) : (frame_x += 1) {
                px_hi = screen_buf[frame_y * FIRE_W + frame_x];
                px_lo = screen_buf[(frame_y + 1) * FIRE_W + frame_x];

                if (px_lo != px_prev_lo) {
                    drawBuf(bg[fire_palette[px_lo]]);
                }
                if (px_hi != px_prev_hi) {
                    drawBuf(fg[fire_palette[px_hi]]);
                }
                drawBuf(px);

                px_prev_hi = px_hi;
                px_prev_lo = px_lo;
            }
            drawBuf(nl);
        }
        try paintBuf();
        resetBuf();

        if (target_frame_ms > 0) {
            const elapsed = getMilliTimestamp() - frame_start;
            if (elapsed < target_frame_ms) {
                sleepMs(@intCast(target_frame_ms - elapsed));
            }
        }
    }
}

fn parseTargetFps() u32 {
    if (builtin.os.tag == .windows) {
        const cmd_raw = win32.GetCommandLineA();
        const cmd = std.mem.sliceTo(cmd_raw, 0);

        var iter = std.mem.tokenizeScalar(u8, cmd, ' ');
        _ = iter.next();

        while (iter.next()) |token| {
            if (std.mem.eql(u8, token, "--")) continue;
            return std.fmt.parseInt(u32, token, 10) catch 0;
        }
        return 0;
    }
    return 0;
}

pub fn main() anyerror!void {
    target_fps = parseTargetFps();

    try initTerm();
    defer complete() catch {};

    try checkTermSz();
    try showTermCap();
    try showDoomFire();
}

const win32 = struct {
    pub const WORD = u16;
    pub const BOOL = c_int;
    pub const HANDLE = *anyopaque;
    pub const SHORT = i16;
    pub const DWORD = u32;
    pub const UINT = u32;

    pub const ENABLE_PROCESSED_OUTPUT: DWORD = 0x0001;
    pub const ENABLE_WRAP_AT_EOL_OUTPUT: DWORD = 0x0002;
    pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
    pub const DISABLE_NEWLINE_AUTO_RETURN: DWORD = 0x0008;
    pub const ENABLE_LVB_GRID_WORLDWIDE: DWORD = 0x0010;

    pub const CP_UTF8: UINT = 65001;
    pub const CP_ANSI: UINT = 1252;

    pub const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
    pub const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
    pub const STD_ERR_HANDLE: DWORD = @bitCast(@as(i32, -12));

    pub const COORD = extern struct {
        X: SHORT,
        Y: SHORT,
    };

    pub const SMALL_RECT = extern struct {
        Left: SHORT,
        Top: SHORT,
        Right: SHORT,
        Bottom: SHORT,
    };

    pub const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: COORD,
        dwCursorPosition: COORD,
        wAttributes: WORD,
        srWindow: SMALL_RECT,
        dwMaximumWindowSize: COORD,
    };

    pub extern "kernel32" fn GetConsoleScreenBufferInfo(
        hConsoleOutput: HANDLE,
        lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO,
    ) callconv(.c) BOOL;

    pub extern "kernel32" fn GetConsoleMode(hConsoleOutput: HANDLE, lpOutMode: *DWORD) callconv(.c) BOOL;
    pub extern "kernel32" fn SetConsoleMode(in_hConsoleHandle: HANDLE, in_Mode: DWORD) callconv(.c) BOOL;
    pub extern "kernel32" fn SetConsoleOutputCP(in_wCodePageID: UINT) callconv(.c) BOOL;

    pub extern "kernel32" fn WriteConsoleA(
        in_hConsoleOutput: HANDLE,
        in_lpBuffer: [*]const u8,
        in_nNumberOfCharsToWrite: DWORD,
        out_lpNumberOfCharsWritten: ?*DWORD,
        lpReserved: ?*anyopaque,
    ) callconv(.c) BOOL;

    pub extern "kernel32" fn ReadConsoleA(
        in_hConsoleInput: HANDLE,
        out_lpBuffer: [*]u8,
        in_nNumberOfCharsToRead: DWORD,
        out_lpNumberOfCharsRead: ?*DWORD,
        pInputControl: ?*anyopaque,
    ) callconv(.c) BOOL;

    pub extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.c) ?HANDLE;
    pub extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.c) BOOL;
    pub extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.c) BOOL;
    pub extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(.c) void;
    pub extern "kernel32" fn GetCommandLineA() callconv(.c) [*:0]const u8;
    pub extern "winmm" fn timeBeginPeriod(uPeriod: UINT) callconv(.c) UINT;
    pub extern "winmm" fn timeEndPeriod(uPeriod: UINT) callconv(.c) UINT;
};
