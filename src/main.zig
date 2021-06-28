const std = @import("std");
const os = std.os;
const mem = std.mem;
const windows = std.os.windows;
const user32 = std.os.windows.user32;

const WINAPI = @import("std").os.windows.WINAPI;
usingnamespace @import("win32").zig;
usingnamespace @import("win32").foundation;
usingnamespace @import("win32").system.system_services;
usingnamespace @import("win32").ui.windows_and_messaging;
usingnamespace @import("win32").graphics.gdi;

var running: bool = true;
var bitmap_memory: *c_void = undefined;
var bitmap_info = mem.zeroes(BITMAPINFO);
var bitmap_handle: ?HBITMAP = null;
var device_context: HDC = undefined;

fn resizeDibSection(width: i32, height: i32) void {
    _ = width;
    _ = height;

    if (bitmap_handle) |handle| {
        _ = DeleteObject(handle);
    } else {
        // TODO: check
        device_context = CreateCompatibleDC(null);
    }

    bitmap_info.bmiHeader = .{
        .biSize = @sizeOf(@TypeOf(bitmap_info.bmiHeader)),
        .biWidth = width,
        .biHeight = height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = BI_RGB,
        .biSizeImage = 0,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    };

    bitmap_handle = CreateDIBSection(
        device_context,
        &bitmap_info,
        DIB_RGB_COLORS,
        &bitmap_memory,
        null,
        0,
    );
}

fn updateWindow(ctx: HDC, x: i32, y: i32, width: i32, height: i32) void {
    _ = StretchDIBits(
        ctx,
        // dest rect
        x,
        y,
        width,
        height,
        // source rect
        x,
        y,
        width,
        height,
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

            updateWindow(ctx, x, y, width, height);
            _ = ctx;
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

    while (running) if (GetMessageA(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageA(&msg);
    } else break;

    return 0;
}
