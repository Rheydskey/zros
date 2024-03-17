const limine = @import("limine");

pub export var kaddr_req: limine.KernelAddressRequest = .{};
pub export var base_revision: limine.BaseRevision = .{ .revision = 1 };
pub export var framebuffer: limine.FramebufferRequest = .{};
pub export var memory_map: limine.MemoryMapRequest = .{};
pub export var hhdm: limine.HhdmRequest = .{};
pub export var rspd: limine.RsdpRequest = .{};
