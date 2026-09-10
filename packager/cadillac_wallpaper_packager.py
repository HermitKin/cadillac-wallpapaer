#!/usr/bin/env python3
"""Build a tested Cadillac OTA wallpaper package from PNG or JPEG images."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import shutil
import struct
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parent
DEFAULT_INPUT_ZIP = PROJECT_ROOT / "templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip"
DEFAULT_ASTCENC = PROJECT_ROOT / "tools/macos/astcenc"
DEFAULT_LIGHT_DIM_MASK = PROJECT_ROOT / "masks/light_dim_alpha_fixed_smoothed_used.png"
DEFAULT_DARK_DIM_MASK = PROJECT_ROOT / "masks/dark_dim_alpha_fixed_smoothed_used.png"

PREVIEW_SIZE = (2198, 367)
VCD_SIZE = (3950, 1320)
RID_SIZE = (1920, 1080)
PNG_TARGET_SIZES = {
    "vcd/wallpaper/light_wallpaper_vcd.png": VCD_SIZE,
    "vcd/wallpaper/dark_wallpaper_vcd.png": VCD_SIZE,
    "rid/screenSaver/light_screenSaver_rid.png": RID_SIZE,
    "rid/screenSaver/dark_screenSaver_rid.png": RID_SIZE,
    "light_dim_background.png": VCD_SIZE,
    "dark_dim_background.png": VCD_SIZE,
    "light_preview_image.png": PREVIEW_SIZE,
    "dark_preview_image.png": PREVIEW_SIZE,
}
PREVIEW_TARGETS = {"light_preview_image.png", "dark_preview_image.png"}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
FACTORY_PNG_CHUNKS = {b"pHYs", b"sRGB", b"gAMA"}


def redact_text(value: Any) -> str:
    text = str(value)
    home = str(Path.home())
    if home and home != "/":
        text = text.replace(home, "<HOME>")
    text = re.sub(r"/(Users|home)/[^/\s\"<>]+", "<HOME>", text)
    text = re.sub(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"<>]+", "<HOME>", text)
    text = re.sub(r"/var/folders/[^\s\"<>]+", "<TEMP>", text)
    return text


def redacted_path(path: Path) -> str:
    try:
        return redact_text(path.expanduser().resolve())
    except Exception:
        return redact_text(path)


def progress(message: str) -> None:
    print(f"[cadillac-packager] {redact_text(message)}", flush=True)


def load_runtime_dependencies() -> None:
    global Image, ImageChops, ImageFilter, ImageOps, ImageStat, kzb
    from PIL import Image as pil_image
    from PIL import ImageChops as pil_image_chops
    from PIL import ImageFilter as pil_image_filter
    from PIL import ImageOps as pil_image_ops
    from PIL import ImageStat as pil_image_stat

    import kzb_astc_patcher as kzb_module

    Image = pil_image
    ImageChops = pil_image_chops
    ImageFilter = pil_image_filter
    ImageOps = pil_image_ops
    ImageStat = pil_image_stat
    kzb = kzb_module


@dataclass(frozen=True)
class ThemeRule:
    label: str
    preview_path: str
    vcd_path: str
    rid_path: str
    dim_path: str
    vcd_crop: tuple[int, int, int, int]
    rid_crop: tuple[int, int, int, int]
    dim_blur_radius: float
    dim_overlay_rgb: tuple[int, int, int]


@dataclass(frozen=True)
class CanvasAdjustment:
    """User-controlled crop matching the web generator's 8960x1320 canvas."""

    zoom: float = 1.0
    scale_x: float = 1.0
    scale_y: float = 1.0
    offset_x: float = 0.0
    offset_y: float = 0.0
    rotation: float = 0.0


THEME_RULES = {
    "light": ThemeRule(
        label="light",
        preview_path="light_preview_image.png",
        vcd_path="vcd/wallpaper/light_wallpaper_vcd.png",
        rid_path="rid/screenSaver/light_screenSaver_rid.png",
        dim_path="light_dim_background.png",
        vcd_crop=(1256, 48, 2196, 362),
        rid_crop=(904, 48, 1441, 350),
        dim_blur_radius=48,
        dim_overlay_rgb=(232, 242, 250),
    ),
    "dark": ThemeRule(
        label="dark",
        preview_path="dark_preview_image.png",
        vcd_path="vcd/wallpaper/dark_wallpaper_vcd.png",
        rid_path="rid/screenSaver/dark_screenSaver_rid.png",
        dim_path="dark_dim_background.png",
        vcd_crop=(1260, 20, 2200, 334),
        rid_crop=(872, 8, 1494, 358),
        dim_blur_radius=32,
        dim_overlay_rgb=(0, 0, 0),
    ),
}


def md5_bytes(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def md5_image_channel(channel: Image.Image) -> str:
    return hashlib.md5(channel.tobytes()).hexdigest()


def load_source_image(path: Path, label: str) -> Image.Image:
    """Load any Pillow-supported image, apply EXIF rotation, and ignore alpha."""
    if not path.exists():
        raise FileNotFoundError(path)
    with Image.open(path) as image:
        source = ImageOps.exif_transpose(image).convert("RGBA")
    if source.width < 1 or source.height < 1:
        raise ValueError(f"{label} image has an invalid size {source.size}: {path}")

    rgb = source.convert("RGB")
    opaque = Image.new("L", source.size, 255)
    return Image.merge("RGBA", (*rgb.split(), opaque))


def prepare_full_texture(
    source: Image.Image,
    adjustment: CanvasAdjustment,
) -> Image.Image:
    """Render one native canvas with web-style zoom/stretch/position controls.

    The base transform is cover-fit, exactly like the reference editor. When
    the user zooms out to preserve a complete subject, a blurred cover copy of
    the same source fills the exposed canvas without stretching the foreground.
    """
    zoom = max(0.05, min(4.0, adjustment.zoom))
    scale_x = max(0.25, min(4.0, adjustment.scale_x))
    scale_y = max(0.25, min(4.0, adjustment.scale_y))
    rotation = max(-180.0, min(180.0, adjustment.rotation))
    base_scale = max(
        kzb.KZB_TEXTURE_WIDTH / source.width,
        kzb.KZB_TEXTURE_HEIGHT / source.height,
    )
    width = max(1, round(source.width * base_scale * zoom * scale_x))
    height = max(1, round(source.height * base_scale * zoom * scale_y))
    source_rgba = source.convert("RGBA")
    if source_rgba.size == (width, height):
        # Native-size images with the default crop pass through without a
        # resampling step, preserving every RGB pixel from the selected area.
        rendered = source_rgba.copy()
    else:
        rendered = source_rgba.resize(
            (width, height), Image.Resampling.LANCZOS
        )
    if abs(rotation) > 0.0001:
        # Flutter's positive rotation is visually clockwise because screen Y
        # grows downward; Pillow uses positive counter-clockwise degrees.
        rendered = rendered.rotate(
            -rotation,
            resample=Image.Resampling.BICUBIC,
            expand=True,
            fillcolor=(0, 0, 0, 0),
        )
    rendered_width, rendered_height = rendered.size
    left = round(
        (kzb.KZB_TEXTURE_WIDTH - rendered_width) / 2
        + adjustment.offset_x * kzb.KZB_TEXTURE_WIDTH
    )
    top = round(
        (kzb.KZB_TEXTURE_HEIGHT - rendered_height) / 2
        + adjustment.offset_y * kzb.KZB_TEXTURE_HEIGHT
    )
    fully_covers = (
        abs(rotation) <= 0.0001
        and
        left <= 0
        and top <= 0
        and left + rendered_width >= kzb.KZB_TEXTURE_WIDTH
        and top + rendered_height >= kzb.KZB_TEXTURE_HEIGHT
    )
    if fully_covers:
        output = rendered.crop(
            (
                -left,
                -top,
                -left + kzb.KZB_TEXTURE_WIDTH,
                -top + kzb.KZB_TEXTURE_HEIGHT,
            )
        )
    else:
        # A portrait or ordinary photo cannot geometrically fill a 224:33
        # canvas while keeping the whole subject. Use a blurred cover copy as
        # the extension background, then place the sharp, undistorted source
        # above it at the user's scale and position.
        background_scale = max(
            kzb.KZB_TEXTURE_WIDTH / source.width,
            kzb.KZB_TEXTURE_HEIGHT / source.height,
        )
        background_width = max(1, round(source.width * background_scale))
        background_height = max(1, round(source.height * background_scale))
        background_large = source_rgba.resize(
            (background_width, background_height),
            Image.Resampling.LANCZOS,
        )
        background_left = (background_width - kzb.KZB_TEXTURE_WIDTH) // 2
        background_top = (background_height - kzb.KZB_TEXTURE_HEIGHT) // 2
        output = background_large.crop(
            (
                background_left,
                background_top,
                background_left + kzb.KZB_TEXTURE_WIDTH,
                background_top + kzb.KZB_TEXTURE_HEIGHT,
            )
        ).filter(ImageFilter.GaussianBlur(radius=42))

        destination_left = max(0, left)
        destination_top = max(0, top)
        destination_right = min(kzb.KZB_TEXTURE_WIDTH, left + rendered_width)
        destination_bottom = min(kzb.KZB_TEXTURE_HEIGHT, top + rendered_height)
        if destination_right > destination_left and destination_bottom > destination_top:
            foreground = rendered.crop(
                (
                    destination_left - left,
                    destination_top - top,
                    destination_right - left,
                    destination_bottom - top,
                )
            )
            output.alpha_composite(
                foreground,
                (destination_left, destination_top),
            )
    rgb = output.convert("RGB")
    return Image.merge(
        "RGBA",
        (*rgb.split(), Image.new("L", output.size, 255)),
    )


def crop_with_edge_pad(
    image: Image.Image,
    bbox: tuple[int, int, int, int],
) -> Image.Image:
    """Crop a bbox, repeating edge pixels when the bbox exceeds image bounds."""
    left, top, right, bottom = bbox
    pad_left = max(0, -left)
    pad_top = max(0, -top)
    pad_right = max(0, right - image.width)
    pad_bottom = max(0, bottom - image.height)
    source = image.convert("RGBA")

    if any((pad_left, pad_top, pad_right, pad_bottom)):
        width, height = source.size
        padded = Image.new(
            "RGBA",
            (width + pad_left + pad_right, height + pad_top + pad_bottom),
        )
        padded.paste(source, (pad_left, pad_top))
        if pad_top:
            padded.paste(
                source.crop((0, 0, width, 1)).resize((width, pad_top)),
                (pad_left, 0),
            )
        if pad_bottom:
            padded.paste(
                source.crop((0, height - 1, width, height)).resize((width, pad_bottom)),
                (pad_left, pad_top + height),
            )
        if pad_left:
            padded.paste(
                padded.crop((pad_left, 0, pad_left + 1, padded.height)).resize(
                    (pad_left, padded.height)
                ),
                (0, 0),
            )
        if pad_right:
            padded.paste(
                padded.crop(
                    (pad_left + width - 1, 0, pad_left + width, padded.height)
                ).resize((pad_right, padded.height)),
                (pad_left + width, 0),
            )
        source = padded
        left += pad_left
        right += pad_left
        top += pad_top
        bottom += pad_top

    return source.crop((left, top, right, bottom))


def resized_crop(
    master: Image.Image,
    bbox: tuple[int, int, int, int],
    target_size: tuple[int, int],
    sharpen: bool,
) -> Image.Image:
    resized = crop_with_edge_pad(master, bbox).resize(target_size, Image.Resampling.LANCZOS)
    if sharpen:
        resized = resized.filter(ImageFilter.UnsharpMask(radius=0.8, percent=130, threshold=2))
    alpha = Image.new("L", target_size, 255)
    rgb = resized.convert("RGB")
    return Image.merge("RGBA", (*rgb.split(), alpha))


def logical_bbox_to_texture_bbox(
    rule: ThemeRule,
    bbox: tuple[int, int, int, int],
) -> tuple[float, float, float, float]:
    """Map legacy 2198x367 preview coordinates onto the 8960x1320 texture."""
    vcd_left, vcd_top, vcd_right, vcd_bottom = rule.vcd_crop
    logical_per_texture_x = (vcd_right - vcd_left) / VCD_SIZE[0]
    logical_per_texture_y = (vcd_bottom - vcd_top) / VCD_SIZE[1]
    full_left = vcd_left - kzb.KZB_VCD_JOIN_X * logical_per_texture_x
    full_top = float(vcd_top)
    full_right = float(vcd_right)
    full_bottom = float(vcd_bottom)
    scale_x = kzb.KZB_TEXTURE_WIDTH / (full_right - full_left)
    scale_y = kzb.KZB_TEXTURE_HEIGHT / (full_bottom - full_top)
    left, top, right, bottom = bbox
    return (
        (left - full_left) * scale_x,
        (top - full_top) * scale_y,
        (right - full_left) * scale_x,
        (bottom - full_top) * scale_y,
    )


def sample_full_texture(
    full_texture: Image.Image,
    rule: ThemeRule,
    logical_bbox: tuple[int, int, int, int],
    target_size: tuple[int, int],
    sharpen: bool,
) -> Image.Image:
    """Render a template asset directly from the native 9K texture."""
    texture_bbox = logical_bbox_to_texture_bbox(rule, logical_bbox)
    padded, padded_bbox = kzb.edge_pad_for_bbox(
        full_texture.convert("RGBA"),
        texture_bbox,
    )
    sampled = padded.transform(
        target_size,
        Image.Transform.EXTENT,
        padded_bbox,
        Image.Resampling.BICUBIC,
    )
    if sharpen:
        sampled = sampled.filter(
            ImageFilter.UnsharpMask(radius=0.65, percent=115, threshold=2)
        )
    rgb = sampled.convert("RGB")
    alpha = Image.new("L", target_size, 255)
    return Image.merge("RGBA", (*rgb.split(), alpha))


def apply_preview_alpha(master: Image.Image, original_preview_bytes: bytes) -> Image.Image:
    with Image.open(io.BytesIO(original_preview_bytes)) as original:
        alpha = original.convert("RGBA").getchannel("A")
    if alpha.size != master.size:
        raise ValueError(
            f"preview master {master.size} does not match template alpha {alpha.size}"
        )
    result = master.convert("RGBA")
    result.putalpha(alpha)
    return result


def make_dim_background(
    vcd: Image.Image,
    mask_path: Path,
    rule: ThemeRule,
) -> Image.Image:
    if not mask_path.exists():
        raise FileNotFoundError(mask_path)
    with Image.open(mask_path) as mask_image:
        mask = mask_image.convert("L")
    if mask.size != VCD_SIZE:
        raise ValueError(f"{rule.label} dim mask must be {VCD_SIZE}, got {mask.size}")

    blurred = vcd.convert("RGBA").filter(ImageFilter.GaussianBlur(radius=rule.dim_blur_radius))
    overlay = Image.new("RGBA", VCD_SIZE, (*rule.dim_overlay_rgb, 0))
    overlay.putalpha(mask)
    composited = Image.alpha_composite(blurred, overlay)
    rgb = composited.convert("RGB")
    alpha = Image.new("L", VCD_SIZE, 255)
    return Image.merge("RGBA", (*rgb.split(), alpha))


def iter_png_chunks(data: bytes) -> list[tuple[bytes, bytes, bytes]]:
    """Return (type, payload, complete encoded chunk) tuples from a PNG."""
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("invalid PNG signature")
    chunks: list[tuple[bytes, bytes, bytes]] = []
    offset = len(PNG_SIGNATURE)
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG chunk")
        chunk_type = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        chunks.append((chunk_type, payload, data[offset:end]))
        offset = end
        if chunk_type == b"IEND":
            break
    if not chunks or chunks[-1][0] != b"IEND":
        raise ValueError("PNG is missing IEND")
    return chunks


def factory_png_chunks(data: bytes) -> list[bytes]:
    """Read the safe colour/physical metadata used by the factory PNG."""
    result: list[bytes] = []
    for chunk_type, payload, _ in iter_png_chunks(data):
        if chunk_type in FACTORY_PNG_CHUNKS:
            result.append(chunk_type)
        elif chunk_type == b"tEXt" and payload.startswith(b"Software\x00"):
            result.append(chunk_type)
    return result


def apply_factory_png_chunks(encoded: bytes, template: bytes) -> bytes:
    """Copy factory-safe PNG metadata without copying ICC, EXIF, or user text."""
    encoded_chunks = iter_png_chunks(encoded)
    template_chunks = iter_png_chunks(template)
    safe_chunks: list[bytes] = []
    for chunk_type, payload, raw in template_chunks:
        if chunk_type in FACTORY_PNG_CHUNKS:
            safe_chunks.append(raw)
        elif chunk_type == b"tEXt" and payload.startswith(b"Software\x00"):
            safe_chunks.append(raw)

    output = bytearray(PNG_SIGNATURE)
    output.extend(encoded_chunks[0][2])  # IHDR must remain first.
    for raw in safe_chunks:
        output.extend(raw)
    for _, _, raw in encoded_chunks[1:]:
        output.extend(raw)
    return bytes(output)


def png_bytes(image: Image.Image, template_png: bytes | None = None) -> bytes:
    # Do not inherit ICC/EXIF/text chunks from the user's source image. The IPD
    # side is encoded to ASTC, but VCD reads these PNGs directly and some vehicle
    # decoders reject large iCCP profiles, falling back to the stock background.
    rgba = image.convert("RGBA")
    clean = Image.frombytes("RGBA", rgba.size, rgba.tobytes())
    buffer = io.BytesIO()
    clean.save(buffer, format="PNG", optimize=True)
    encoded = buffer.getvalue()
    return (
        apply_factory_png_chunks(encoded, template_png)
        if template_png is not None
        else encoded
    )


def save_png(
    image: Image.Image,
    path: Path,
    template_png: bytes | None = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_bytes(image, template_png))


def derive_external_pngs(
    archive: zipfile.ZipFile,
    root: str,
    light_full_texture: Image.Image,
    dark_full_texture: Image.Image,
    work_dir: Path,
    light_dim_mask: Path,
    dark_dim_mask: Path,
    preview_blur: float,
    sharpen: bool,
) -> tuple[dict[str, bytes], dict[str, Any]]:
    full_textures = {
        "light": light_full_texture,
        "dark": dark_full_texture,
    }
    dim_masks = {"light": light_dim_mask, "dark": dark_dim_mask}
    replacements: dict[str, bytes] = {}
    report: dict[str, Any] = {}
    archive_names = set(archive.namelist())

    for label, rule in THEME_RULES.items():
        full_texture = full_textures[label]
        save_png(full_texture, work_dir / "full_textures" / f"{label}_8960x1320.png")

        preview_name = f"{root}/{rule.preview_path}"
        preview_template = archive.read(preview_name)
        with Image.open(io.BytesIO(preview_template)) as template_preview:
            preview_size = template_preview.size
        # Most templates use a 2198x367 UI preview, while C59D uses the native
        # 8960x1320 panorama. Preserve each package's own dimensions and alpha.
        preview_master = (
            full_texture.copy()
            if full_texture.size == preview_size
            else full_texture.resize(preview_size, Image.Resampling.LANCZOS)
        )
        save_png(
            preview_master,
            work_dir / "preview_masters" / f"{label}_preview_master.png",
        )

        preview_source = preview_master
        if preview_blur > 0:
            preview_source = preview_master.filter(
                ImageFilter.GaussianBlur(radius=preview_blur)
            )
        preview = (
            apply_preview_alpha(preview_source, preview_template)
            if preview_name in archive_names
            else None
        )
        # The external VCD is exactly the right-hand part of the 9K texture.
        # Keeping this as a direct crop preserves detail and the KZB/VCD seam.
        vcd = full_texture.crop(
            (
                kzb.KZB_VCD_JOIN_X,
                0,
                kzb.KZB_TEXTURE_WIDTH,
                kzb.KZB_TEXTURE_HEIGHT,
            )
        ).convert("RGBA")
        outputs: dict[str, Image.Image] = {rule.vcd_path: vcd}
        if preview is not None:
            outputs[rule.preview_path] = preview
        if f"{root}/{rule.rid_path}" in archive_names:
            rid_left = (kzb.KZB_TEXTURE_WIDTH - RID_SIZE[0]) // 2
            rid_top = (kzb.KZB_TEXTURE_HEIGHT - RID_SIZE[1]) // 2
            outputs[rule.rid_path] = full_texture.crop(
                (
                    rid_left,
                    rid_top,
                    rid_left + RID_SIZE[0],
                    rid_top + RID_SIZE[1],
                )
            ).convert("RGBA")
        if f"{root}/{rule.dim_path}" in archive_names:
            outputs[rule.dim_path] = make_dim_background(
                vcd, dim_masks[label], rule
            )
        for relative_path, image in outputs.items():
            archive_name = f"{root}/{relative_path}"
            template_png = archive.read(archive_name)
            encoded = png_bytes(image, template_png)
            (work_dir / "derived_png" / relative_path).parent.mkdir(
                parents=True,
                exist_ok=True,
            )
            (work_dir / "derived_png" / relative_path).write_bytes(encoded)
            replacements[archive_name] = encoded

        report[label] = {
            "preview_alpha_md5": (
                md5_image_channel(preview.getchannel("A"))
                if preview is not None
                else None
            ),
            "generated_resources": sorted(outputs),
            "native_texture_size": list(full_texture.size),
            "template_preview_size": list(preview_size),
            "vcd_crop": list(rule.vcd_crop),
            "rid_crop": list(rule.rid_crop),
            "dim_mask": redacted_path(dim_masks[label]),
            "dim_blur_radius": rule.dim_blur_radius,
            "dim_overlay_rgb": list(rule.dim_overlay_rgb),
        }

    return replacements, report


def premultiply_rgb_by_alpha(image: Image.Image) -> Image.Image:
    """Premultiply RGB by alpha so alpha=0 pixels have RGB 0,0,0."""
    red, green, blue, alpha = image.convert("RGBA").split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    )


def apply_original_alpha_premultiplied(source: Image.Image, alpha: Image.Image) -> Image.Image:
    result = source.convert("RGBA")
    result.putalpha(alpha.convert("L"))
    return premultiply_rgb_by_alpha(result)


def build_kzb_payloads(
    astcenc: Path,
    output_dir: Path,
    light_full_texture: Image.Image,
    dark_full_texture: Image.Image,
    source_kzb: bytes,
    source_records: list[kzb.TextureRecord],
    quality: str,
    template_id: str,
) -> tuple[dict[int, bytes], dict[str, Any], int, int, str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    light_full = light_full_texture.convert("RGB")
    dark_full = dark_full_texture.convert("RGB")
    # Preserve each template's own layer structure. The opaque panorama slots
    # differ between factory packages: BFA3 is 3/6 while C076 is 1/4.
    alphas = kzb.build_half_alphas(
        astcenc=astcenc,
        output_dir=output_dir / "source_masks",
        kzb=source_kzb,
        records=source_records,
    )
    normalized_id = template_id.upper()
    if normalized_id.startswith("1DE01DE2"):
        template_profile = "1DE0-racing"
        dark_indices = (4, 5, 6)
        light_indices = (1, 2, 3)
        dark_full_record = 6
        light_full_record = 1
    elif normalized_id.startswith("36DBC54B"):
        template_profile = "36DB-purple-space"
        dark_indices = (1, 2, 3)
        light_indices = (4, 5, 6)
        dark_full_record = 3
        light_full_record = 6
    elif normalized_id.startswith("C59D070C"):
        template_profile = "C59D-spring"
        dark_indices = (1, 2, 3)
        light_indices = (4, 5, 6)
        dark_full_record = 3
        light_full_record = 6
    elif normalized_id.startswith("9ADAF72D"):
        template_profile = "9ADA-ocean-mermaid"
        dark_indices = (1, 2, 3)
        light_indices = (4, 5, 6)
        dark_full_record = 3
        light_full_record = 6
    elif normalized_id.startswith("485EACC2"):
        template_profile = "485E-vacation-duck"
        dark_indices = (1, 2, 3)
        light_indices = (4, 5, 6)
        dark_full_record = 1
        light_full_record = 4
    elif normalized_id.startswith("BFA3A0F4"):
        template_profile = "BFA3"
        dark_indices = (1, 2, 3)
        light_indices = (4, 5, 6)
        dark_full_record = 3
        light_full_record = 6
    else:
        raise ValueError(
            "unsupported factory template; supported prefixes are "
            "BFA3A0F4, C59D070C, 1DE01DE2, 9ADAF72D, 36DBC54B, "
            "and 485EACC2"
        )

    sources: dict[int, Image.Image] = {}
    for indices, master, full_record in (
        (dark_indices, dark_full, dark_full_record),
        (light_indices, light_full, light_full_record),
    ):
        for index in indices:
            sources[index] = (
                master.convert("RGBA")
                if index == full_record
                else apply_original_alpha_premultiplied(master, alphas[index])
            )

    payloads: dict[int, bytes] = {}
    source_reports: dict[str, Any] = {}
    progress("step 5/9 encode KZB ASTC records")
    total = len(sources)
    for ordinal, (index, image) in enumerate(sorted(sources.items()), start=1):
        source_png = output_dir / f"record{index}_source_storage_yflip.png"
        output_astc = output_dir / f"record{index}_8960x1320_8x8.astc"
        progress(f"encode ASTC record {index} ({ordinal}/{total})")
        kzb.save_storage_orientation(image, source_png)
        payloads[index] = kzb.encode_astc_payload(
            astcenc=astcenc,
            source_png=source_png,
            output_astc=output_astc,
            quality=quality,
        )
        source_reports[str(index)] = {
            "source_png": redacted_path(source_png),
            "source_alpha_extrema": list(image.getchannel("A").getextrema()),
        }

    return (
        payloads,
        source_reports,
        dark_full_record,
        light_full_record,
        template_profile,
    )


def patch_kzb_from_full_textures(
    source_kzb: bytes,
    astcenc: Path,
    work_dir: Path,
    light_full_texture: Image.Image,
    dark_full_texture: Image.Image,
    quality: str,
    template_id: str,
) -> tuple[bytes, dict[str, Any]]:
    source_records = kzb.find_texture_records(source_kzb)
    (
        payloads,
        source_reports,
        dark_full_record,
        light_full_record,
        template_profile,
    ) = build_kzb_payloads(
        astcenc=astcenc,
        output_dir=work_dir / "kzb_astc_payloads",
        light_full_texture=light_full_texture,
        dark_full_texture=dark_full_texture,
        source_kzb=source_kzb,
        source_records=source_records,
        quality=quality,
        template_id=template_id,
    )
    patched_kzb, _ = kzb.patch_kzb(source_kzb, payloads)
    patched_records = kzb.find_texture_records(patched_kzb)
    report = {
        "source_kzb_md5": md5_bytes(source_kzb),
        "patched_kzb_md5": md5_bytes(patched_kzb),
        "source_kzb_size": len(source_kzb),
        "patched_kzb_size": len(patched_kzb),
        "source_records": [record.__dict__ for record in source_records],
        "patched_records": [record.__dict__ for record in patched_records],
        "replaced_records": sorted(payloads),
        "template_profile": template_profile,
        "dark_full_record": dark_full_record,
        "light_full_record": light_full_record,
        "preserved_records": [0],
        "record0_preserved": source_records[0].md5 == patched_records[0].md5,
        "preserved_records_unchanged": (
            source_records[0].md5 == patched_records[0].md5
        ),
        "record_offsets_same": [
            source.header_offset == patched.header_offset
            for source, patched in zip(source_records, patched_records)
        ],
        "record_source_reports": source_reports,
    }
    return patched_kzb, report


def rgba_extrema_from_png_bytes(data: bytes) -> tuple[tuple[int, int], ...]:
    with Image.open(io.BytesIO(data)) as image:
        return tuple(image.convert("RGBA").getextrema())


def verify_pngs(
    template_archive: zipfile.ZipFile,
    output_archive: zipfile.ZipFile,
    root: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    output_names = set(output_archive.namelist())
    for relative_path, expected_size in PNG_TARGET_SIZES.items():
        archive_name = f"{root}/{relative_path}"
        if archive_name not in output_names:
            continue
        template_data = template_archive.read(archive_name)
        if relative_path in PREVIEW_TARGETS:
            with Image.open(io.BytesIO(template_data)) as template_preview:
                expected_size = template_preview.size
        output_data = output_archive.read(archive_name)
        with Image.open(io.BytesIO(output_data)) as image:
            rgba = image.convert("RGBA")
            alpha_extrema = rgba.getchannel("A").getextrema()
            entry: dict[str, Any] = {
                "size": list(rgba.size),
                "size_matches": rgba.size == expected_size,
                "alpha_extrema": list(alpha_extrema),
                "bytes": len(output_data),
                "factory_png_chunks": [
                    chunk.decode("ascii") for chunk in factory_png_chunks(output_data)
                ],
            }
            template_chunks = factory_png_chunks(template_data)
            output_chunks = factory_png_chunks(output_data)
            entry["template_factory_png_chunks"] = [
                chunk.decode("ascii") for chunk in template_chunks
            ]
            entry["factory_png_chunks_match_template"] = (
                output_chunks == template_chunks
            )
            if relative_path in PREVIEW_TARGETS:
                original_alpha = Image.open(
                    io.BytesIO(template_archive.read(f"{root}/{relative_path}"))
                ).convert("RGBA").getchannel("A")
                entry["preview_alpha_md5"] = md5_image_channel(rgba.getchannel("A"))
                entry["template_alpha_md5"] = md5_image_channel(original_alpha)
                entry["preview_alpha_matches_template"] = (
                    entry["preview_alpha_md5"] == entry["template_alpha_md5"]
                )
            else:
                entry["fully_opaque"] = alpha_extrema == (255, 255)
            result[relative_path] = entry
    return result


def channel_max_where_alpha_zero(image: Image.Image) -> list[int] | None:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    alpha_zero_count = alpha.histogram()[0]
    if not alpha_zero_count:
        return None
    mask = alpha.point(lambda pixel: 255 if pixel == 0 else 0)
    maxima: list[int] = []
    for channel in rgba.convert("RGB").split():
        extrema = ImageStat.Stat(channel, mask=mask).extrema[0]
        maxima.append(int(extrema[1]))
    return maxima


def alpha_summary(image: Image.Image) -> dict[str, Any]:
    alpha = image.convert("RGBA").getchannel("A")
    histogram = alpha.histogram()
    total = alpha.width * alpha.height
    alpha0 = histogram[0]
    alpha255 = histogram[255]
    alpha_mid = total - alpha0 - alpha255
    return {
        "alpha_extrema": list(alpha.getextrema()),
        "alpha0_pct": round(alpha0 / total * 100, 6),
        "alpha_1_254_pct": round(alpha_mid / total * 100, 6),
        "alpha255_pct": round(alpha255 / total * 100, 6),
        "rgb_where_alpha0_max": channel_max_where_alpha_zero(image),
    }


def image_mae(left: Image.Image, right: Image.Image) -> float:
    diff = ImageChops.difference(left.convert("RGB"), right.convert("RGB"))
    stat = ImageStat.Stat(diff)
    return round(sum(stat.mean) / len(stat.mean), 6)


def verify_kzb_decode(
    astcenc: Path,
    output_kzb: bytes,
    output_archive: zipfile.ZipFile,
    root: str,
    work_dir: Path,
    dark_full_record: int,
    light_full_record: int,
    replaced_records: list[int],
) -> dict[str, Any]:
    records = kzb.find_texture_records(output_kzb)
    verify_dir = work_dir / "verify_decode"
    verify_dir.mkdir(parents=True, exist_ok=True)
    aux_reports: dict[str, Any] = {}
    full_records = {dark_full_record, light_full_record}
    for index in sorted(set(replaced_records) - full_records):
        record = records[index]
        decoded = kzb.decode_record_payload(
            astcenc=astcenc,
            payload=output_kzb[record.payload_start : record.payload_end],
            astc_path=verify_dir / f"record{index}.astc",
            png_path=verify_dir / f"record{index}_decoded_storage.png",
        )
        aux_reports[str(index)] = alpha_summary(decoded)

    stitch_reports: dict[str, Any] = {}
    for index, relative_path in (
        (dark_full_record, "vcd/wallpaper/dark_wallpaper_vcd.png"),
        (light_full_record, "vcd/wallpaper/light_wallpaper_vcd.png"),
    ):
        record = records[index]
        decoded_storage = kzb.decode_record_payload(
            astcenc=astcenc,
            payload=output_kzb[record.payload_start : record.payload_end],
            astc_path=verify_dir / f"record{index}.astc",
            png_path=verify_dir / f"record{index}_decoded_storage.png",
        )
        decoded = decoded_storage.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        right_crop = decoded.crop((kzb.KZB_VCD_JOIN_X, 0, kzb.KZB_TEXTURE_WIDTH, kzb.KZB_TEXTURE_HEIGHT))
        with Image.open(io.BytesIO(output_archive.read(f"{root}/{relative_path}"))) as vcd:
            stitch_reports[str(index)] = {
                "external_vcd": relative_path,
                "right_crop_vs_vcd_mae": image_mae(right_crop, vcd.convert("RGBA")),
            }

    return {
        "aux_records": aux_reports,
        "stitch": stitch_reports,
        "decode_dir": redacted_path(verify_dir),
    }


def assert_report_is_safe(report: dict[str, Any], max_stitch_mae: float) -> None:
    if report["zip_test_bad_file"] is not None:
        raise ValueError(f"zip test failed at {report['zip_test_bad_file']}")
    if not report["zip_names_identical_order"]:
        raise ValueError("zip entry order changed")

    for relative_path, entry in report["pngs"].items():
        if not entry["size_matches"]:
            raise ValueError(f"{relative_path} size mismatch: {entry['size']}")
        if not entry["factory_png_chunks_match_template"]:
            raise ValueError(
                f"{relative_path} factory PNG metadata differs from template"
            )
        if relative_path in PREVIEW_TARGETS:
            if not entry["preview_alpha_matches_template"]:
                raise ValueError(f"{relative_path} alpha differs from template")
        elif not entry["fully_opaque"]:
            raise ValueError(f"{relative_path} is not fully opaque")

    kzb_report = report["kzb"]
    if kzb_report["source_kzb_size"] != kzb_report["patched_kzb_size"]:
        raise ValueError("patched KZB size changed")
    if not kzb_report["preserved_records_unchanged"]:
        raise ValueError("one or more template-owned KZB records changed")
    if not all(kzb_report["record_offsets_same"]):
        raise ValueError("KZB record offsets changed")

    decode = report.get("decoded_kzb")
    if not decode:
        return
    for index, entry in decode["aux_records"].items():
        transparent_rgb = entry["rgb_where_alpha0_max"]
        # ASTC 8x8 may quantize a mathematically zero transparent channel to
        # 1-2 at fast settings. Values up to 4 are visually and semantically
        # transparent; larger values indicate missing premultiplication.
        if transparent_rgb is not None and max(transparent_rgb) > 4:
            raise ValueError(
                f"KZB rec{index} transparent RGB is not zero: "
                f"{transparent_rgb}"
            )
    for index, entry in decode["stitch"].items():
        mae = entry["right_crop_vs_vcd_mae"]
        if mae > max_stitch_mae:
            raise ValueError(f"KZB rec{index} stitch MAE too high: {mae}")


def build_package(
    input_zip: Path,
    output_zip: Path,
    light_image: Path,
    dark_image: Path,
    astcenc: Path,
    work_dir: Path,
    light_dim_mask: Path,
    dark_dim_mask: Path,
    quality: str = "-exhaustive",
    preview_blur: float = 0,
    sharpen: bool = True,
    decode_verify: bool = True,
    max_stitch_mae: float = 4.0,
    light_adjustment: CanvasAdjustment = CanvasAdjustment(),
    dark_adjustment: CanvasAdjustment = CanvasAdjustment(),
) -> dict[str, Any]:
    progress("step 1/9 validate inputs")
    if not input_zip.exists():
        raise FileNotFoundError(input_zip)
    if not astcenc.exists():
        raise FileNotFoundError(astcenc)
    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)

    progress("step 2/9 load images and prepare native 8960x1320 textures")
    light_source = load_source_image(light_image, "light")
    dark_source = load_source_image(dark_image, "dark")
    progress(
        f"light source {light_source.width}x{light_source.height}; "
        f"dark source {dark_source.width}x{dark_source.height}"
    )
    light_full_texture = prepare_full_texture(light_source, light_adjustment)
    dark_full_texture = prepare_full_texture(dark_source, dark_adjustment)
    replacements: dict[str, bytes] = {}

    with zipfile.ZipFile(input_zip) as source_archive:
        source_names = source_archive.namelist()
        root = kzb.find_wallpaper_root(source_names)
        progress(f"template wallpaper root: {root}")
        progress("step 3/9 derive external PNGs")
        external_replacements, external_report = derive_external_pngs(
            archive=source_archive,
            root=root,
            light_full_texture=light_full_texture,
            dark_full_texture=dark_full_texture,
            work_dir=work_dir,
            light_dim_mask=light_dim_mask,
            dark_dim_mask=dark_dim_mask,
            preview_blur=preview_blur,
            sharpen=sharpen,
        )
        replacements.update(external_replacements)

        kzb_name = kzb.find_kzb_name(source_names, root)
        progress("step 4/9 prepare KZB source records")
        patched_kzb, kzb_report = patch_kzb_from_full_textures(
            source_kzb=source_archive.read(kzb_name),
            astcenc=astcenc,
            work_dir=work_dir,
            light_full_texture=light_full_texture,
            dark_full_texture=dark_full_texture,
            quality=quality,
            template_id=root.split("/", 1)[0],
        )
        replacements[kzb_name] = patched_kzb

        progress("step 6/9 write output OTA zip")
        output_zip.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output_zip, "w") as output_archive:
            for info in source_archive.infolist():
                if info.is_dir():
                    output_archive.writestr(info, b"")
                    continue
                data = replacements.get(info.filename)
                if data is None:
                    data = source_archive.read(info.filename)
                output_archive.writestr(kzb.copy_info(info), data)

    with zipfile.ZipFile(input_zip) as template_archive, zipfile.ZipFile(output_zip) as output_archive:
        output_names = output_archive.namelist()
        root = kzb.find_wallpaper_root(output_names)
        progress("step 7/9 verify ZIP, PNG, and KZB invariants")
        report: dict[str, Any] = {
            "input_zip": redacted_path(input_zip),
            "output_zip": redacted_path(output_zip),
            "light_image": redacted_path(light_image),
            "dark_image": redacted_path(dark_image),
            "light_source_size": list(light_source.size),
            "dark_source_size": list(dark_source.size),
            "native_texture_size": [
                kzb.KZB_TEXTURE_WIDTH,
                kzb.KZB_TEXTURE_HEIGHT,
            ],
            "fit_mode": "web_canvas_cover_adjusted",
            "light_adjustment": light_adjustment.__dict__,
            "dark_adjustment": dark_adjustment.__dict__,
            "work_dir": redacted_path(work_dir),
            "astcenc": redacted_path(astcenc),
            "quality": quality,
            "preview_size": list(PREVIEW_SIZE),
            "preview_blur": preview_blur,
            "sharpen": sharpen,
            "zip_names_identical_order": template_archive.namelist() == output_names,
            "zip_test_bad_file": output_archive.testzip(),
            "external_pngs": external_report,
            "pngs": verify_pngs(template_archive, output_archive, root),
            "kzb": kzb_report,
        }
        if decode_verify:
            progress("step 8/9 decode verify KZB/VCD stitch")
            report["decoded_kzb"] = verify_kzb_decode(
                astcenc=astcenc,
                output_kzb=output_archive.read(kzb_name),
                output_archive=output_archive,
                root=root,
                work_dir=work_dir,
                dark_full_record=kzb_report["dark_full_record"],
                light_full_record=kzb_report["light_full_record"],
                replaced_records=kzb_report["replaced_records"],
            )
    assert_report_is_safe(report, max_stitch_mae=max_stitch_mae)
    progress("safety checks passed")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a final Cadillac OTA wallpaper zip from two PNG or JPEG images. "
            "Images are center-cropped to the native 8960x1320 texture. "
            "The tool replaces external PNGs and KZB ASTC records, then applies "
            "the v22 transparent-RGB rule for KZB auxiliary layers."
        )
    )
    parser.add_argument("--light-image", type=Path, required=True)
    parser.add_argument("--dark-image", type=Path, required=True)
    parser.add_argument("--output-zip", type=Path, required=True)
    parser.add_argument("--input-zip", type=Path, default=DEFAULT_INPUT_ZIP)
    parser.add_argument("--astcenc", type=Path, default=DEFAULT_ASTCENC)
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--light-dim-mask", type=Path, default=DEFAULT_LIGHT_DIM_MASK)
    parser.add_argument("--dark-dim-mask", type=Path, default=DEFAULT_DARK_DIM_MASK)
    parser.add_argument(
        "--quality",
        default="-exhaustive",
        help="astcenc quality; -exhaustive gives the clearest supported 8x8 texture",
    )
    parser.add_argument("--preview-blur", type=float, default=0)
    parser.add_argument("--no-sharpen", action="store_true")
    parser.add_argument("--skip-decode-verify", action="store_true")
    parser.add_argument("--max-stitch-mae", type=float, default=4.0)
    for label in ("light", "dark"):
        parser.add_argument(f"--{label}-zoom", type=float, default=1.0)
        parser.add_argument(f"--{label}-scale-x", type=float, default=1.0)
        parser.add_argument(f"--{label}-scale-y", type=float, default=1.0)
        parser.add_argument(f"--{label}-offset-x", type=float, default=0.0)
        parser.add_argument(f"--{label}-offset-y", type=float, default=0.0)
        parser.add_argument(f"--{label}-rotation", type=float, default=0.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    load_runtime_dependencies()
    work_dir = args.work_dir
    if work_dir is None:
        work_dir = PROJECT_ROOT / "build" / f"{args.output_zip.stem}_work"
    report = build_package(
        input_zip=args.input_zip,
        output_zip=args.output_zip,
        light_image=args.light_image,
        dark_image=args.dark_image,
        astcenc=args.astcenc,
        work_dir=work_dir,
        light_dim_mask=args.light_dim_mask,
        dark_dim_mask=args.dark_dim_mask,
        quality=args.quality,
        preview_blur=args.preview_blur,
        sharpen=not args.no_sharpen,
        decode_verify=not args.skip_decode_verify,
        max_stitch_mae=args.max_stitch_mae,
        light_adjustment=CanvasAdjustment(
            zoom=args.light_zoom,
            scale_x=args.light_scale_x,
            scale_y=args.light_scale_y,
            offset_x=args.light_offset_x,
            offset_y=args.light_offset_y,
            rotation=args.light_rotation,
        ),
        dark_adjustment=CanvasAdjustment(
            zoom=args.dark_zoom,
            scale_x=args.dark_scale_x,
            scale_y=args.dark_scale_y,
            offset_x=args.dark_offset_x,
            offset_y=args.dark_offset_y,
            rotation=args.dark_rotation,
        ),
    )
    report_path = args.report
    if report_path is None:
        report_path = work_dir / "package-report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    progress("step 9/9 write report.json")
    print(
        json.dumps(
            {
                "output_zip": redacted_path(args.output_zip),
                "report": redacted_path(report_path),
            },
            ensure_ascii=False,
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        progress(f"error: {type(error).__name__}: {error}")
        raise SystemExit(1)
