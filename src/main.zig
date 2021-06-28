const std = @import("std");
const os = std.os;
const mem = std.mem;
const windows = std.os.windows;
const user32 = std.os.windows.user32;

const WINAPI = @import("std").os.windows.WINAPI;
usingnamespace @import("win32").zig;
usingnamespace @import("win32").foundation;
usingnamespace @import("win32").system.system_services;
usingnamespace @import("win32").system.memory;
usingnamespace @import("win32").ui.windows_and_messaging;
usingnamespace @import("win32").graphics.gdi;

var running: bool = true;
var bitmap_memory: ?[*]u8 = null;
var bitmap_info = mem.zeroes(BITMAPINFO);
var bitmap_handle: ?HBITMAP = null;
var device_context: HDC = undefined;
var bitmap_width: i32 = undefined;
var bitmap_height: i32 = undefined;

fn renderOddGradient(x_offset: u32, y_offset: u32) void {
    _ = x_offset;
    _ = y_offset;
    const pitch = @intCast(u32, bitmap_width) * 4;
    var y: u32 = 0;
    var row = bitmap_memory.?;
    while (y < bitmap_height) : (y += 1) {
        var x: u32 = 0;
        var pixel = @ptrCast([*]u32, @alignCast(4, row));
        while (x < bitmap_width) : (x += 1) {
            pixel.* = (x +% x_offset) | ((y +% y_offset) << 8);
            pixel += 1;
        }
        row += pitch;
    }
}

fn resizeDibSection(width: i32, height: i32) void {
    if (bitmap_memory) |memory| {
        _ = VirtualFree(@ptrCast(*c_void, memory), 0, MEM_RELEASE);
    }

    bitmap_height = height;
    bitmap_width = width;

    bitmap_info.bmiHeader = .{
        .biSize = @sizeOf(@TypeOf(bitmap_info.bmiHeader)),
        .biWidth = width,
        .biHeight = -height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = BI_RGB,
        .biSizeImage = 0,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    };

    const size = @intCast(usize, bitmap_width) * @intCast(usize, bitmap_height) * 4;
    bitmap_memory = @ptrCast([*]u8, VirtualAlloc(null, size, MEM_COMMIT, PAGE_READWRITE));

    // TODO: clear
}

fn updateWindow(ctx: HDC, rect: RECT, x: i32, y: i32, width: i32, height: i32) void {
    _ = x; // TODO: use
    _ = y; // TODO: use
    _ = width; // TODO: use
    _ = height; // TODO: use

    const wh = rect.bottom - rect.top;
    const ww = rect.right - rect.left;

    _ = StretchDIBits(
        ctx,
        // dest rect
        0, //x,
        0, //y,
        bitmap_width,
        bitmap_height,
        // source rect
        0, //x,
        0, //y,
        ww,
        wh,
        bitmap_memory,
        &bitmap_info,
        DIB_RGB_COLORS,
        SRCCOPY,
    );
}

fn mainWindowCallback(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.C) LRESULT {
    _ = window;
    _ = wparam;
    _ = lparam;

    var result: LRESULT = 0;

    switch (message) {
        WM_SIZE => {
            var client_rect: RECT = undefined;
            _ = GetClientRect(window, &client_rect);

            const height = client_rect.bottom - client_rect.top;
            const width = client_rect.right - client_rect.left;

            resizeDibSection(width, height);

            std.log.info("size", .{});
        },

        WM_DESTROY => {
            running = false;
            std.log.info("destroy", .{});
        },

        WM_CLOSE => {
            running = false;
            std.log.info("close", .{});
        },

        WM_ACTIVATEAPP => {
            std.log.info("app", .{});
        },

        WM_PAINT => {
            var paint: PAINTSTRUCT = undefined;

            const ctx = BeginPaint(window, &paint);
            defer _ = EndPaint(window, &paint);

            const x = paint.rcPaint.left;
            const y = paint.rcPaint.top;
            const height = paint.rcPaint.bottom - paint.rcPaint.top;
            const width = paint.rcPaint.right - paint.rcPaint.left;

            var client_rect: RECT = undefined;
            _ = GetClientRect(window, &client_rect);

            updateWindow(ctx, client_rect, x, y, width, height);
        },
        else => {
            result = DefWindowProcA(window, message, wparam, lparam);
        },
    }

    return result;
}

pub fn wWinMain(
    instance: HINSTANCE,
    prevInstance: ?HINSTANCE,
    cl: [*:0]const u16,
    show: c_int,
) callconv(WINAPI) c_int {
    _ = prevInstance;
    _ = cl;
    _ = show;

    var wnd = mem.zeroes(WNDCLASSEXA);
    wnd.cbSize = @sizeOf(WNDCLASSEXA);
    wnd.hInstance = instance;
    wnd.lpszClassName = "HandClass";
    wnd.lpfnWndProc = mainWindowCallback;

    if (RegisterClassExA(&wnd) == 0) @panic("register failed");

    const window: HWND = CreateWindowExA(
        @intToEnum(WINDOW_EX_STYLE, 0),
        wnd.lpszClassName,
        "Hand",
        @intToEnum(WINDOW_STYLE, @enumToInt(WS_OVERLAPPEDWINDOW) | @enumToInt(WS_VISIBLE)),
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        null,
        null,
        instance,
        null,
    ) orelse @panic("window failed");
    _ = window;

    var msg: MSG = undefined;

    var x_offset: u32 = 0;
    var y_offset: u32 = 0;
    while (running) {
        while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == WM_QUIT) running = false;
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }

        renderOddGradient(x_offset, y_offset);
        x_offset += 1;

        const ctx = GetDC(window);
        defer _ = ReleaseDC(window, ctx);

        var client_rect: RECT = undefined;
        _ = GetClientRect(window, &client_rect);

        const height = client_rect.bottom - client_rect.top;
        const width = client_rect.right - client_rect.left;

        updateWindow(ctx, client_rect, 0, 0, width, height);
    }

    return 0;
}
