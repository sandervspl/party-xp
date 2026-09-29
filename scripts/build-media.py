"""Build the small, dependency-free textures and addon icon used by Party XP."""

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


def icon(x, y):
    """Three party portraits with XP bars, legible at AddOns-list size."""
    background = (12, 25 + y // 12, 39 + y // 10)
    color = background

    def blend(foreground, amount):
        return tuple(round(back * (1 - amount) + front * amount) for back, front in zip(color, foreground))

    # A thin gold frame identifies the image at small sizes.
    edge = min(x, y, 127 - x, 127 - y)
    if edge < 3:
        color = (179, 137, 66)
    elif edge < 6:
        color = (35, 48, 53)

    for center_y, progress, fill in (
        (35, 57, (94, 183, 106)),
        (64, 43, (108, 157, 220)),
        (93, 28, (203, 159, 75)),
    ):
        distance = ((x - 27) ** 2 + (y - center_y) ** 2) ** 0.5
        if distance < 13:
            color = (193, 157, 87)
        if distance < 10:
            color = (58, 77, 86)
        if distance < 6:
            color = fill

        if 44 <= x < 111 and center_y - 10 <= y < center_y + 11:
            color = (160, 132, 77)
        if 47 <= x < 108 and center_y - 7 <= y < center_y + 8:
            color = (18, 31, 39)
        if 48 <= x < 48 + progress and center_y - 5 <= y < center_y + 6:
            color = fill
        if 48 <= x < 48 + progress and center_y - 5 <= y < center_y - 3:
            color = blend((255, 255, 255), 0.25)

    return (*color, 255)


def main():
    MEDIA.mkdir(exist_ok=True)
    for aspect in (1, 2, 4, 8, 16, 32):
        write_tga(MEDIA / f"Rounded-{aspect}.tga", HEIGHT * aspect, HEIGHT, rounded_mask(HEIGHT * aspect))
    write_tga(MEDIA / "Flat.tga", 128, HEIGHT, lambda x, y: (255, 255, 255, 255))
    write_tga(MEDIA / "Gloss.tga", 128, HEIGHT, gloss)
    write_tga(MEDIA / "Striped.tga", 128, HEIGHT, striped)
    write_tga(MEDIA / "icon.tga", 128, 128, icon)


if __name__ == "__main__":
    main()
