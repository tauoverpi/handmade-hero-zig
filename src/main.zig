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
var back_buffer: ScreenBuffer = undefined;

const ScreenBuffer = struct {
    memory: ?[*]u8 = null,
    info: BITMAPINFO = mem.zeroes(BITMAPINFO),
    width: i32,
    pitch: u32,
    height: i32,
};

fn windowDimensions(window: HWND) struct { width: i32, height: i32 } {
    var client_rect: RECT = undefined;
    _ = GetClientRect(window, &client_rect);

    const height = client_rect.bottom - client_rect.top;
    const width = client_rect.right - client_rect.left;

    return .{
        .width = width,
        .height = height,
    };
}

fn renderOddGradient(bitmap: ScreenBuffer, x_offset: u32, y_offset: u32) void {
    var y: u32 = 0;
    var row = bitmap.memory.?;
    while (y < bitmap.height) : (y += 1) {
        var x: u32 = 0;
        var pixel = @ptrCast([*]u32, @alignCast(4, row));
        while (x < bitmap.width) : (x += 1) {
            pixel.* = (x +% x_offset) | ((y +% y_offset) << 8);
            pixel += 1;
        }
        row += bitmap.pitch;
    }
}

fn resizeDibSection(bitmap: *ScreenBuffer, width: i32, height: i32) error{OutOfMemory}!void {
    if (bitmap.memory) |memory| {
        _ = VirtualFree(@ptrCast(*c_void, memory), 0, MEM_RELEASE);
    }

    bitmap.height = height;
    bitmap.width = width;
    bitmap.pitch = @intCast(u32, bitmap.width) * 4;

    bitmap.info.bmiHeader = .{
        .biSize = @sizeOf(@TypeOf(bitmap.info.bmiHeader)),
        .biWidth = width,
        // negative for top-down index
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

    const size = @intCast(usize, bitmap.width) * @intCast(usize, bitmap.height) * 4;
    const memory = @ptrCast(?[*]u8, VirtualAlloc(null, size, MEM_COMMIT, PAGE_READWRITE));
    bitmap.memory = memory orelse return error.OutOfMemory;

    // TODO: clear
}

fn updateWindow(
    bitmap: ScreenBuffer,
    ctx: HDC,
    window_width: i32,
    window_height: i32,
) void {
    _ = StretchDIBits(
        ctx,
        // dest rect
        0, //x,
        0, //y,
        window_width,
        window_height,
        // source rect
        0, //x,
        0, //y,
        bitmap.width,
        bitmap.height,
        bitmap.memory,
        &bitmap.info,
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
    _ = wparam;
    _ = lparam;

    var result: LRESULT = 0;

    switch (message) {
        WM_SIZE => {},

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

            const dim = windowDimensions(window);
            updateWindow(back_buffer, ctx, dim.width, dim.height);
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

    resizeDibSection(&back_buffer, 1280, 720) catch @panic("out of memory");

    var wnd = mem.zeroes(WNDCLASSEXA);
    wnd.style = @intToEnum(WNDCLASS_STYLES, @enumToInt(CS_HREDRAW) | @enumToInt(CS_VREDRAW));
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

    const ctx = GetDC(window);
    defer _ = ReleaseDC(window, ctx);

    while (running) {
        while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == WM_QUIT) running = false;
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }

        renderOddGradient(back_buffer, x_offset, y_offset);

        x_offset +%= 1;
        y_offset +%= 1;

        var client_rect: RECT = undefined;
        _ = GetClientRect(window, &client_rect);

        const dim = windowDimensions(window);

        updateWindow(back_buffer, ctx, dim.width, dim.height);
    }

    return 0;
}
