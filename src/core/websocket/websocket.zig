//! WebSocket protocol support (RFC 6455).
//!
//! Re-exports the key types from sub-modules.

pub const WebSocket = @import("connection.zig").WebSocket;
pub const Message = @import("connection.zig").Message;
pub const Handler = @import("connection.zig").Handler;
pub const runLoop = @import("connection.zig").runLoop;

pub const Opcode = @import("frame.zig").Opcode;
pub const Frame = @import("frame.zig").Frame;
pub const readFrame = @import("frame.zig").readFrame;
pub const writeFrame = @import("frame.zig").writeFrame;
pub const writeCloseFrame = @import("frame.zig").writeCloseFrame;
pub const applyMask = @import("frame.zig").applyMask;

pub const computeAcceptKey = @import("handshake.zig").computeAcceptKey;
pub const validateUpgradeRequest = @import("handshake.zig").validateUpgradeRequest;
pub const buildUpgradeResponse = @import("handshake.zig").buildUpgradeResponse;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
