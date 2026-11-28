"""Generate Survey GT icons for Windows, Android and the README from the K vector."""
from __future__ import annotations

import math
import re
import struct
import sys
import zlib
from pathlib import Path
from xml.etree import ElementTree

APP_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = APP_DIR / "windows" / "runner" / "resources"
DOCS_IMAGES = APP_DIR.parent / "docs" / "screenshots"
SVG_NS = "{http://www.w3.org/2000/svg}"

BMP_SIZES = (16, 32, 48, 64)
PNG_SIZES = (128, 256)
ALL_SIZES = tuple(sorted(BMP_SIZES + PNG_SIZES))

def load_icon():
    svg = ElementTree.parse(DOCS_IMAGES / "app_icon.svg").getroot()
    _, _, width, height = map(int, svg.attrib["viewBox"].split())
    if width != height or svg.attrib["viewBox"] != f"0 0 {width} {height}":
        raise ValueError("Expected a square icon with its origin at (0, 0).")

    background, *paths = svg
    if (
        background.tag != SVG_NS + "rect"
        or background.get("width") != str(width)
        or background.get("height") != str(height)
    ):
        raise ValueError("Expected a full-bleed background rectangle.")

    colors = [bytes.fromhex(background.attrib["fill"].removeprefix("#"))]
    polygons = []
    for path in paths:
        data = path.attrib["d"]
        if path.tag != SVG_NS + "path" or not re.fullmatch(
            r"M \d+ \d+(?: L \d+ \d+){2,} Z", data
        ):
            raise ValueError("Expected a closed polygon made of M/L/Z commands.")
        coords = list(map(int, re.findall(r"\d+", data)))
        polygons.append(list(zip(coords[::2], coords[1::2])))
        colors.append(bytes.fromhex(path.attrib["fill"].removeprefix("#")))
    return width, colors, polygons


def render_rgba(size: int, icon) -> bytes:
    """Rasterize the supplied filled polygons at 4× for antialiased edges."""
    width, colors, polygons = icon
    samples = 4
    grid = size * samples
    scale = grid / width
    canvas = bytearray(grid * grid)
    for color, polygon in enumerate(polygons, start=1):
        points = [(x * scale, y * scale) for x, y in polygon]
        edges = list(zip(points, points[1:] + points[:1]))
        first = max(0, math.floor(min(y for _, y in points)))
        last = min(grid, math.ceil(max(y for _, y in points)))
        for row in range(first, last):
            y = row + 0.5
            intersections = sorted(
                x0 + (y - y0) * (x1 - x0) / (y1 - y0)
                for (x0, y0), (x1, y1) in edges
                if min(y0, y1) <= y < max(y0, y1)
            )
            for left, right in zip(intersections[::2], intersections[1::2]):
                lo = max(0, math.ceil(left - 0.5))
                hi = min(grid, math.ceil(right - 0.5))
                canvas[row * grid + lo : row * grid + hi] = bytes([color]) * (hi - lo)

    rgba = bytearray()
    for row in range(0, grid, samples):
        rows = [canvas[y * grid : (y + 1) * grid] for y in range(row, row + samples)]
        for col in range(0, grid, samples):
            red = green = blue = 0
            for scanline in rows:
                for color in scanline[col : col + samples]:
                    r, g, b = colors[color]
                    red += r
                    green += g
                    blue += b
            coverage = samples * samples
            rgba.extend((red // coverage, green // coverage, blue // coverage, 255))
    return bytes(rgba)


def encode_png(size: int, rgba: bytes) -> bytes:
    """将 size x size RGBA 字节编码为标准 32 位 PNG。"""
    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    stride = size * 4
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter type 0 (None)
        raw.extend(rgba[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), level=9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def _bmp_entry(size: int, rgba: bytes) -> bytes:
    """32 位 BMP（BITMAPINFOHEADER + BGRA 倒序像素 + 1bpp AND 掩码）。"""
    rows = bytearray()
    row_bytes = size * 4
    for y in range(size - 1, -1, -1):
        start = y * row_bytes
        for x in range(size):
            p = start + x * 4
            r, g, b, a = rgba[p], rgba[p + 1], rgba[p + 2], rgba[p + 3]
            rows.extend((b, g, r, a))
    stride = ((size + 31) // 32) * 4
    and_mask = (b"\x00" * stride) * size
    header = struct.pack(
        "<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, len(rows) + len(and_mask), 0, 0, 0, 0
    )
    return header + bytes(rows) + and_mask


def build_ico(frames: dict[int, bytes]) -> bytes:
    payloads: list[tuple[int, bytes]] = []
    for size in sorted(frames):
        rgba = frames[size]
        payloads.append(
            (size, _bmp_entry(size, rgba) if size in BMP_SIZES else encode_png(size, rgba))
        )

    count = len(payloads)
    out = bytearray(struct.pack("<HHH", 0, 1, count))
    offset = 6 + 16 * count
    body = bytearray()
    for size, data in payloads:
        dim = 0 if size >= 256 else size
        out += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        body += data
    return bytes(out + body)


def validate_ico(path: Path) -> list[int]:
    """手工解析 ICO 头与全部目录项；任何不一致直接抛异常。"""
    data = path.read_bytes()
    total = len(data)
    if total < 6:
        raise ValueError("文件过短")
    reserved, typ, count = struct.unpack_from("<HHH", data, 0)
    if reserved != 0 or typ != 1 or count == 0:
        raise ValueError(f"ICO 头非法: reserved={reserved}, type={typ}, count={count}")
    if 6 + count * 16 > total:
        raise ValueError("目录项长度超出文件")
    sizes = []
    for i in range(count):
        w, h, colors, res, planes, bpp, nbytes, offset = struct.unpack_from(
            "<BBBBHHII", data, 6 + i * 16
        )
        w = 256 if w == 0 else w
        h = 256 if h == 0 else h
        if w != h or colors != 0 or res != 0 or planes != 1 or bpp != 32:
            raise ValueError(f"第 {i} 项目录参数异常")
        if nbytes == 0 or offset < 6 + 16 * count or offset + nbytes > total:
            raise ValueError(f"第 {i} 项数据区越界")
        payload = data[offset : offset + nbytes]
        if payload[:8] == b"\x89PNG\r\n\x1a\n":
            pw, ph = struct.unpack_from(">II", payload, 16)
            if (pw, ph) != (w, h):
                raise ValueError(f"第 {i} 项 PNG 尺寸 {pw}x{ph} != {w}x{h}")
        elif struct.unpack_from("<I", payload, 0)[0] == 40:
            bi_w, bi_h = struct.unpack_from("<ii", payload, 4)
            if (bi_w, bi_h) != (w, h * 2):
                raise ValueError(f"第 {i} 项 DIB 尺寸 {bi_w}x{bi_h} != {w}x{h * 2}")
        else:
            raise ValueError(f"第 {i} 项既不是 PNG 也不是 32 位 DIB")
        sizes.append(w)
    return sizes


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    icon = load_icon()
    master_size = 512
    master_rgba = render_rgba(master_size, icon)
    (OUT_DIR / "app_icon.png").write_bytes(encode_png(master_size, master_rgba))

    frames = {s: render_rgba(s, icon) for s in ALL_SIZES}
    preview = encode_png(256, frames[256])
    (OUT_DIR / "app_icon_256.png").write_bytes(preview)
    (DOCS_IMAGES / "app_icon_256.png").write_bytes(preview)

    ico = OUT_DIR / "app_icon.ico"
    ico.write_bytes(build_ico(frames))

    sizes_found = validate_ico(ico)
    print(f"ico  : {ico}  {ico.stat().st_size} bytes")
    print(f"png  : {OUT_DIR / 'app_icon.png'}  {master_size}x{master_size}")
    print(f"png  : {OUT_DIR / 'app_icon_256.png'}  256x256")
    print(f"sizes: {sizes_found}")
    missing = set(ALL_SIZES) - set(sizes_found)
    if missing:
        raise SystemExit(f"缺少尺寸: {sorted(missing)}")
    print("header ok: reserved=0 type=1 planes=1 bpp=32，全部数据区在文件内")

    android_res = APP_DIR / "android" / "app" / "src" / "main" / "res"
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    if android_res.is_dir():
        for folder, sz in densities.items():
            target = android_res / folder / "ic_launcher.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(encode_png(sz, render_rgba(sz, icon)))
            print(f"mipmap: {folder}/ic_launcher.png {sz}x{sz}")
    else:
        print(f"skip android: {android_res} 不存在")
    return 0


if __name__ == "__main__":
    sys.exit(main())
