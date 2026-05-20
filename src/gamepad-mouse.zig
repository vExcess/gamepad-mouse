const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/extensions/XTest.h");
});

const TRUE = 1;
const FALSE = 0;

const InputType = struct {
    const Button = 1;
    const Axis = 3;
};

const X11MouseButton = struct {
    const Left = 1;
    const Middle  = 2;
    const Right = 3;
    const ScrollUp = 4;
    const ScrollDown = 5;
    const ScrollLeft = 6;
    const ScrollRight = 7;
};

// see /usr/include/linux/input.h
const InputEvent = extern struct {
    time: extern struct {
        tv_sec: i64, // seconds
        tv_usec: i64, // microseconds
    },
    type: u16,
    code: u16,
    value: i32,
};

const Vec2 = struct {
    x: f32 = undefined,
    y: f32 = undefined,

    fn zeroed() Vec2 {
        return Vec2{
            .x = 0,
            .y = 0
        };
    }
};

const State = struct {
    mutex: Mutex = Mutex{},
    normalizedLeftJoystick: Vec2 = Vec2.zeroed(),
    normalizedRightJoystick: Vec2 = Vec2.zeroed(),
};

const bindings = .{
    .buttons = .{
        .A = 304,
        .B = 305,
        .X = 307,
        .Y = 308,
    },
    .leftJoystick = .{
        .horizontal = 0,
        .vertical = 1,
    },
    .rightJoystick = .{
        .horizontal = 3,
        .vertical = 4,
    }
};

const DEADZONE: f32 = 0.01;
const MOVE_SENSITIVITY: f32 = 10.0;
const SCROLL_SENSITIVITY: f32 = 0.4;
const REFRESH_RATE = 60;

fn normalizeJoystickInput(n: i32) f32 {
    const nf: f32 = @floatFromInt(n);
    if (n < 0) {
        return nf / 32768.0;
    } else {
        return nf / 32767.0;
    }
}

fn inputThread(file: std.fs.File, state: *State, display: *c.Display) void {
    // handle gamepad events
    var event: InputEvent = undefined;
    const eventSize = @sizeOf(InputEvent);

    while (true) {
        const bytesRead = file.read(std.mem.asBytes(&event)) catch |err| {
            std.debug.print("Error reading device (probably the controller disconnected): {}\n", .{err});
            break;
        };

        if (bytesRead != eventSize) continue;

        // skip sync events
        if (event.type == 0) continue;

        const code = event.code;

        if (event.type == InputType.Axis) {
            state.mutex.lock();

            const normalizedValue = normalizeJoystickInput(event.value);
            switch (code) {
                bindings.leftJoystick.horizontal => {
                    state.normalizedLeftJoystick.x = normalizedValue;
                },
                bindings.leftJoystick.vertical => {
                    state.normalizedLeftJoystick.y = normalizedValue;
                },
                bindings.rightJoystick.horizontal => {
                    state.normalizedRightJoystick.x = normalizedValue;
                },
                bindings.rightJoystick.vertical => {
                    state.normalizedRightJoystick.y = normalizedValue;
                },
                else => {},
            }

            state.mutex.unlock();
        } else if (event.type == InputType.Button) {
            const isButtonPressed = event.value;
            switch (code) {
                bindings.buttons.X, bindings.buttons.A => {
                    _ = c.XTestFakeButtonEvent(display, X11MouseButton.Left, isButtonPressed, 0);
                },
                bindings.buttons.B => {
                    _ = c.XTestFakeButtonEvent(display, X11MouseButton.Right, isButtonPressed, 0);
                },
                bindings.buttons.Y => {
                    _ = c.XTestFakeButtonEvent(display, X11MouseButton.Middle, isButtonPressed, 0);
                },
                else => {}
            }
            _ = c.XFlush(display);
        }
    }
}

pub fn main() !void {
    // enables X11 thread safety
    _ = c.XInitThreads();

    // Find the device    
    var devicePathBuff: [512]u8 = undefined;
    var devicePath: ?[]const u8 = null;
    var dir = try std.fs.openDirAbsolute("/dev/input/by-id", .{ .iterate = true });
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.indexOf(u8, entry.name, "-event-joystick") != null) {
            devicePath = try std.fmt.bufPrint(&devicePathBuff, "/dev/input/by-id/{s}", .{entry.name});
            break;
        }
    }
    dir.close();

    // check and print device
    if (devicePath == null) {
        std.debug.print("No compatible controller found\n", .{});
        return;
    }
    std.debug.print("Using device: {s}\n", .{devicePath.?});

    // open device file
    const file = std.fs.openFileAbsolute(devicePath.?, .{ .mode = .read_only }) catch |err| {
        if (err == error.AccessDenied) {
            std.debug.print("Permission Denied. Run gamepad-mouse with sudo.\n", .{});
        } else {
            std.debug.print("Failed to open device: {}\n", .{err});
        }
        return;
    };
    defer file.close();

    // get X11 connection
    const display = c.XOpenDisplay(null);
    if (display == null) {
        std.debug.print("Failed to open X11 display. Wayland is not supported!\n", .{});
        return;
    }
    defer _ = c.XCloseDisplay(display);

    const rootWindow = c.XDefaultRootWindow(display);

    var state = State{};

    // spawn input processing thread
    const thread = try std.Thread.spawn(.{}, inputThread, .{ file, &state, display.? });
    thread.detach();

    var xScrollAccumulator: f32 = 0;
    var yScrollAccumulator: f32 = 0;

    // update loop
    while (true) {
        state.mutex.lock();
        const joyLeft = state.normalizedLeftJoystick;
        const joyRight = state.normalizedRightJoystick;
        state.mutex.unlock();

        // move mouse
        if (@abs(joyLeft.x) > DEADZONE or @abs(joyLeft.y) > DEADZONE) {
            // Returns the root window that the pointer is in.
            var rootReturn: c.Window = undefined;
            // Returns the child window that the pointer is located in, if any
            var childReturn: c.Window = undefined;
            // Return the pointer coordinates relative to the root window's origin
            var rootXReturn: c_int = 0;
            var rootYReturn: c_int = 0;
            // Return the pointer coordinates relative to the specified window
            var winXReturn: c_int = 0;
            var winYReturn: c_int = 0;
            // Returns the current state of the modifier keys and pointer buttons
            var maskReturn: c_uint = 0;

            if (c.XQueryPointer(display, rootWindow, &rootReturn, &childReturn, &rootXReturn, &rootYReturn, &winXReturn, &winYReturn, &maskReturn) != FALSE) {
                const newX = rootXReturn + @as(c_int, @intFromFloat(joyLeft.x * MOVE_SENSITIVITY));
                const newY = rootYReturn + @as(c_int, @intFromFloat(joyLeft.y * MOVE_SENSITIVITY));
                
                // If screen_number is -1, the current screen (that the pointer is on) is used.
                // https://linux.die.net/man/3/xtestfakemotionevent
                _ = c.XTestFakeMotionEvent(display, -1, newX, newY, 0);
            }
        }

        // do scrolling
        if (@abs(joyRight.x) > DEADZONE or @abs(joyRight.y) > DEADZONE) {
            xScrollAccumulator += joyRight.x * -SCROLL_SENSITIVITY;
            yScrollAccumulator += joyRight.y * -SCROLL_SENSITIVITY;

            std.debug.print("{}\n", .{yScrollAccumulator});

            while (@abs(yScrollAccumulator) >= 1.0) {
                const btn: c_uint = if (yScrollAccumulator > 0) X11MouseButton.ScrollUp else X11MouseButton.ScrollDown;
                _ = c.XTestFakeButtonEvent(display, btn, TRUE, 0);
                _ = c.XTestFakeButtonEvent(display, btn, FALSE, 0);
                yScrollAccumulator -= if (yScrollAccumulator > 0) 1.0 else -1.0;
            }

            while (@abs(xScrollAccumulator) >= 1.0) {
                const btn: c_uint = if (xScrollAccumulator > 0) X11MouseButton.ScrollLeft else X11MouseButton.ScrollRight;
                _ = c.XTestFakeButtonEvent(display, btn, TRUE, 0);
                _ = c.XTestFakeButtonEvent(display, btn, FALSE, 0);
                xScrollAccumulator -= if (xScrollAccumulator > 0) 1.0 else -1.0;
            }
        }

        _ = c.XFlush(display);
        Thread.sleep(std.time.ns_per_s / REFRESH_RATE);
    }
}