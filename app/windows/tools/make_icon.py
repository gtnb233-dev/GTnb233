# -*- coding: utf-8 -*-
"""生成工程测量工具箱的 Windows 应用图标（纯 Python 标准库，多尺寸合法 .ico + PNG）。

图案：科技蓝渐变圆角底 (#3B82F6 → #1D4ED8) + 罗盘刻度外环 + 精密三角网标架 + 测站中心点。

输出（app/windows/runner/resources/）：
  app_icon.ico        16/32/48/64 用 32 位 BMP 条目、128/256 用 PNG 条目
  app_icon.png        512/1024 源图（与 Windows/Android 资源一致）
  app_icon_256.png    256 预览图

运行：python make_icon.py
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "runner" / "resources"

BMP_SIZES = (16, 32, 48, 64)
PNG_SIZES = (128, 256)
ALL_SIZES = tuple(sorted(BMP_SIZES + PNG_SIZES))

# 科技蓝渐变色板（与桌面端主题 kSeed #2F6FED / #3B82F6 → #1D4ED8 统一）
BLUE_TOP_LEFT = (59.0, 130.0, 246.0)     # #3B82F6
BLUE_MID = (37.0, 99.0, 235.0)           # #2563EB
BLUE_BOT_RIGHT = (29.0, 78.0, 216.0)     # #1D4ED8


def _clamp01(v: float) -> float:
    return 0.0 if v <= 0.0 else (1.0 if v >= 1.0 else v)


def _smooth_alpha(sdf_px: float) -> float:
    """将像素单位的有符号距离平滑为 [0, 1] 覆盖率。"""
    return _clamp01(0.5 - sdf_px)


def _sd_round_box(px: float, py: float, bx: float, by: float, r: float) -> float:
    qx = abs(px) - bx + r
    qy = abs(py) - by + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def _dist_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx = bx - ax
    dy = by - ay
    denom = dx * dx + dy * dy
    if denom <= 1e-12:
        return math.hypot(px - ax, py - ay)
    t = _clamp01(((px - ax) * dx + (py - ay) * dy) / denom)
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _blend(dst_r: float, dst_g: float, dst_b: float, dst_a: float,
           src_r: float, src_g: float, src_b: float, src_a: float) -> tuple[float, float, float, float]:
    out_a = src_a + dst_a * (1.0 - src_a)
    if out_a <= 1e-9:
        return (0.0, 0.0, 0.0, 0.0)
    out_r = (src_r * src_a + dst_r * dst_a * (1.0 - src_a)) / out_a
    out_g = (src_g * src_a + dst_g * dst_a * (1.0 - src_a)) / out_a
    out_b = (src_b * src_a + dst_b * dst_a * (1.0 - src_a)) / out_a
    return (out_r, out_g, out_b, out_a)


def render_rgba(size: int) -> bytes:
    """使用解析 SDF 在 size x size 画布生成 RGBA 字节流，边缘天然抗锯齿。"""
    inv = 1.0 / size
    min_stroke_uv = 1.15 * inv  # 16px 小尺寸下保持最少 ~1.15px 清晰度

    # 几何参数（归一化 [0, 1] 坐标，中心 (0.5, 0.5)）
    box_half = 0.468
    box_radius = 0.112

    ring_r = 0.305
    ring_w = max(0.013, min_stroke_uv * 0.72)

    tri_w = max(0.029, min_stroke_uv * 0.92)
    ax, ay = 0.500, 0.220
    bx, by = 0.258, 0.708
    cx, cy = 0.742, 0.708

    dot_cx, dot_cy = 0.500, 0.548
    dot_r = max(0.056, 1.3 * inv)

    tick_w = max(0.014, min_stroke_uv * 0.65)
    ticks = (
        (0.500, 0.125, 0.500, 0.185),  # N
        (0.875, 0.500, 0.815, 0.500),  # E
        (0.500, 0.875, 0.500, 0.815),  # S
        (0.125, 0.500, 0.185, 0.500),  # W
    )

    buf = bytearray(size * size * 4)
    idx = 0
    for y in range(size):
        v = (y + 0.5) * inv
        dy_c = v - 0.5
        for x in range(size):
            u = (x + 0.5) * inv
            dx_c = u - 0.5

            # 1. 圆角底 SDF（换算为像素距离以平滑边缘）
            sd_bg = _sd_round_box(dx_c, dy_c, box_half, box_half, box_radius) * size
            bg_alpha = _smooth_alpha(sd_bg)
            if bg_alpha <= 0.001:
                buf[idx] = 0
                buf[idx + 1] = 0
                buf[idx + 2] = 0
                buf[idx + 3] = 0
                idx += 4
                continue

            # 对角科技蓝渐变 + 左上柔和径向高光
            gt = _clamp01(0.45 * u + 0.55 * v)
            if gt < 0.5:
                k = gt * 2.0
                br = BLUE_TOP_LEFT[0] + (BLUE_MID[0] - BLUE_TOP_LEFT[0]) * k
                bg_c = BLUE_TOP_LEFT[1] + (BLUE_MID[1] - BLUE_TOP_LEFT[1]) * k
                bb = BLUE_TOP_LEFT[2] + (BLUE_MID[2] - BLUE_TOP_LEFT[2]) * k
            else:
                k = (gt - 0.5) * 2.0
                br = BLUE_MID[0] + (BLUE_BOT_RIGHT[0] - BLUE_MID[0]) * k
                bg_c = BLUE_MID[1] + (BLUE_BOT_RIGHT[1] - BLUE_MID[1]) * k
                bb = BLUE_MID[2] + (BLUE_BOT_RIGHT[2] - BLUE_MID[2]) * k

            glow = math.exp(-((u - 0.30) ** 2 + (v - 0.24) ** 2) / 0.16) * 26.0
            r = min(255.0, br + glow)
            g = min(255.0, bg_c + glow)
            b = min(255.0, bb + glow * 0.6)
            a = bg_alpha

            # 内描边高光（仅在 64px 以上呈现细腻玻璃边缘）
            if size >= 48:
                rim_sd = abs(sd_bg + 1.2) - 0.75
                rim_a = _smooth_alpha(rim_sd) * 0.18 * bg_alpha
                if rim_a > 0.002:
                    r, g, b, a = _blend(r, g, b, a, 255.0, 255.0, 255.0, rim_a)

            # 2. 罗盘参考圆环（浅白半透明）
            d_ring = (abs(math.hypot(dx_c, dy_c) - ring_r) - ring_w) * size
            ring_a = _smooth_alpha(d_ring) * 0.30 * bg_alpha
            if ring_a > 0.002:
                r, g, b, a = _blend(r, g, b, a, 255.0, 255.0, 255.0, ring_a)

            # 3. 四向精密分划刻度
            d_tick = min(
                _dist_segment(u, v, x0, y0, x1, y1) for (x0, y0, x1, y1) in ticks
            )
            tick_a = _smooth_alpha((d_tick - tick_w) * size) * 0.72 * bg_alpha
            if tick_a > 0.002:
                r, g, b, a = _blend(r, g, b, a, 255.0, 255.0, 255.0, tick_a)

            # 4. 精密三角测量标架（纯白圆角三角形）
            d_tri = min(
                _dist_segment(u, v, ax, ay, bx, by),
                _dist_segment(u, v, bx, by, cx, cy),
                _dist_segment(u, v, cx, cy, ax, ay),
            )
            tri_a = _smooth_alpha((d_tri - tri_w) * size) * 0.98 * bg_alpha
            if tri_a > 0.002:
                r, g, b, a = _blend(r, g, b, a, 255.0, 255.0, 255.0, tri_a)

            # 5. 中心测站点（纯白实心点 + 微弱暗蓝对比环突出锐利度）
            d_center = math.hypot(u - dot_cx, v - dot_cy)
            dot_a = _smooth_alpha((d_center - dot_r) * size) * bg_alpha
            if dot_a > 0.002:
                r, g, b, a = _blend(r, g, b, a, 255.0, 255.0, 255.0, dot_a)

            buf[idx] = max(0, min(255, int(round(r))))
            buf[idx + 1] = max(0, min(255, int(round(g))))
            buf[idx + 2] = max(0, min(255, int(round(b))))
            buf[idx + 3] = max(0, min(255, int(round(a * 255.0))))
            idx += 4
    return bytes(buf)


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

    master_size = 512
    master_rgba = render_rgba(master_size)
    (OUT_DIR / "app_icon.png").write_bytes(encode_png(master_size, master_rgba))

    frames = {s: render_rgba(s) for s in ALL_SIZES}
    (OUT_DIR / "app_icon_256.png").write_bytes(encode_png(256, frames[256]))

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

    app_dir = OUT_DIR.parents[2]
    android_res = app_dir / "android" / "app" / "src" / "main" / "res"
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
            target.write_bytes(encode_png(sz, render_rgba(sz)))
            print(f"mipmap: {folder}/ic_launcher.png {sz}x{sz}")
    else:
        print(f"skip android: {android_res} 不存在")
    return 0


if __name__ == "__main__":
    sys.exit(main())
