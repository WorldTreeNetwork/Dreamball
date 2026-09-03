//! `dreamball grow <in> --key <keyfile> [flags...]` — update slots and re-sign.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const io = @import("../io.zig");
const args_mod = @import("args.zig");
const helpers = @import("helpers.zig");

const SPECS = [_]args_mod.Spec{
    .{ .long = "key" },
    .{ .long = "out" },
    .{ .long = "stage" },
    .{ .long = "set-name" },
    .{ .long = "set-personality" },
    .{ .long = "set-voice" },
    .{ .long = "set-model" },
    .{ .long = "set-system-prompt" },
    .{ .long = "set-look" },
    .{ .long = "revision-bump", .takes_value = false },
    .{ .long = "help", .takes_value = false },
};

pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
    var parsed = try args_mod.parse(gpa, argv, &SPECS);
    defer parsed.deinit();

    if (parsed.flag(10) or parsed.positional.items.len == 0) {
        try io.writeAllStdout(
            \\dreamball grow <in.ball> --key <keyfile> [flags]
            \\  --out <path>             write updated file here (default: in-place)
            \\  --stage <seed|dreamball> set the stage value
            \\  --set-name <str>
            \\  --set-personality <str>
            \\  --set-voice <str>
            \\  --set-model <str>
            \\  --set-system-prompt <str>
            \\  --set-look <look.json>   attach a ball.look scene slot (assets/url/background)
            \\  --revision-bump          increment revision by 1
            \\
        );
        return 0;
    }

    const in_path = parsed.positional.items[0];
    const key_path = parsed.get(0) orelse {
        try io.writeAllStderr("error: --key is required\n");
        return 2;
    };
    const out_path = parsed.get(1) orelse in_path;

    const in_bytes = try helpers.readFile(gpa, in_path);
    defer gpa.free(in_bytes);

    // Decode subject + every prior assertion into an arena. Prior attributes
    // (name, feel, act, …) survive into the re-encoded envelope unless this
    // grow explicitly overwrites them; signEnvelope re-encodes from `db`
    // before the arena is freed.
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var db = try dreamball.envelope.decodeDreamBall(arena.allocator(), in_bytes);

    if (parsed.get(2)) |stage_str| {
        db.stage = dreamball.Stage.fromString(stage_str) orelse {
            try io.writeAllStderr("error: --stage must be seed|dreamball|dragonball\n");
            return 2;
        };
    }
    if (parsed.get(3)) |n| db.name = n;

    var feel: ?dreamball.Feel = null;
    if (parsed.get(4)) |p| {
        feel = .{ .personality = p };
    }
    if (parsed.get(5)) |v| {
        if (feel) |*f| {
            f.voice = v;
        } else {
            feel = .{ .voice = v };
        }
    }
    if (feel) |f| db.feel = f;

    var act: ?dreamball.Act = null;
    if (parsed.get(6)) |m| act = .{ .model = m };
    if (parsed.get(7)) |sp| {
        if (act) |*a| {
            a.system_prompt = sp;
        } else {
            act = .{ .system_prompt = sp };
        }
    }
    if (act) |a| db.act = a;

    // --set-look: attach (or replace) the look slot from a standalone
    // ball.look JSON, then re-sign below. Decoded into the same arena as the
    // rest of `db` so its strings survive until signEnvelope re-encodes.
    if (parsed.get(8)) |look_path| {
        const look_json = try helpers.readFile(gpa, look_path);
        defer gpa.free(look_json);
        db.look = dreamball.json.readLook(arena.allocator(), look_json) catch {
            try io.writeAllStderr("error: --set-look: invalid ball.look JSON\n");
            return 2;
        };
    }

    if (parsed.flag(9)) db.revision += 1;
    db.updated = io.unixSeconds();
    if (db.stage == .seed) db.stage = .dreamball;

    const sign = @import("sign.zig");
    const signed = try sign.signEnvelope(gpa, &db, key_path);
    defer gpa.free(signed);

    try helpers.writeFile(out_path, signed);
    try io.printStdout("grew → {s}  revision={d}\n", .{ out_path, db.revision });
    return 0;
}
