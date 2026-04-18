//! `jelly export-json <in> --out <out>` — write canonical JSON rendering.
//!
//! To preserve signatures in the JSON output, this command uses
//! `stripSignatures` to lift the signed-assertion objects back out of the
//! envelope and re-attaches them to the decoded DreamBall before JSON
//! emission. Other assertions (look/feel/act/name/created/...) are still
//! lost until the full envelope decoder lands.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "out" },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(1) or parsed.positional.items.len == 0) {
        try io.writeAllStdout("jelly export-json <in.jelly> --out <out.jelly.json>\n");
        return 0;
    }

    const in_path = parsed.positional.items[0];
    const out_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --out is required\n");
        return 2;
    };

    const bytes = try helpers.readFile(gpa, in_path);
    defer gpa.free(bytes);
    var db = try dreamball.envelope.decodeDreamBallSubject(bytes);

    var stripped = try dreamball.envelope.stripSignatures(gpa, bytes);
    defer stripped.deinit();

    const sigs = try gpa.alloc(dreamball.protocol.Signature, stripped.signatures.len);
    defer gpa.free(sigs);
    for (stripped.signatures, 0..) |captured, i| {
        sigs[i] = .{ .alg = captured.alg, .value = captured.value };
    }
    db.signatures = sigs;

    const jtext = try dreamball.json.writeDreamBall(gpa, db);
    defer gpa.free(jtext);

    try helpers.writeFile(out_path, jtext);
    try io.printStdout("exported → {s} ({d} bytes)\n", .{ out_path, jtext.len });
    return 0;
}
