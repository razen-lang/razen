const fmt = @import("fmt.zig");
const os = @import("os.zig");
const debug = @import("debug.zig");

pub fn all() []const u8 {
    return fmt.ir() ++ "\n" ++ os.ir() ++ "\n" ++ debug.ir();
}
