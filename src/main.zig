// A tool for generating HaldCLUT images
//
// Copyright (c) 2022 Sampo Vuori


const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
});

const std = @import("std");
const assert = std.debug.assert;
const warn = std.log.warn;
const info = std.log.info;
const math = std.math;
const mem = std.mem;

const images_file = "./images.txt";

const SDL_WINDOWPOS_UNDEFINED = @bitCast(c_int, sdl.SDL_WINDOWPOS_UNDEFINED_MASK);

const LEVEL = 8;
const WIDTH = LEVEL * LEVEL * LEVEL;
const HEIGHT = LEVEL * LEVEL * LEVEL;
const CUBE_SIZE = LEVEL * LEVEL;

const CLIP_LOW = 3;
const CLIP_HIGH = 252;

const MIN_VEC_REQ = 5;

var mapping: [256][256][256][3]f32 = undefined;

var imageData: [WIDTH * HEIGHT * 3]u8 = undefined;

extern fn SDL_PollEvent(event: *sdl.SDL_Event) c_int;

const Vector3 = struct {
    x: f32, y: f32, z: f32
};

const M_DIM = 16;
const M_LEN = 2000;
const MAX_PER_FILE = 40;

var colorMatrix: [M_DIM][M_DIM][M_DIM][M_LEN]Vector3 = undefined;
var vecsPerFile = std.mem.zeroes([M_DIM][M_DIM][M_DIM]u32);
var cmlen = std.mem.zeroes([M_DIM][M_DIM][M_DIM]u32);

var resultMatrix: [M_DIM + 2][M_DIM + 2][M_DIM + 2]Vector3 = undefined;

// SDL_RWclose is fundamentally unrepresentable in Zig, because `ctx` is
// evaluated twice. One could make the case that this is a bug in SDL,
// especially since the docs list a real function prototype that would not
// have this double-evaluation of the parameter.
// If SDL would instead of a macro use a static inline function,
// it would resolve the SDL bug as well as make the function visible to Zig
// and to debuggers.
// SDL_rwops.h:#define SDL_RWclose(ctx)        (ctx)->close(ctx)
fn SDL_RWclose(ctx: [*]sdl.SDL_RWops) c_int {
    return ctx[0].close.?(ctx);
}

fn vecAdd(v1: Vector3, v2: Vector3) Vector3 {
    return Vector3{ .x = v1.x + v2.x, .y = v1.y + v2.y, .z = v1.z + v2.z };
}

fn vecDiv(vec: Vector3, scalar: f32) Vector3 {
    return Vector3{ .x = vec.x / scalar, .y = vec.y / scalar, .z = vec.z / scalar };
}

fn vecMul(vec: Vector3, scalar: f32) Vector3 {
    return Vector3{ .x = vec.x * scalar, .y = vec.y * scalar, .z = vec.z * scalar };
}

fn colorAdjustVector(vec: *Vector3, r: u32, g: u32, b: u32) void {
    var ri = @intCast(i32, colorToIndex(@intCast(u8, r)));
    var gi = @intCast(i32, colorToIndex(@intCast(u8, g)));
    var bi = @intCast(i32, colorToIndex(@intCast(u8, b)));

    var rrem = @rem(vec.x, (245 / M_DIM)) / (256 / M_DIM);
    var grem = @rem(vec.y, (245 / M_DIM)) / (256 / M_DIM);
    var brem = @rem(vec.z, (245 / M_DIM)) / (256 / M_DIM);

    var rpow = math.fabs((rrem - 0.5) * 2);
    var gpow = math.fabs((grem - 0.5) * 2);
    var bpow = math.fabs((brem - 0.5) * 2);

    var ri2 = if (rrem < 0.5) (ri - 1) else (ri + 1);
    var gi2 = if (grem < 0.5) (gi - 1) else (gi + 1);
    var bi2 = if (brem < 0.5) (bi - 1) else (bi + 1);

    var vec1 = resultMatrix[colorToIndex(@intCast(u8, ri + 1))][colorToIndex(@intCast(u8, gi + 1))][colorToIndex(@intCast(u8, bi + 1))];

    var vec2 = resultMatrix[@intCast(u32, ri2 + 1)][@intCast(u32, gi2 + 1)][@intCast(u32, bi2 + 1)];

    vec.x = math.max(0, math.min(255, vec.x + vec1.x * (1 - rpow) + vec2.x * rpow));
    vec.y = math.max(0, math.min(255, vec.y + vec1.y * (1 - gpow) + vec2.y * gpow));
    vec.z = math.max(0, math.min(255, vec.z + vec1.z * (1 - bpow) + vec2.z * bpow));
}

fn populateImageData(data: []u8) void {
    var y: u32 = 0;
    while (y < HEIGHT) {
        var blue: u32 = @intCast(u8, y / LEVEL);
        var x: u32 = 0;
        var green: u32 = 0;
        while (green < CUBE_SIZE) {
            var red: u32 = 0;
            while (red < CUBE_SIZE) {
                var r = (255 * red / (CUBE_SIZE - 1));
                var g = (255 * green / (CUBE_SIZE - 1));
                var b = (255 * blue / (CUBE_SIZE - 1));

                data[(y * WIDTH + x) * 3 + 0] = @intCast(u8, math.max(0, math.min(255, @intCast(i32, r) + @floatToInt(i32, mapping[r][g][b][0]))));
                data[(y * WIDTH + x) * 3 + 1] = @intCast(u8, math.max(0, math.min(255, @intCast(i32, g) + @floatToInt(i32, mapping[r][g][b][1]))));
                data[(y * WIDTH + x) * 3 + 2] = @intCast(u8, math.max(0, math.min(255, @intCast(i32, b) + @floatToInt(i32, mapping[r][g][b][2]))));

                x += 1;
                if (x == WIDTH) {
                    x = 0;
                    y += 1;
                }

                red += 1;
            }
            green += 1;
        }
    }
}

fn colorToIndex(c: u8) u8 {
    return math.min(M_DIM, @divTrunc(c, (256 / M_DIM)));
}

fn loadAndMapImages(from: []const u8, to: []const u8) !void {

    vecsPerFile = std.mem.zeroes([M_DIM][M_DIM][M_DIM]u32);

    var fromSurface: *sdl.SDL_Surface = sdl.IMG_Load(@ptrCast([*c]const u8, from)) orelse {
        warn("Unable to load file {s}\n", .{from});
        sdl.SDL_Log("error: %s", sdl.SDL_GetError());
        return;
    };

    defer sdl.SDL_FreeSurface(fromSurface);
    var toSurface: *sdl.SDL_Surface = sdl.IMG_Load(@ptrCast([*c]const u8, to)) orelse {
        warn("Unable to load file {s}\n", .{to});
        sdl.SDL_Log("error: %s", sdl.SDL_GetError());
        return;
    };

    defer sdl.SDL_FreeSurface(toSurface);

    if(!(fromSurface.w == toSurface.w and fromSurface.h == toSurface.h)) {
        warn("These files have different dimensions {s} and {s}! Returning. \n", .{from, to});
    }

    if (fromSurface.pitch != toSurface.pitch) {
        warn("These files have different pixel pitches, {s} and {s} ! Returning.\n", .{ from, to });
        return;
    }

    var fromPixels = @ptrCast([*]u8, fromSurface.pixels);
    var toPixels = @ptrCast([*]u8, toSurface.pixels);
    var sw = @intCast(u32, fromSurface.w);
    var sh = @intCast(u32, fromSurface.h);
    var y: u32 = 0;

    while (y < sh) {
        var x: u32 = 0;
        while (x < sw) {
            var r1: u8 = fromPixels[(y * sw + x) * 3 + 0];
            var g1: u8 = fromPixels[(y * sw + x) * 3 + 1];
            var b1: u8 = fromPixels[(y * sw + x) * 3 + 2];
            var r2: u8 = toPixels[(y * sw + x) * 3 + 0];
            var g2: u8 = toPixels[(y * sw + x) * 3 + 1];
            var b2: u8 = toPixels[(y * sw + x) * 3 + 2];

            var ri = colorToIndex(r1); //@divTrunc(r1, (256 / M_DIM));
            var gi = colorToIndex(g1); //@divTrunc(g1, (256 / M_DIM));
            var bi = colorToIndex(b1); //@divTrunc(b1, (256 / M_DIM));

            if (cmlen[ri][gi][bi] < M_LEN and vecsPerFile[ri][gi][bi] < MAX_PER_FILE and r2 > CLIP_LOW and r2 < CLIP_HIGH and g2 > CLIP_LOW and g2 < CLIP_HIGH and b2 > CLIP_LOW and b2 < CLIP_HIGH) {
                colorMatrix[ri][gi][bi][cmlen[ri][gi][bi]] = Vector3{
                    .x = @intToFloat(f32, r2) - @intToFloat(f32, r1),
                    .y = @intToFloat(f32, g2) - @intToFloat(f32, g1),
                    .z = @intToFloat(f32, b2) - @intToFloat(f32, b1),
                };
                cmlen[ri][gi][bi] += 1;
                vecsPerFile[ri][gi][bi] += 1;
            } else {
                //warn("Discarded a vector in segment: r({}) g({}) b({})\n", .{ri, gi, bi});
            }

            x += 1;
        }
        y += 1;
    }
}

fn createMapping() void {
    for (mapping) |row, row_index| {
        var max_r: i32 = 0;
        var max_g: i32 = 0;
        var max_b: i32 = 0;
        var min_r: i32 = 255;
        var min_g: i32 = 255;
        var min_b: i32 = 255;
        for (row) |column, column_index| {
            for (column) |cell, cell_index| {
                _ = cell;
                var r_pos: f32 = @intToFloat(f32, row_index) / (256 / M_DIM) + 0.5;
                var g_pos: f32 = @intToFloat(f32, column_index) / (256 / M_DIM) + 0.5;
                var b_pos: f32 = @intToFloat(f32, cell_index) / (256 / M_DIM) + 0.5;

                var r_rem = r_pos - @floor(r_pos);
                var g_rem = g_pos - @floor(g_pos);
                var b_rem = b_pos - @floor(b_pos);

                var ri = @floatToInt(u32, @floor(r_pos));
                var gi = @floatToInt(u32, @floor(g_pos));
                var bi = @floatToInt(u32, @floor(b_pos));

                var v111 = resultMatrix[ri][gi][bi];
                var v112 = resultMatrix[ri][gi][bi + 1];
                var v121 = resultMatrix[ri][gi + 1][bi];
                var v122 = resultMatrix[ri][gi + 1][bi + 1];
                var v211 = resultMatrix[ri + 1][gi][bi];
                var v212 = resultMatrix[ri + 1][gi][bi + 1];
                var v221 = resultMatrix[ri + 1][gi + 1][bi];
                var v222 = resultMatrix[ri + 1][gi + 1][bi + 1];

                var v111_v211 = vecAdd(vecMul(v111, (1 - r_rem)), vecMul(v211, r_rem));
                var v121_v221 = vecAdd(vecMul(v121, (1 - r_rem)), vecMul(v221, r_rem));

                var v111_v211_v121_v221 = vecAdd(vecMul(v111_v211, (1 - g_rem)), vecMul(v121_v221, g_rem));

                var v112_v212 = vecAdd(vecMul(v112, (1 - r_rem)), vecMul(v212, r_rem));
                var v122_v222 = vecAdd(vecMul(v122, (1 - r_rem)), vecMul(v222, r_rem));

                var v112_v212_v122_v222 = vecAdd(vecMul(v112_v212, (1 - g_rem)), vecMul(v122_v222, g_rem));

                var resultVec = vecAdd(vecMul(v111_v211_v121_v221, (1 - b_rem)), vecMul(v112_v212_v122_v222, b_rem));

                var cx = @floatToInt(i32, resultVec.x);
                var cy = @floatToInt(i32, resultVec.y);
                var cz = @floatToInt(i32, resultVec.z);

                if (min_r > cx) min_r = cx;
                if (min_g > cy) min_g = cy;
                if (min_b > cz) min_b = cz;

                if (max_r < cx) max_r = cx;
                if (max_g < cy) max_g = cy;
                if (max_b < cz) max_b = cz;

                mapping[row_index][column_index][cell_index][0] = resultVec.x;
                mapping[row_index][column_index][cell_index][1] = resultVec.y;
                mapping[row_index][column_index][cell_index][2] = resultVec.z;
            }
        }
    }
}

fn createResultMatrix() void {
    for (resultMatrix) |row, row_index| {
        for (row) |column, column_index| {
            for (column) |cell, cell_index| {
                _ = cell;
                resultMatrix[row_index][column_index][cell_index] = Vector3{ .x = 0, .y = 0, .z = 0 };
            }
        }
    }

    for (colorMatrix) |row, row_index| {
        for (row) |column, column_index| {
            for (column) |cell, cell_index| {
                _ = cell;
                var resultVec = Vector3{ .x = 0, .y = 0, .z = 0 };
                var index: u32 = 0;
                if (cmlen[row_index][column_index][cell_index] > MIN_VEC_REQ) {
                    while (index < cmlen[row_index][column_index][cell_index]) {
                        resultVec = vecAdd(resultVec, colorMatrix[row_index][column_index][cell_index][index]);
                        index += 1;
                    }
                    resultVec = vecDiv(resultVec, @intToFloat(f32, cmlen[row_index][column_index][cell_index]));
                }
                resultMatrix[row_index + 1][column_index + 1][cell_index + 1] = resultVec;
            }
        }
    }
}

fn print_matrix() void {
    info("matrix lengths are as follows: \n", .{});
    for (cmlen) |row, row_index| {
        _ = row_index;
        for (row) |column, column_index| {
            _ = column_index;
            for (column) |cell, cell_index| {
                _ = cell_index;
                std.debug.print("{} ", .{cell});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n", .{});
    }
}

pub fn main() anyerror!void {
    info("Start", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var dir = std.fs.cwd().openDir("./", .{}) catch |err| {
        return err;
    };
    const image_list = try dir.readFileAlloc(allocator, images_file, std.math.maxInt(usize));


    var lines_it = mem.tokenize(u8, image_list, "\r\n");

    while (lines_it.next()) |line| {
        var source_path = try mem.join(allocator, "", &[_][]const u8{ "./source_images/", line, "\x00" });
        defer allocator.free(source_path);

        var target_path = try mem.join(allocator, "", &[_][]const u8{ "./target_images/", line, "\x00" });
        defer allocator.free(target_path);

        try loadAndMapImages(source_path, target_path);
    }

    defer allocator.free(image_list);

    //print_matrix();

    info("creating the result matrix\n", .{});

    createResultMatrix();

    createMapping();

    populateImageData(&imageData);

    info("Created the HaldCLUT image\n", .{});

    //const surface = sdl.SDL_CreateRGBSurfaceFrom(@ptrCast(*c_void, &imageData[0]), WIDTH, HEIGHT, 24, WIDTH * 3, 0x000000ff, 0x0000ff00, 0x00ff0000, 0);

    const surface = sdl.SDL_CreateRGBSurfaceFrom(@ptrCast(*u8, &imageData[0]), WIDTH, HEIGHT, 24, WIDTH * 3, 0x000000ff, 0x0000ff00, 0x00ff0000, 0);

    defer sdl.SDL_FreeSurface(surface);

    _ = sdl.IMG_SavePNG(surface, "lut.png");
    info("Saved: lut.png", .{});
}
