const std = @import("std");

pub fn TicketLock(comptime value_type: type) type {
    return struct {
        current_ticket: std.atomic.Atomic(u32),
        value: value_type,
    };
}
