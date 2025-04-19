const std = @import("std");
const rl = @import("raylib");

const LUTCollumns = struct {
    rk: u8,
    nk: usize,
    pr: f64,
    fa: f64,
    eq: u8,
};

const WINDOW_WIDTH = 1080;
const WINDOW_HEIGHT = 720;

var camera = rl.Camera2D{
    .offset = .{ .x = WINDOW_WIDTH / 2, .y = WINDOW_HEIGHT / 2 },
    .target = .{ .x = WINDOW_WIDTH / 2, .y = WINDOW_HEIGHT / 2 },
    .rotation = 0,
    .zoom = 1,
};

var og_tx: ?rl.Texture = null;
var eq_tx: ?rl.Texture = null;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();

    var lut = std.MultiArrayList(LUTCollumns).empty;
    defer lut.deinit(allocator);
    try lut.resize(allocator, 256);

    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Equalização de histograma");
    defer {
        if (og_tx) |_| {
            rl.unloadTexture(og_tx.?);
            rl.unloadTexture(eq_tx.?);
        }
        rl.closeWindow();
    }

    while (!rl.windowShouldClose()) {
        if (rl.isFileDropped()) {
            if (og_tx) |_| {
                rl.unloadTexture(og_tx.?);
                rl.unloadTexture(eq_tx.?);
            }
            const files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(files);

            if (files.count > 1) {
                std.debug.print("Err: Número de errado de arquivos", .{});
            } else {
                og_tx = try rl.loadTexture(std.mem.span(files.paths[0]));

                const og = try rl.loadImageFromTexture(og_tx.?);
                const og_cor = try rl.loadImageColors(og);
                defer rl.unloadImageColors(og_cor);

                // Imagem que será equalizada
                var eq = rl.imageCopy(og);
                const eq_cor = try rl.loadImageColors(eq);
                // grayscale(&eq_cor);

                for (0..lut.len) |i| {
                    lut.set(i, std.mem.zeroes(LUTCollumns));
                }

                for (eq_cor) |cor| {
                    const ch = cor.toHSV();
                    var linha = lut.get(@intFromFloat(@round(ch.z * 255)));
                    linha.nk += 1;
                    lut.set(@intFromFloat(@round(ch.z * 255)), linha);
                }

                const total: f64 = @floatFromInt(eq.width * eq.height);

                for (0..lut.slice().len) |i| {
                    const ant = blk: {
                        if (i == 0) {
                            break :blk std.mem.zeroes(LUTCollumns);
                        } else {
                            break :blk lut.get(i - 1);
                        }
                    };
                    var linha = lut.get(i);
                    linha.rk = @intCast(i);
                    linha.pr = @as(f64, @floatFromInt(linha.nk)) / total;
                    linha.fa = std.math.clamp(ant.fa + linha.pr, 0, 1);
                    linha.eq = @intFromFloat(@round(linha.fa * 255));
                    lut.set(i, linha);
                }

                for (eq_cor) |*cor| {
                    const ch = cor.toHSV();
                    const linha = lut.get(@intFromFloat(@round(ch.z * 255)));
                    const nova = rl.Color.fromHSV(ch.x, ch.y, @as(f32, @floatFromInt(linha.eq)) / 255);
                    cor.r = nova.r;
                    cor.g = nova.g;
                    cor.b = nova.b;
                }

                eq.data = eq_cor.ptr;
                eq.format = .uncompressed_r8g8b8a8;
                eq_tx = try rl.loadTextureFromImage(eq);
            }
        }

        if (rl.isMouseButtonDown(.left)) {
            camera.target.x -= rl.getMouseDelta().x * rl.getFrameTime() * 3000.0 * (1 / camera.zoom);
            camera.target.y -= rl.getMouseDelta().y * rl.getFrameTime() * 3000.0 * (1 / camera.zoom);
        }

        if (camera.zoom + rl.getMouseWheelMove() / 10 > 0) {
            camera.zoom += rl.getMouseWheelMove() / 10;
        }

        rl.beginDrawing();
        rl.beginMode2D(camera);
        defer rl.endDrawing();

        rl.clearBackground(.ray_white);

        if (og_tx) |_| {
            // Imagem original
            rl.drawText("Imagem original", 4, 4, 32, .black);
            rl.drawTexture(og_tx.?, 0, 64, .white);

            // Histograma equalizado
            rl.drawText("Equalização de histograma", 1 * (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(eq_tx.?, 1 * (og_tx.?.width + 64), 64, .white);
        } else {
            rl.drawText("Arraste uma imagem aqui para começar", 4, 4, 32, .black);
        }
        rl.endMode2D();
    }
}

fn grayscale(cores: *[]rl.Color) void {
    for (cores.*) |*cor| {
        const r: usize = @intCast(cor.r);
        const g: usize = @intCast(cor.g);
        const b: usize = @intCast(cor.b);

        const avg: u8 = @intCast((r + g + b) / 3);
        cor.*.r = avg;
        cor.*.g = avg;
        cor.*.b = avg;
    }
}
