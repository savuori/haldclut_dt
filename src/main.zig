const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

const assert = @import("std").debug.assert;
const warn = @import("std").debug.warn;
const math = @import("std").math;


// See https://github.com/zig-lang/zig/issues/565
// SDL_video.h:#define SDL_WINDOWPOS_UNDEFINED         SDL_WINDOWPOS_UNDEFINED_DISPLAY(0)
// SDL_video.h:#define SDL_WINDOWPOS_UNDEFINED_DISPLAY(X)  (SDL_WINDOWPOS_UNDEFINED_MASK|(X))
// SDL_video.h:#define SDL_WINDOWPOS_UNDEFINED_MASK    0x1FFF0000u
const SDL_WINDOWPOS_UNDEFINED = @bitCast(c_int, sdl.SDL_WINDOWPOS_UNDEFINED_MASK);

const LEVEL = 4;
const BUBBLE_RADIUS = 4;
const WIDTH = LEVEL * LEVEL * LEVEL;
const HEIGHT = LEVEL * LEVEL * LEVEL;
const CUBE_SIZE=LEVEL*LEVEL;

var mapping : [256][256][256][4]u8 = undefined;

var imageData : [WIDTH*HEIGHT*3]u8 = undefined;

extern fn SDL_PollEvent(event: *sdl.SDL_Event) c_int;

// SDL_RWclose is fundamentally unrepresentable in Zig, because `ctx` is
// evaluated twice. One could make the case that this is a bug in SDL,
// especially since the docs list a real function prototype that would not
// have this double-evaluation of the parameter.
// If SDL would instead of a macro use a static inline function,
// it would resolve the SDL bug as well as make the function visible to Zig
// and to debuggers.
// SDL_rwops.h:#define SDL_RWclose(ctx)        (ctx)->close(ctx)
inline fn SDL_RWclose(ctx: [*]sdl.SDL_RWops) c_int {
    return ctx[0].close.?(ctx);
}

fn populateImageData(data: []u8, map: [256][256][256][4]u8) void {
    var y : u32 = 0;
    while(y < HEIGHT) {
        var blue : u32 = @intCast(u8, y / LEVEL);
        var x : u32 = 0;
        var green : u32 = 0;
        while(green < CUBE_SIZE) {
            var red : u32 = 0;
            while(red < CUBE_SIZE) {
                var r = (255 * red / (CUBE_SIZE -1));
                var g = (255 * green / (CUBE_SIZE -1));
                var b = (255 * blue / (CUBE_SIZE -1));

                if(map[r][g][b][3] == 0) {
                    data[(y*WIDTH + x)*3 + 0] = @intCast(u8, r);
                    data[(y*WIDTH + x)*3 + 1] = @intCast(u8, g);
                    data[(y*WIDTH + x)*3 + 2] = @intCast(u8, b);
                } else {
                    data[(y*WIDTH + x)*3 + 0] = @intCast(u8,
                                                         @divTrunc(@intCast(u32, r) * (255 - @intCast(u32, map[r][g][b][3])) + @intCast(u32, map[r][g][b][0]) * @intCast(u32, map[r][g][b][3]), 255));
                    data[(y*WIDTH + x)*3 + 1] = @intCast(u8, @divTrunc(@intCast(u32, g) * (255 - @intCast(u32, map[r][g][b][3])) + @intCast(u32, map[r][g][b][1]) * @intCast(u32, map[r][g][b][3]), 255));
                    data[(y*WIDTH + x)*3 + 2] = @intCast(u8, @divTrunc(@intCast(u32, b) * (255 - @intCast(u32, map[r][g][b][3])) + @intCast(u32, map[r][g][b][2]) * @intCast(u32, map[r][g][b][3]), 255));

                    warn("r: {} new r: {}, power: {}, result: {}\n", .{r, map[r][g][b][0], map[r][g][b][3], data[(y*WIDTH +x)*3 + 0]});
//                    data[(y*WIDTH + x)*3 + 1] = map[r][g][b][1];
//                    data[(y*WIDTH + x)*3 + 2] = map[r][g][b][2];

                }

                x += 1;
                if(x == WIDTH) {
                    x = 0;
                    y += 1;
                }

                red += 1;
            }
            green += 1;
        }
    }
}


fn bubble(x : u8, y : u8, z : u8, r : u8, g : u8, b : u8) void {

    var fx : u8 = @intCast(u8, math.max(0, @intCast(i32, x) - BUBBLE_RADIUS));
    var tx : u8 = @intCast(u8, math.min(255, @intCast(i32, x) + BUBBLE_RADIUS));
    while(fx < tx) {

        var fy : u8 = @intCast(u8, math.max(0, @intCast(i32, y) - BUBBLE_RADIUS));
        var ty : u8 = @intCast(u8, math.min(255, @intCast(i32, y) + BUBBLE_RADIUS));
        while(fy < ty) {
            var fz : u8 = @intCast(u8, math.max(0, @intCast(i32, z) - BUBBLE_RADIUS));
            var tz : u8 = @intCast(u8, math.min(255, @intCast(i32, z) + BUBBLE_RADIUS));
            while(fz < tz) {
                var mx = @intCast(i32, x);
                var mfx = @intCast(i32, fx);
                var my = @intCast(i32, y);
                var mfy = @intCast(i32, fy);
                var mz = @intCast(i32, z);
                var mfz = @intCast(i32, fz);
                var distance : i32 = math.sqrt(math.pow(i32, (mx - mfx),2) +
                                                   math.pow(i32, (my - mfy),2) +
                                                   math.pow(i32, (mz - mfz),2));
                //warn("distance: {}", .{distance});
                var power : i32 = math.max(0, 255 - @divTrunc((255 * distance), BUBBLE_RADIUS));

                //if(mapping[fx][fy][fz][3] < @intCast(u8, power)) {
                    //mapping[fx][fy][fz][0] = r;
                    //mapping[fx][fy][fz][1] = g;
                    //mapping[fx][fy][fz][2] = b;
                    //mapping[fx][fy][fz][3] = @intCast(u8, power);
                    //warn("power: {}", .{mapping[fx][fy][fz][3]});

                //} else {

                mapping[fx][fy][fz][0] = @intCast(u8, @divTrunc(@intCast(u32, r) + @intCast(u32, mapping[fx][fy][fz][0]), 2));
                mapping[fx][fy][fz][1] = @intCast(u8, @divTrunc(@intCast(u32, g) + @intCast(u32, mapping[fx][fy][fz][1]), 2));
                mapping[fx][fy][fz][2] = @intCast(u8, @divTrunc(@intCast(u32, b) + @intCast(u32, mapping[fx][fy][fz][2]), 2));
                mapping[fx][fy][fz][3] = @intCast(u8, math.min(255, @divTrunc(power*2 + @intCast(i32, mapping[fx][fy][fz][3])*2, 3)));
                //}


                fz += 1;
            }

            fy += 1;
        }
        fx += 1;
    }

    //warn("finished bubble", .{});
}

fn loadAndMapImages(from: []const u8, to: []const u8) void {
    var fromSurface : *sdl.SDL_Surface = sdl.IMG_Load(@ptrCast([*c]const u8, from));
    defer sdl.SDL_FreeSurface(fromSurface);
    var toSurface : *sdl.SDL_Surface = sdl.IMG_Load(@ptrCast([*c]const u8, to));
    defer sdl.SDL_FreeSurface(toSurface);

    assert(fromSurface.w == toSurface.w and fromSurface.h == toSurface.h);

    var fromPixels = @ptrCast([*]u8, fromSurface.pixels);
    var toPixels = @ptrCast([*]u8, toSurface.pixels);
    //warn("r: {} g: {} b: {} a?: {}", .{testi[0], testi[1], testi[2], testi[3]});
    //
    var sw = @intCast(u32, fromSurface.w);
    var sh = @intCast(u32, fromSurface.h);
    var y : u32 = 0;
    while(y < sh){
        var x : u32 = 0;
        while(x < sw) {
            var r1 : u8 = fromPixels[(y * sw + x) * 4 + 0];
            var g1 : u8 = fromPixels[(y * sw + x) * 4 + 1];
            var b1 : u8 = fromPixels[(y * sw + x) * 4 + 2];
            var r2 = toPixels[(y * sw + x) * 4 + 0];
            var g2 = toPixels[(y * sw + x) * 4 + 1];
            var b2 = toPixels[(y * sw + x) * 4 + 2];
            //warn("calling bubble for x: {}", .{x});
            if(r2 < 250 and r2 > 5 and g2 < 250 and g2 > 5 and b2 < 250 and b2 > 5) {
                bubble(r1, g1, b1, r2, g2, b2);

            }

            x += 1;
        }
        y += 1;
    }
}


pub fn main() !void {
    warn("Start", .{});

    //loadAndMapImages("DSCF0198_unprocessed.png", "DSCF0198_camera.png");
    loadAndMapImages("DSCF1326_provia_darktable.png", "DSCF1326_provia_camera.png");
    loadAndMapImages("DSCF1328_provia_darktable2.png", "DSCF1328_provia_camera2.png");
    loadAndMapImages("DSCF1329_provia_darktable.png", "DSCF1329_provia_camera.png");






    warn("Starting to create the texture", .{});

    populateImageData(&imageData, mapping);

    warn("Created the texture", .{});

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    const surface = sdl.SDL_CreateRGBSurfaceFrom(@ptrCast(*c_void, &imageData[0]), WIDTH, HEIGHT, 24, WIDTH*3, 0x000000ff, 0x0000ff00, 0x00ff0000, 0) orelse {
        sdl.SDL_Log("Unable to create surface from data: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };

    defer sdl.SDL_FreeSurface(surface);

    const result = sdl.IMG_SavePNG(surface, "testi.png");

}
