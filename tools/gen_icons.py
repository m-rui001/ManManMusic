#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 logo.jpg 生成全平台 App 图标 / 应用内 logo / 启动图。

用法（在项目根目录执行）：
    python tools/gen_icons.py [源图片路径]

默认源图片：logo.jpg；默认输出：assets/logo.png + assets/ic_launch.png
以及 android / ios / macos / windows / web 五端图标。

依赖：pip install pillow
"""

import io
import os
import re
import sys

# Windows 控制台默认 GBK，统一走 UTF-8 输出
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, sys.argv[1] if len(sys.argv) > 1 else "logo.jpg")

# 图标兜底背景色（与 logo 边缘平均色一致，用于自适应图标背景 / maskable 图标）
BG = (0xCF, 0xC4, 0xAA)
# 旧版 Android / 桌面端图标的圆角比例
CORNER_RATIO = 0.22


def load_square(size):
    """读取源图并裁剪成正方形，返回正方形的 RGB 图。"""
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    if w != h:
        side = min(w, h)
        im = im.crop(
            ((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side)
        )
    return im


def rounded(im, radius_ratio=CORNER_RATIO):
    """加圆角（返回 RGBA）。"""
    size = im.size[0]
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * 4 - 1, size * 4 - 1),
        radius=int(size * 4 * radius_ratio),
        fill=255,
    )
    mask = mask.resize((size, size), Image.LANCZOS)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def save(im, path, mode=None):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if mode is not None:
        im = im.convert(mode)
    im.save(path, optimize=True)
    print(f"  {path}  {im.size[0]}x{im.size[1]} {im.mode}")


def make(size):
    """生成指定尺寸的正方形原图（RGB）。"""
    return load_square(size).resize((size, size), Image.LANCZOS)


def main():
    if not os.path.exists(SRC):
        sys.exit(f"找不到源图片：{SRC}")

    print(f"源图片：{SRC}")
    print("\n[1/7] 应用内 logo / 窗口图标")

    # 应用内展示 + 桌面窗口图标（setting.dart / window_manage.dart 引用 ic_launch.png）
    save(make(1600), "assets/ic_launch.png")
    save(make(1024), "assets/logo.png")

    print("\n[2/7] Android")
    # 旧版（Android < 8）图标：圆角方形
    android_legacy = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for dpi, size in android_legacy.items():
        icon = rounded(make(size))
        save(icon, f"android/app/src/main/res/mipmap-{dpi}/launcher_icon.png")
        save(icon, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher.png")

    # 自适应图标前景（Android >= 8）：108dp 画布，可见区域只有中间约 72dp 的圆形/圆角方形，
    # 所以把图片缩到画布的 72% 居中放置，外围透明交给背景色，避免被各厂商遮罩裁掉画面
    android_fg = {
        "mdpi": 108,
        "hdpi": 162,
        "xhdpi": 216,
        "xxhdpi": 324,
        "xxxhdpi": 432,
    }
    for dpi, canvas in android_fg.items():
        inner = int(round(canvas * 0.72))
        fg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        pic = rounded(make(inner))
        off = (canvas - inner) // 2
        fg.paste(pic, (off, off), pic)
        save(fg, f"android/app/src/main/res/drawable-{dpi}/ic_launcher_foreground.png")

    print("\n[3/7] iOS")
    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name in sorted(os.listdir(os.path.join(ROOT, ios_dir))):
        m = re.match(r"Icon-App-([\d.]+)x([\d.]+)@(\d)x\.png$", name)
        if not m:
            continue
        size = int(round(float(m.group(1)) * int(m.group(3))))
        # iOS 图标不允许带 alpha 通道
        save(make(size), f"{ios_dir}/{name}", mode="RGB")

    print("\n[4/7] macOS")
    macos_dir = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name in sorted(os.listdir(os.path.join(ROOT, macos_dir))):
        m = re.match(r"app_icon_(\d+)\.png$", name)
        if not m:
            continue
        save(make(int(m.group(1))).convert("RGBA"), f"{macos_dir}/{name}")

    print("\n[5/7] Windows")
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    ico_path = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
    make(256).save(ico_path, format="ICO", sizes=ico_sizes)
    print(f"  {ico_path}  " + ", ".join(f"{w}x{h}" for w, h in ico_sizes))

    print("\n[6/7] Web")
    save(make(48), "web/favicon.png", mode="RGBA")
    save(make(192), "web/icons/Icon-192.png", mode="RGBA")
    save(make(512), "web/icons/Icon-512.png", mode="RGBA")
    # maskable 图标需要留安全边距（约 10%），否则会被裁掉边缘
    for size in (192, 512):
        canvas = Image.new("RGB", (size, size), BG)
        inner = int(size * 0.8)
        canvas.paste(make(inner), ((size - inner) // 2, (size - inner) // 2))
        save(canvas, f"web/icons/Icon-maskable-{size}.png", mode="RGBA")

    # 自适应图标背景色跟随 logo 边缘平均色，避免露出一圈黑边
    color_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n' % BG
        + '</resources>\n'
    )
    with open(
        os.path.join(ROOT, "android/app/src/main/res/values/colors.xml"),
        "w",
        encoding="utf-8",
    ) as f:
        f.write(color_xml)
    print("  android/app/src/main/res/values/colors.xml  背景色 #%02X%02X%02X" % BG)

    print("\n[7/7] 校验 flutter_launcher_icons.yaml 配置")
    yaml_path = os.path.join(ROOT, "flutter_launcher_icons.yaml")
    with open(yaml_path, encoding="utf-8") as f:
        text = f.read()
    if "assets/ic_launch.png" not in text:
        print("  提示：flutter_launcher_icons.yaml 未指向 assets/ic_launch.png，可手动确认")
    else:
        print("  OK：flutter_launcher_icons.yaml 已指向 assets/ic_launch.png")

    print("\n全部图标生成完成 ✅")


if __name__ == "__main__":
    main()
