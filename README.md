# Cadillac Wallpaper Desktop

[中文](README.zh-CN.md) | English

Flutter desktop app for building Cadillac-compatible OTA wallpaper packages from two JPG, JPEG, or PNG images of any size. For native-quality output, use `8960x1320` (`224:33`) or a larger image with the same aspect ratio.

The desktop UI does not reimplement KZB, ASTC, crop, alpha, or dim-mask rules. Both modes call the same Python CLI, `packager/cadillac_wallpaper_packager.py`, then read `package-report.json` and display the validation checks in the app.

> This is an unofficial project. It is not affiliated with, endorsed by, or sponsored by General Motors or Cadillac. See [DISCLAIMER.md](DISCLAIMER.md).

Chinese usage guide: [docs/usage-zh-CN.md](docs/usage-zh-CN.md).

## Keywords

Cadillac wallpaper, Cadillac car wallpaper, Cadillac wallpaper packager, OTA wallpaper package, Flutter desktop, macOS, Windows, `.cwtheme`, Android-linked theme package, football template.

## Current Version

The current source version is `1.4.1+15`. Windows binaries can be published on this
repository's [Releases](https://github.com/HermitKin/cadillac-wallpapaer/releases) page.
GitHub's automatically generated `Source code` archives are development sources, not
complete ready-to-run Windows packages.

## Features

- Standard OTA mode: select light and dark JPG, JPEG, or PNG images, then output an OTA zip and a sibling report JSON.
- Native-resolution pipeline: exact `8960x1320` inputs bypass resampling; other sizes receive a single high-quality render pass.
- Non-destructive crop editor operating on the full source image, with zoom, independent width/height ratios, and X/Y positioning.
- Free rotation from `-180°` to `180°`; positive values rotate clockwise.
- Direct numeric entry for zoom, width/height ratios, rotation, and position.
- Maximum-quality encoding: KZB textures default to ASTC `-exhaustive` with perceptual photo optimization. The vehicle template mandates lossy ASTC 8x8, so pixel-lossless storage is impossible, but the app adds no avoidable degradation to the main texture.
- Android-linked theme mode: select light/dark masters plus theme metadata, then output a `.cwtheme` package and save it in the local desktop theme library.
- Report-driven validation UI for zip integrity, PNG size/alpha, preview alpha reuse, KZB size/record offsets, `rec0`, transparent RGB rules, and KZB/VCD stitch MAE.
- macOS desktop support for Intel and Apple Silicon builds.
- Windows x64 desktop support.
- Drag-and-drop image import, progress logs, path redaction, and quick open-output-folder actions.
- Six bundled template profiles: `BFA3`, `C59D`, `1DE0`, `9ADA`, `36DB`, and `485E`.

## Theme Package Format

`.cwtheme` files contain:

```text
cwtheme/
  manifest.json
  previews/light_preview_2198x367.png
  previews/dark_preview_2198x367.png
  previews/thumbnail_light.png
  previews/thumbnail_dark.png
  masters/light_master_2198x367.png
  masters/dark_master_2198x367.png
  payload/ota_wallpaper.zip
  report/package-report.json
```

## Bundled Template And Optional Override

The app bundles six template profiles:

```text
BFA3A0F4596C4C57A6BCDC1EB3348932
C59D070C944F434488DBB47F3A1856B4
1DE01DE2BDE840B5B80A2CBA4069C63A
9ADAF72DC26C4442A4FDA635FABCA348
36DBC54BD479499FB8D3585D7A3CE184
485EACC2AAC04B0291C769D74E938AE6
```

Release downloads can build packages directly without setting a template zip.

To test with your own compatible template package, override the bundled template at runtime:

```bash
export CADILLAC_INPUT_ZIP=/path/to/your/template.zip
```

Optional overrides:

```bash
export CADILLAC_PYTHON=/path/to/python-with-pillow
export CADILLAC_PACKAGER_SCRIPT=/path/to/cadillac_wallpaper_packager.py
export CADILLAC_ASTCENC=/path/to/astcenc-or-astcenc.exe
export CADILLAC_LIGHT_DIM_MASK=/path/to/light_dim_alpha_fixed_smoothed_used.png
export CADILLAC_DARK_DIM_MASK=/path/to/dark_dim_alpha_fixed_smoothed_used.png
```

On Windows use `set NAME=value` in `cmd.exe` or `$env:NAME="value"` in PowerShell.

Different factory packages may use different KZB record mappings. The bundled templates
have dedicated profiles; an unknown package supplied through `CADILLAC_INPUT_ZIP` must be
checked before use.

## Development

```bash
flutter pub get
flutter analyze
flutter test --coverage
```

Current coverage target is 80%+ line coverage.

## macOS Build

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter analyze
flutter test
flutter build macos --release
```

Expected release app path:

```text
build/macos/Build/Products/Release/cadillac_wallpaper_desktop.app
```

Architecture verification:

```bash
lipo -info build/macos/Build/Products/Release/cadillac_wallpaper_desktop.app/Contents/MacOS/cadillac_wallpaper_desktop
```

The final macOS release must report both `x86_64` and `arm64`.

## Windows x64 Build

Run on a Windows x64 host with Flutter desktop enabled:

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter analyze
flutter test --coverage
flutter build windows --release
```

Expected Windows artifact directory:

```text
build\windows\x64\runner\Release\
```

Expected executable:

```text
build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
```

Windows verification:

```powershell
Test-Path build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
Get-Item build\windows\x64\runner\Release\cadillac_wallpaper_desktop.exe
```

## Windows One-Click Build Kit

From macOS or Linux, create a Windows build kit zip:

```bash
scripts/make_windows_build_kit.sh
```

Copy `dist/CadillacPackager-windows-build-kit.zip` to a Windows x64 machine, extract it, then right-click `build_windows_one_click.cmd` and choose "Run as administrator". The generated release package will be:

```text
dist\CadillacPackager-windows-x64.zip
```

The Windows build kit includes the currently supported football template. After copying it to a Windows machine, the packaged app can use the bundled template by default.

## Community

This project will continue as an open-source and free Cadillac wallpaper tooling series. The wallpaper packager is available now; the wallpaper installer is still an unverified work in progress.

I am looking for Cadillac owners who want to help improve the tools, test different vehicles and system versions, share product suggestions, or help with tutorials, posts, and videos. Scan the WeChat QR code below to get in touch.

<img src="docs/assets/wechat-contact.png" alt="WeChat contact" width="240">

Good-faith learning, discussion, forks, and contributions are welcome. Copying this open-source work, rebranding it, and selling it for profit is not. This tooling series is intended to stay open-source and free, and contributors are expected to respect the work shared here.

禁止偷电
