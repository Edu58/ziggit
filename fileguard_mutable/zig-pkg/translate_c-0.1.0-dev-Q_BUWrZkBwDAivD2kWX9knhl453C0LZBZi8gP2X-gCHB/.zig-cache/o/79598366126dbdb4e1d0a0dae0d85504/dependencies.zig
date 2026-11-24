pub const packages = struct {
    pub const @"aro-0.1.0-dev-zsf-JSD1QvK5OQBz7R3t4i_xhQmdifnQnUppPy-1YWNs4BZY" = struct {
        pub const build_root = "zig-pkg/aro-0.1.0-dev-zsf-JSD1QvK5OQBz7R3t4i_xhQmdifnQnUppPy-1YWNs4BZY";
        pub const build_zig = @import("aro-0.1.0-dev-zsf-JSD1QvK5OQBz7R3t4i_xhQmdifnQnUppPy-1YWNs4BZY");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "aro", "aro-0.1.0-dev-zsf-JSD1QvK5OQBz7R3t4i_xhQmdifnQnUppPy-1YWNs4BZY" },
};
