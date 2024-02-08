const serial = @import("serial.zig");
const pic = @import("pic.zig");

const KEYBOARDMAP: [56]u8 = [_]u8{
    '\x00', '\x00', '1', '2', '3',  '4', '5', '6',  '7', '8', '9',  '0',    '-', '=', '\x00', '\t', 'q', 'w',
    'e',    'r',    't', 'y', 'u',  'i', 'o', 'p',  '[', ']', '\n', '\x00', 'a', 's', 'd',    'f',  'g', 'h',
    'j',    'k',    'l', ';', '\'', '`', ' ', '\\', 'z', 'x', 'c',  'v',    'b', 'n', 'm',    ',',  '.', '/',
    ' ',    '*',
};

const Key = struct {
    key: u8,
};

const KeyboardEvent = enum {
    Key,
    Esc,
    Space,
    Back,
    Shift,
    Ctrl,
    Enter,
    Other,
};

pub fn event2enum(scancode: u8) KeyboardEvent {
    const event = switch (scancode) {
        0x01 => KeyboardEvent.Esc,
        0x0E => KeyboardEvent.Back,
        0x1C => KeyboardEvent.Enter,
        0x36 | 0x2A => KeyboardEvent.Shift,
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

pub fn handle(scancode: u8) void {
    const event = event2enum(scancode);

    switch (event) {
        KeyboardEvent.Esc => {
            _ = serial.Serial.write_array("Escape");
        },
        KeyboardEvent.Back => {
            _ = serial.Serial.write_array("Back");
        },
        KeyboardEvent.Enter => {
            _ = serial.Serial.write_array("Enter");
        },
        KeyboardEvent.Shift => {
            _ = serial.Serial.write_array("Shift");
        },
        KeyboardEvent.Space => {
            _ = serial.Serial.write_array("Space");
        },
        KeyboardEvent.Ctrl => {
            _ = serial.Serial.write_array("Ctrl");
        },
        KeyboardEvent.Other => {
            _ = serial.Serial.write_array("Other");
        },
        KeyboardEvent.Key => {
            _ = serial.Serial.write(KEYBOARDMAP[scancode]);
        },
    }
}
