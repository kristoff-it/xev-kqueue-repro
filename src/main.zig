const std = @import("std");
const builtin = @import("builtin");
const xev = @import("xev");

// Open two netcat instances and make them listen to these ports
const recv1_addr = std.net.Address.parseIp4("0.0.0.0", 1993) catch unreachable;
const recv2_addr = std.net.Address.parseIp4("0.0.0.0", 1994) catch unreachable;

var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
const gpa = gpa_impl.allocator();

var timer = xev.Timer.init() catch unreachable;
pub fn main() !void {
    if (builtin.os.tag != .macos) {
        @compileError("this repro only works on macos");
    }

    const sender_addr = try std.net.Address.parseIp4("0.0.0.0", 1992);

    var loop = try xev.Loop.init(.{});

    var udp = try xev.UDP.init(sender_addr);
    try udp.bind(sender_addr);

    std.debug.print("bound to {}\n", .{sender_addr});

    var timer_c: xev.Completion = .{};
    schedule_timer(&timer_c, &loop, &udp);

    try loop.run(.until_done);
    std.debug.print("exiting", .{});
}

// Because rearm doesn't seem to have an easy way to
// define a fixed interval.
pub fn schedule_timer(
    timer_c: *xev.Completion,
    loop: *xev.Loop,
    udp: *xev.UDP,
) void {
    timer.run(loop, timer_c, 1000, xev.UDP, udp, struct {
        fn cb(
            ud: ?*xev.UDP,
            l: *xev.Loop,
            timer_c_inner: *xev.Completion,
            r: xev.Timer.RunError!void,
        ) xev.CallbackAction {
            _ = r catch unreachable;

            const udp_inner = ud.?;

            std.debug.print("timer running\n", .{});

            // Issue two writes in parallel
            const addresses: []const std.net.Address = &.{ recv1_addr, recv2_addr };
            for (addresses) |addr| {
                const c = gpa.create(xev.Completion) catch unreachable;
                const s = gpa.create(xev.UDP.State) catch unreachable;

                std.debug.print("sending to {}\n", .{addr});

                udp_inner.write(
                    l,
                    c,
                    s,
                    addr,
                    .{ .slice = "hello\n" },
                    void,
                    undefined,

                    struct {
                        fn cb(
                            _: ?*void,
                            _: *xev.Loop,
                            c_inner: *xev.Completion,
                            s_inner: *xev.UDP.State,
                            _: xev.UDP,
                            _: xev.WriteBuffer,
                            r_inner: xev.UDP.WriteError!usize,
                        ) xev.CallbackAction {
                            _ = r_inner catch unreachable;

                            std.debug.print("success sending to {}\n", .{
                                c_inner.op.sendto.addr,
                            });

                            gpa.destroy(c_inner);
                            gpa.destroy(s_inner);

                            return .disarm;
                        }
                    }.cb,
                );
            }

            schedule_timer(timer_c_inner, l, udp_inner);
            return .disarm;
        }
    }.cb);
}
