"""Build the small, dependency-free textures used by Party XP bars."""

from pathlib import Path
import struct


MEDIA = Path(__file__).resolve().parent.parent / "Media"
HEIGHT = 16
SAMPLES = 4


def write_tga(path, width, height, pixel):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with path.open("wb") as image:
        image.write(header)
        for y in range(height):
            for x in range(width):
                red, green, blue, alpha = pixel(x, y)
                image.write(bytes((blue, green, red, alpha)))


def rounded_mask(width):
    radius = HEIGHT / 2

    def pixel(x, y):
        inside = 0
        for sy in range(SAMPLES):
            py = y + (sy + 0.5) / SAMPLES
            for sx in range(SAMPLES):
                px = x + (sx + 0.5) / SAMPLES
                nearest_x = min(max(px, radius), width - radius)
                nearest_y = min(max(py, radius), HEIGHT - radius)
                if (px - nearest_x) ** 2 + (py - nearest_y) ** 2 <= radius ** 2:
                    inside += 1
        return 255, 255, 255, round(255 * inside / (SAMPLES * SAMPLES))

    return pixel


def gloss(x, y):
    if y < HEIGHT // 2:
        shade = 245 - 3 * y
    else:
        shade = 205 - 5 * (y - HEIGHT // 2)
    if y == 3:
        shade = 255
    return shade, shade, shade, 255


def striped(x, y):
    shade = 240 if (x + 2 * y) % 20 < 10 else 155
    shade -= y // 3
    return shade, shade, shade, 255


def main():
    MEDIA.mkdir(exist_ok=True)
    for aspect in (1, 2, 4, 8, 16, 32):
        write_tga(MEDIA / f"Rounded-{aspect}.tga", HEIGHT * aspect, HEIGHT, rounded_mask(HEIGHT * aspect))
    write_tga(MEDIA / "Flat.tga", 128, HEIGHT, lambda x, y: (255, 255, 255, 255))
    write_tga(MEDIA / "Gloss.tga", 128, HEIGHT, gloss)
    write_tga(MEDIA / "Striped.tga", 128, HEIGHT, striped)


if __name__ == "__main__":
    main()
