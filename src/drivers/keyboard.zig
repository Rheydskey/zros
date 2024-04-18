const serial = @import("serial.zig");

const KEYBOARDMAP: [56]u8 = [_]u8{
    '\x00', '\x00', '1', '2', '3',  '4', '5', '6',  '7', '8', '9',  '0',    '-', '=', '\x00', '\t', 'q', 'w',
    'e',    'r',    't', 'y', 'u',  'i', 'o', 'p',  '[', ']', '\\', '\x00', 'a', 's', 'd',    'f',  'g', 'h',
    'j',    'k',    'l', ';', '\'', '`', ' ', '\\', 'z', 'x', 'c',  'v',    'b', 'n', 'm',    ',',  '.', '/',
    ' ',    '*',
};

const MAJKEYBOARDMAP: [56]u8 = [_]u8{
    '\x00', '\x00', '!', '@', '#', '$',  '%', '^',  '&', '*', '(', ')',    '_', '+', '\x00', '\t', 'Q', 'W',
    'E',    'R',    'T', 'Y', 'U', 'I',  'O', 'P',  '{', '}', '|', '\x00', 'A', 'S', 'D',    'F',  'G', 'H',
    'J',    'K',    'L', ':', '"', '\n', ' ', '\\', 'Z', 'X', 'C', 'V',    'B', 'N', 'M',    '<',  '>', '?',
    ' ',    '*',
};

const KeyboardEvent = enum {
    Key,
    Esc,
    Space,
    Shift,
    Ctrl,
    Enter,
    BackSpace,
    Other,
};

pub fn event2enum(scancode: u8) KeyboardEvent {
    const event = switch (scancode) {
        0x01 => KeyboardEvent.Esc,
        0x0E => KeyboardEvent.BackSpace,
        0x1C => KeyboardEvent.Enter,
        0x36, 0x2A => KeyboardEvent.Shift,
        0x39 => KeyboardEvent.Space,
        0x1D => KeyboardEvent.Ctrl,
        else => {
            if (scancode >= comptime @as(u8, KEYBOARDMAP.len)) {
                return KeyboardEvent.Other;
            }

            return KeyboardEvent.Key;
        },
    };

    return event;
}

var shift = false;
var ctrl = false;

pub fn handle(scancode: u8) void {
    const event = event2enum(scancode);
    serial.println("{}", .{event});
    var screen = &@import("./fbscreen.zig").screen.?;

    switch (event) {
        KeyboardEvent.Key => {
            if (shift) {
                serial.Serial.write(MAJKEYBOARDMAP[scancode]);
                screen.print(MAJKEYBOARDMAP[scancode]);
                return;
            }
            serial.Serial.write(KEYBOARDMAP[scancode]);
            screen.print(KEYBOARDMAP[scancode]);
        },
        KeyboardEvent.Space => {
            serial.Serial.write(' ');
            screen.print(' ');
        },
        KeyboardEvent.BackSpace => {
            screen.remove(10);
            screen.print(' ');
            screen.remove(10);
        },
        KeyboardEvent.Shift => shift = !shift,
        KeyboardEvent.Enter => {
            screen.nextLine();
        },
        else => {},
    }
}
