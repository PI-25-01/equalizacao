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
var gr_tx: ?rl.Texture = null;
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
                var eq_cor = try rl.loadImageColors(eq);
                grayscale(&eq_cor);

                const gr = rl.imageCopy(eq);
                gr_tx = try rl.loadTextureFromImage(gr);

                for (eq_cor) |cor| {
                    var linha = lut.get(cor.b);
                    linha.nk += 1;
                    lut.set(cor.b, linha);
                }

                const total: f64 = @floatFromInt(eq.width * eq.height);

                for (0..lut.slice().len) |i| {
                    const ant = if (i == 0) null else lut.get(i);
                    var linha = lut.get(i);
                    linha.pr = @as(f64, @floatFromInt(linha.nk)) / total;
                    linha.fa += if (ant) |_| std.math.clamp(ant.?.pr + linha.fa, 0, 1) else linha.fa;
                    linha.eq = @intFromFloat(std.math.clamp(std.math.round(linha.fa / 256), 0, 255));
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

            // Tons de cinza
            rl.drawText("Tons de cinza", (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(eq_tx.?, (og_tx.?.width + 64), 64, .white);

            // Histograma equalizado
            rl.drawText("Equalização de histograma", 2 * (og_tx.?.width + 64), 4, 32, .black);
            rl.drawTexture(eq_tx.?, 2 * (og_tx.?.width + 64), 64, .white);
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
