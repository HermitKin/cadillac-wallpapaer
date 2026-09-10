// coverage:ignore-file
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cadillac_wallpaper_desktop/src/models/package_build_request.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_build_result.dart';
import 'package:cadillac_wallpaper_desktop/src/models/package_report_summary.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_library_entry.dart';
import 'package:cadillac_wallpaper_desktop/src/models/theme_package_request.dart';
import 'package:cadillac_wallpaper_desktop/src/services/folder_opener_service.dart';
import 'package:cadillac_wallpaper_desktop/src/services/image_probe_service.dart';
import 'package:cadillac_wallpaper_desktop/src/services/path_redactor.dart';
import 'package:cadillac_wallpaper_desktop/src/services/theme_library_store.dart';
import 'package:cadillac_wallpaper_desktop/src/services/theme_package_service.dart';
import 'package:cadillac_wallpaper_desktop/src/services/wallpaper_packager_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PackageMode {
  standardOta,
  androidTheme,
}

enum _FactoryTemplate {
  bfa3,
  springC59d,
  racing1de0,
  oceanMermaid9ada,
  purpleSpace36db,
  vacationDuck485e,
}

extension on _FactoryTemplate {
  String get label => switch (this) {
        _FactoryTemplate.bfa3 => 'BFA3 · 大力抽射（有 RID）',
        _FactoryTemplate.springC59d => 'C59D · 春日重塑（无 RID）',
        _FactoryTemplate.racing1de0 => '1DE0 · 致命弯道（无 RID）',
        _FactoryTemplate.oceanMermaid9ada => '9ADA · 海洋美人鱼（有 RID）',
        _FactoryTemplate.purpleSpace36db => '36DB · 紫色太空（有 RID）',
        _FactoryTemplate.vacationDuck485e => '485E · 度假鸭（无 RID）',
      };

  String get assetPath => switch (this) {
        _FactoryTemplate.bfa3 =>
          'packager/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip',
        _FactoryTemplate.springC59d =>
          'packager/templates/C59D070C944F434488DBB47F3A1856B4.zip',
        _FactoryTemplate.racing1de0 =>
          'packager/templates/1DE01DE2BDE840B5B80A2CBA4069C63A.zip',
        _FactoryTemplate.oceanMermaid9ada =>
          'packager/templates/9ADAF72DC26C4442A4FDA635FABCA348.zip',
        _FactoryTemplate.purpleSpace36db =>
          'packager/templates/36DBC54BD479499FB8D3585D7A3CE184.zip',
        _FactoryTemplate.vacationDuck485e =>
          'packager/templates/485EACC2AAC04B0291C769D74E938AE6.zip',
      };

  String get mapping => switch (this) {
        _FactoryTemplate.bfa3 => '深色 3 / 浅色 6',
        _FactoryTemplate.springC59d => '深色 3 / 浅色 6',
        _FactoryTemplate.racing1de0 => '深色 6 / 浅色 1',
        _FactoryTemplate.oceanMermaid9ada => '深色 3 / 浅色 6',
        _FactoryTemplate.purpleSpace36db => '深色 3 / 浅色 6',
        _FactoryTemplate.vacationDuck485e => '深色 1 / 浅色 4',
      };

  bool get hasRid => switch (this) {
        _FactoryTemplate.bfa3 ||
        _FactoryTemplate.oceanMermaid9ada ||
        _FactoryTemplate.purpleSpace36db =>
          true,
        _ => false,
      };

  String get rootId => switch (this) {
        _FactoryTemplate.bfa3 => 'BFA3A0F4596C4C57A6BCDC1EB3348932',
        _FactoryTemplate.springC59d => 'C59D070C944F434488DBB47F3A1856B4',
        _FactoryTemplate.racing1de0 => '1DE01DE2BDE840B5B80A2CBA4069C63A',
        _FactoryTemplate.oceanMermaid9ada => '9ADAF72DC26C4442A4FDA635FABCA348',
        _FactoryTemplate.purpleSpace36db => '36DBC54BD479499FB8D3585D7A3CE184',
        _FactoryTemplate.vacationDuck485e => '485EACC2AAC04B0291C769D74E938AE6',
      };

  String get wallpaperFolder => switch (this) {
        _FactoryTemplate.bfa3 => 'cadi_wallpaper05111930',
        _FactoryTemplate.springC59d => 'cadi_wallpaper02121606',
        _FactoryTemplate.racing1de0 => 'cadi_wallpaper03112144',
        _FactoryTemplate.oceanMermaid9ada => 'cadi_wallpaper08062238',
        _FactoryTemplate.purpleSpace36db => 'cadi_wallpaper07022119',
        _FactoryTemplate.vacationDuck485e => 'cadi_wallpaper06031832',
      };
}

class _CanvasAdjustment {
  const _CanvasAdjustment({
    this.zoom = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.rotation = 0,
  });

  final double zoom;
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;
  final double rotation;

  _CanvasAdjustment copyWith({
    double? zoom,
    double? scaleX,
    double? scaleY,
    double? offsetX,
    double? offsetY,
    double? rotation,
  }) {
    return _CanvasAdjustment(
      zoom: zoom ?? this.zoom,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      rotation: rotation ?? this.rotation,
    );
  }
}

double _minimumZoomForProbe(ImageProbe probe) {
  final widthScale = ImageProbe.ultraClearWidth / probe.width;
  final heightScale = ImageProbe.ultraClearHeight / probe.height;
  final coverScale = widthScale > heightScale ? widthScale : heightScale;
  final containScale = widthScale < heightScale ? widthScale : heightScale;
  return (containScale / coverScale).clamp(0.05, 1.0).toDouble();
}

_CanvasAdjustment _clampCropAdjustment(
  _CanvasAdjustment value,
  ImageProbe probe,
) {
  final zoom = value.zoom.clamp(_minimumZoomForProbe(probe), 4.0).toDouble();
  final scaleX = value.scaleX.clamp(0.25, 4.0).toDouble();
  final scaleY = value.scaleY.clamp(0.25, 4.0).toDouble();
  final rotation = value.rotation.clamp(-180.0, 180.0).toDouble();
  final widthScale = ImageProbe.ultraClearWidth / probe.width;
  final heightScale = ImageProbe.ultraClearHeight / probe.height;
  final baseScale = widthScale > heightScale ? widthScale : heightScale;
  final renderedWidth = probe.width * baseScale * zoom * scaleX;
  final renderedHeight = probe.height * baseScale * zoom * scaleY;
  final radians = rotation * 3.141592653589793 / 180;
  final cosine = math.cos(radians).abs();
  final sine = math.sin(radians).abs();
  final boundsWidth = renderedWidth * cosine + renderedHeight * sine;
  final boundsHeight = renderedWidth * sine + renderedHeight * cosine;
  final proposedCenterX = ImageProbe.ultraClearWidth / 2 +
      value.offsetX * ImageProbe.ultraClearWidth;
  final proposedCenterY = ImageProbe.ultraClearHeight / 2 +
      value.offsetY * ImageProbe.ultraClearHeight;
  final minCenterX = boundsWidth <= ImageProbe.ultraClearWidth
      ? boundsWidth / 2
      : ImageProbe.ultraClearWidth - boundsWidth / 2;
  final maxCenterX = boundsWidth <= ImageProbe.ultraClearWidth
      ? ImageProbe.ultraClearWidth - boundsWidth / 2
      : boundsWidth / 2;
  final minCenterY = boundsHeight <= ImageProbe.ultraClearHeight
      ? boundsHeight / 2
      : ImageProbe.ultraClearHeight - boundsHeight / 2;
  final maxCenterY = boundsHeight <= ImageProbe.ultraClearHeight
      ? ImageProbe.ultraClearHeight - boundsHeight / 2
      : boundsHeight / 2;
  final centerX = proposedCenterX.clamp(minCenterX, maxCenterX).toDouble();
  final centerY = proposedCenterY.clamp(minCenterY, maxCenterY).toDouble();
  return _CanvasAdjustment(
    zoom: zoom,
    scaleX: scaleX,
    scaleY: scaleY,
    offsetX:
        (centerX - ImageProbe.ultraClearWidth / 2) / ImageProbe.ultraClearWidth,
    offsetY: (centerY - ImageProbe.ultraClearHeight / 2) /
        ImageProbe.ultraClearHeight,
    rotation: rotation,
  );
}

class CadillacWallpaperDesktopApp extends StatelessWidget {
  const CadillacWallpaperDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xff0a7c76);
    return MaterialApp(
      title: 'Cadillac Wallpaper Packager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: _AppColors.surface,
          background: _AppColors.chrome,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: _AppColors.chrome,
        fontFamily: '.AppleSystemUIFont',
        visualDensity: VisualDensity.standard,
        dividerTheme: const DividerThemeData(
          color: _AppColors.separator,
          thickness: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _AppColors.field,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.separator),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.separator),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _AppColors.accent, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            side: const MaterialStatePropertyAll(
              BorderSide(color: _AppColors.separator),
            ),
          ),
        ),
      ),
      home: const PackagingHomePage(),
    );
  }
}

class PackagingHomePage extends StatefulWidget {
  const PackagingHomePage({super.key});

  @override
  State<PackagingHomePage> createState() => _PackagingHomePageState();
}

class _PackagingHomePageState extends State<PackagingHomePage> {
  final _themeNameController = TextEditingController(text: 'Cadillac Theme');
  final _authorController = TextEditingController();
  final _notesController = TextEditingController();
  final _outputZipController = TextEditingController();
  final _packagerService = WallpaperPackagerService();
  final _themePackageService = ThemePackageService();
  final _imageProbeService = ImageProbeService();
  final _folderOpenerService = FolderOpenerService();
  final _logs = <String>[];

  PackageMode _mode = PackageMode.standardOta;
  ThemeLibraryStore? _libraryStore;
  String? _libraryRootPath;
  String? _lightImagePath;
  String? _darkImagePath;
  String? _templateZipPath;
  _FactoryTemplate _factoryTemplate = _FactoryTemplate.bfa3;
  ImageProbe? _lightProbe;
  ImageProbe? _darkProbe;
  PackageBuildResult? _lastResult;
  String? _lastPackagePath;
  String? _lastOutputFolderPath;
  List<ThemeLibraryEntry> _themes = const <ThemeLibraryEntry>[];
  bool _running = false;
  bool _editingLight = true;
  _CanvasAdjustment _lightAdjustment = const _CanvasAdjustment();
  _CanvasAdjustment _darkAdjustment = const _CanvasAdjustment();

  static const _imageType = XTypeGroup(
    label: '图片',
    extensions: <String>['png', 'jpg', 'jpeg'],
    uniformTypeIdentifiers: <String>['public.png', 'public.jpeg'],
  );
  static const _zipType = XTypeGroup(
    label: 'ZIP',
    extensions: <String>['zip'],
    uniformTypeIdentifiers: <String>['public.zip-archive'],
  );

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _themeNameController.dispose();
    _authorController.dispose();
    _notesController.dispose();
    _outputZipController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final supportDir = await getApplicationSupportDirectory();
    final rootPath = p.join(supportDir.path, 'CadillacWallpaperThemes');
    final store = ThemeLibraryStore(rootDirectory: rootPath);
    final themes = await store.loadEntries();
    if (themes.isNotEmpty) {
      await store.saveEntries(themes);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _libraryRootPath = rootPath;
      _libraryStore = store;
      _themes = themes;
    });
  }

  Future<void> _selectImage({required bool isLight}) async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_imageType],
      confirmButtonText: '选择',
    );
    if (file == null) {
      return;
    }

    await _setImagePath(isLight: isLight, path: file.path);
  }

  Future<void> _dropImage({
    required bool isLight,
    required List<String> paths,
  }) async {
    final droppedPaths = paths.where((path) => path.trim().isNotEmpty).toList();
    final imagePath = droppedPaths.cast<String?>().firstWhere(
          (path) => _isSupportedImagePath(path!),
          orElse: () => null,
        );
    final label = isLight ? '白天' : '黑夜';
    if (imagePath == null) {
      _appendLog('拖入失败: $label 只支持 JPG、JPEG 或 PNG 文件');
      return;
    }
    if (droppedPaths.length > 1) {
      _appendLog('拖入多个文件，$label 已使用第一张支持的图片');
    }
    await _setImagePath(isLight: isLight, path: imagePath);
  }

  Future<void> _setImagePath({
    required bool isLight,
    required String path,
  }) async {
    if (!_isSupportedImagePath(path)) {
      _appendLog('图片添加失败: 只支持 JPG、JPEG 或 PNG 文件 (${p.basename(path)})');
      return;
    }

    try {
      final probe = await _imageProbeService.inspect(path);
      setState(() {
        if (isLight) {
          _lightImagePath = path;
          _lightProbe = probe;
          _lightAdjustment = _CanvasAdjustment(
            zoom: _minimumZoomForProbe(probe),
          );
        } else {
          _darkImagePath = path;
          _darkProbe = probe;
          _darkAdjustment = _CanvasAdjustment(
            zoom: _minimumZoomForProbe(probe),
          );
        }
      });
      final label = isLight ? '白天' : '黑夜';
      final sizeLabel = '${probe.width}x${probe.height}';
      _appendLog(
        '已添加$label图片: ${p.basename(path)} '
        '($sizeLabel, alpha ${probe.alphaMin}-${probe.alphaMax})',
      );
      _appendLog('$label图片质量评估: ${probe.qualityLabel}');
      if (!probe.isUltraClearSize || !probe.hasUltraWideAspectRatio) {
        _appendLog(
          '建议使用 8960x1320（224:33）或更高的同宽高比图片，以获得最清晰效果',
        );
      }
      if (mounted) {
        await _openCropEditor(isLight: isLight);
      }
    } on Object catch (error) {
      _appendLog('图片读取失败: $error');
    }
  }

  Future<void> _openCropEditor({required bool isLight}) async {
    final path = isLight ? _lightImagePath : _darkImagePath;
    final probe = isLight ? _lightProbe : _darkProbe;
    if (path == null || probe == null || !mounted) {
      return;
    }
    var local = _clampCropAdjustment(
      isLight ? _lightAdjustment : _darkAdjustment,
      probe,
    );
    final label = isLight ? '白天' : '黑夜';
    final result = await showDialog<_CanvasAdjustment>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(CupertinoIcons.crop),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '调整$label画面中的人物大小和位置',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      _StatusPill(
                        text: '${probe.width} × ${probe.height}',
                        color: probe.isUltraClearSize
                            ? _AppColors.success
                            : _AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '默认先完整放入原图。可拖动定位、自由旋转，也可以在下方直接输入缩放、宽高比例、角度和位置数值。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _AppColors.secondaryText,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _SourceCropCanvas(
                    path: path,
                    probe: probe,
                    adjustment: local,
                    onChanged: (value) => setDialogState(() => local = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Icon(
                        CupertinoIcons.info_circle,
                        size: 16,
                        color: _AppColors.secondaryText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '预览就是最终 8960×1320 画面。缩小产生的空白由同一原图的模糊背景填满；红线区分左右屏。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _AppColors.secondaryText,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _CropZoomControl(
                    value: local,
                    probe: probe,
                    onChanged: (value) => setDialogState(
                      () => local = _clampCropAdjustment(value, probe),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => setDialogState(
                          () => local = _clampCropAdjustment(
                            _CanvasAdjustment(
                              zoom: _minimumZoomForProbe(probe),
                            ),
                            probe,
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.arrow_counterclockwise),
                        label: const Text('完整人物居中'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(local),
                        icon: const Icon(CupertinoIcons.checkmark_alt),
                        label: const Text('确认调整'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      if (isLight) {
        _lightAdjustment = result;
      } else {
        _darkAdjustment = result;
      }
    });
    _appendLog('$label裁切范围已确认，将直接从原图生成 8960x1320 母图');
  }

  static bool _isSupportedImagePath(String path) {
    return const <String>{'.png', '.jpg', '.jpeg'}
        .contains(p.extension(path).toLowerCase());
  }

  Future<void> _selectOutputZip() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_zipType],
      suggestedName: 'cadillac_ota_wallpaper.zip',
      confirmButtonText: '保存',
    );
    if (location == null) {
      return;
    }
    final path = location.path.toLowerCase().endsWith('.zip')
        ? location.path
        : '${location.path}.zip';
    setState(() {
      _outputZipController.text = path;
    });
  }

  Future<void> _selectTemplateZip() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_zipType],
      confirmButtonText: '选择原厂模板',
    );
    if (file == null) {
      return;
    }
    setState(() => _templateZipPath = file.path);
    _appendLog('已选择原厂模板: ${p.basename(file.path)}');
  }

  Future<void> _runPackaging() async {
    final validationError = _validateInputs();
    if (validationError != null) {
      _appendLog(validationError);
      return;
    }

    setState(() {
      _running = true;
      _lastResult = null;
      _lastPackagePath = null;
      _lastOutputFolderPath = null;
      _logs.clear();
    });

    Timer? progressTimer;
    final stopwatch = Stopwatch()..start();
    try {
      final now = DateTime.now();
      _appendLog(
        '步骤 1/6 校验输入: 白天 ${p.basename(_lightImagePath!)}，'
        '黑夜 ${p.basename(_darkImagePath!)}',
      );
      final paths = _resolveBuildPaths(now);
      _appendLog('步骤 2/6 准备输出目录: ${p.dirname(paths.outputZipPath)}');
      final buildResources = await _resolveBuildResources();
      final envInputZipPath = _envPath('CADILLAC_INPUT_ZIP');
      final inputZipPath =
          envInputZipPath ?? _templateZipPath ?? buildResources.inputZipPath;
      final astcencPath =
          _envPath('CADILLAC_ASTCENC') ?? buildResources.astcencPath;
      final lightDimMaskPath = _envPath('CADILLAC_LIGHT_DIM_MASK') ??
          buildResources.lightDimMaskPath;
      final darkDimMaskPath =
          _envPath('CADILLAC_DARK_DIM_MASK') ?? buildResources.darkDimMaskPath;
      _appendLog('步骤 3/6 解析内置模板和 ASTC 工具');
      _appendLog(
        envInputZipPath != null
            ? '使用 CADILLAC_INPUT_ZIP 指定的模板'
            : _templateZipPath != null
                ? '使用手动选择的原厂模板（自动识别 KZB 映射）'
                : '使用内置 ${_factoryTemplate.label}，映射 ${_factoryTemplate.mapping}',
      );
      _appendResourceLog('模板 zip', inputZipPath);
      _appendResourceLog('astcenc', astcencPath);
      _appendResourceLog('白天 alpha mask', lightDimMaskPath);
      _appendResourceLog('黑夜 alpha mask', darkDimMaskPath);
      final resourceError = _validateInputZipResource(inputZipPath);
      if (resourceError != null) {
        throw PackagerException(resourceError);
      }
      _appendLog(
        '步骤 4/6 调用打包 Runtime: ${_packagerService.runtimeDescription}',
      );
      _appendLog('已启用原生尺寸直通和 ASTC 最高画质编码；耗时会明显增加');
      progressTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _appendLog(
          'CLI 仍在运行 ${stopwatch.elapsed.inSeconds}s，'
          '正在生成预览、编码 ASTC 或校验拼接',
        );
      });
      final result = await _packagerService.buildPackage(
        PackageBuildRequest(
          lightImagePath: _lightImagePath!,
          darkImagePath: _darkImagePath!,
          outputZipPath: paths.outputZipPath,
          workDirPath: paths.workDirPath,
          reportPath: paths.reportPath,
          inputZipPath: inputZipPath,
          astcencPath: astcencPath,
          lightDimMaskPath: lightDimMaskPath,
          darkDimMaskPath: darkDimMaskPath,
          lightZoom: _lightAdjustment.zoom,
          lightScaleX: _lightAdjustment.scaleX,
          lightScaleY: _lightAdjustment.scaleY,
          lightOffsetX: _lightAdjustment.offsetX,
          lightOffsetY: _lightAdjustment.offsetY,
          lightRotation: _lightAdjustment.rotation,
          darkZoom: _darkAdjustment.zoom,
          darkScaleX: _darkAdjustment.scaleX,
          darkScaleY: _darkAdjustment.scaleY,
          darkOffsetX: _darkAdjustment.offsetX,
          darkOffsetY: _darkAdjustment.offsetY,
          darkRotation: _darkAdjustment.rotation,
        ),
        onCliOutput: _appendCliOutput,
      );
      progressTimer.cancel();
      progressTimer = null;
      _appendLog('步骤 5/6 读取 report.json 并生成校验报告');
      _appendLog('OTA zip: ${result.outputZipPath}');
      _appendLog('report.json: ${result.reportPath}');

      ThemeLibraryEntry? savedTheme;
      if (_mode == PackageMode.androidTheme) {
        _appendLog('步骤 6/6 写入 .cwtheme 并保存到本地主题库');
        savedTheme = await _saveThemePackage(result, now);
      } else {
        _appendLog('步骤 6/6 完成标准 OTA 打包');
      }

      if (!mounted) {
        return;
      }
      final packagePath = savedTheme?.cwthemePath ?? result.outputZipPath;
      final outputFolderPath = p.dirname(packagePath);
      setState(() {
        _lastResult = result;
        _lastPackagePath = packagePath;
        _lastOutputFolderPath = outputFolderPath;
      });
      _appendLog('输出文件夹: $outputFolderPath');
      _appendLog('总耗时: ${stopwatch.elapsed.inSeconds}s');
    } on Object catch (error) {
      _appendLog('打包失败: $error');
    } finally {
      progressTimer?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<ThemeLibraryEntry> _saveThemePackage(
    PackageBuildResult result,
    DateTime createdAt,
  ) async {
    final libraryRootPath = _libraryRootPath;
    final libraryStore = _libraryStore;
    if (libraryRootPath == null || libraryStore == null) {
      throw StateError('主题库尚未初始化');
    }

    final entry = await _themePackageService.createThemePackage(
      ThemePackageRequest(
        displayName: _themeNameController.text.trim(),
        author: _authorController.text.trim(),
        notes: _notesController.text.trim(),
        createdAt: createdAt,
        lightMasterPath: p.join(
          result.workDirPath,
          'preview_masters',
          'light_preview_master.png',
        ),
        darkMasterPath: p.join(
          result.workDirPath,
          'preview_masters',
          'dark_preview_master.png',
        ),
        lightPreviewPath: p.join(
          result.workDirPath,
          'derived_png',
          'light_preview_image.png',
        ),
        darkPreviewPath: p.join(
          result.workDirPath,
          'derived_png',
          'dark_preview_image.png',
        ),
        otaZipPath: result.outputZipPath,
        reportPath: result.reportPath,
        reportSummary: result.reportSummary,
        libraryRootPath: libraryRootPath,
        templateRootId: _factoryTemplate.rootId,
        wallpaperFolder: _factoryTemplate.wallpaperFolder,
      ),
    );
    await libraryStore.upsertEntry(entry);
    final themes = await libraryStore.loadEntries();
    if (!mounted) {
      return entry;
    }
    setState(() {
      _themes = themes;
    });
    _appendLog('.cwtheme: ${entry.cwthemePath}');
    return entry;
  }

  _BuildPaths _resolveBuildPaths(DateTime now) {
    final stamp = _timestamp(now);
    if (_mode == PackageMode.standardOta) {
      final outputZipPath = _outputZipController.text.trim();
      final base = p.withoutExtension(outputZipPath);
      return _BuildPaths(
        outputZipPath: outputZipPath,
        workDirPath: '${base}_work',
        reportPath: '$base-report.json',
      );
    }

    final root = p.join(_libraryRootPath!, 'builds', stamp);
    return _BuildPaths(
      outputZipPath: p.join(root, 'ota_wallpaper.zip'),
      workDirPath: p.join(root, 'work'),
      reportPath: p.join(root, 'package-report.json'),
    );
  }

  Future<_BuildResources> _resolveBuildResources() async {
    String? astcencSource;
    if (Platform.isMacOS) {
      astcencSource = WallpaperPackagerService.bundledAssetPath(
        'packager/tools/macos/astcenc',
      );
    } else if (Platform.isWindows) {
      astcencSource = WallpaperPackagerService.bundledAssetPath(
        'packager/tools/windows/astcenc.exe',
      );
    }
    return _BuildResources(
      inputZipPath: WallpaperPackagerService.bundledAssetPath(
        _factoryTemplate.assetPath,
      ),
      astcencPath: astcencSource == null
          ? null
          : await _stageExecutableAsset(
              sourcePath: astcencSource,
              name: Platform.isWindows ? 'astcenc.exe' : 'astcenc',
            ),
      lightDimMaskPath: WallpaperPackagerService.bundledAssetPath(
        'packager/masks/light_dim_alpha_fixed_smoothed_used.png',
      ),
      darkDimMaskPath: WallpaperPackagerService.bundledAssetPath(
        'packager/masks/dark_dim_alpha_fixed_smoothed_used.png',
      ),
    );
  }

  Future<String> _stageExecutableAsset({
    required String sourcePath,
    required String name,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final runtimeDir = Directory(p.join(supportDir.path, 'PackagerRuntime'));
    await runtimeDir.create(recursive: true);
    final destination = File(p.join(runtimeDir.path, name));
    final source = File(sourcePath);
    if (!destination.existsSync() ||
        destination.lengthSync() != source.lengthSync()) {
      await source.copy(destination.path);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['755', destination.path]);
    }
    return destination.path;
  }

  String? _validateInputs() {
    if (_lightImagePath == null || _darkImagePath == null) {
      return '需要选择白天和黑夜两张 JPG、JPEG 或 PNG 图片';
    }
    if (_mode == PackageMode.standardOta &&
        _outputZipController.text.trim().isEmpty) {
      return '标准 OTA 模式需要输出 zip 路径';
    }
    if (_mode == PackageMode.androidTheme &&
        _themeNameController.text.trim().isEmpty) {
      return 'Android 联动主题包需要主题名称';
    }
    if (_mode == PackageMode.androidTheme && _libraryRootPath == null) {
      return '主题库路径尚未初始化';
    }
    return null;
  }

  Future<void> _deleteTheme(ThemeLibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除主题'),
        content: Text(entry.displayName),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(CupertinoIcons.delete),
            label: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _libraryStore?.deleteTheme(entry.themeId);
    await _loadLibrary();
  }

  Future<void> _openOutputFolder() async {
    final outputFolderPath = _lastOutputFolderPath;
    if (outputFolderPath == null) {
      return;
    }
    await _openFolder(outputFolderPath);
  }

  Future<void> _openThemeFolder(ThemeLibraryEntry entry) async {
    await _openFolder(p.dirname(entry.cwthemePath));
  }

  Future<void> _openFolder(String folderPath) async {
    try {
      final openedPath = await _folderOpenerService.openFolder(folderPath);
      _appendLog('已打开文件夹: $openedPath');
    } on Object catch (error) {
      _appendLog('打开文件夹失败: $error');
    }
  }

  void _appendLog(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.add(redactSensitivePaths(message));
    });
  }

  void _appendResourceLog(String label, String? path) {
    _appendLog('$label: ${path ?? '使用 CLI 默认'}');
  }

  String? _validateInputZipResource(String? path) {
    if (path == null || path.trim().isEmpty) {
      return '模板 zip 未配置。请重新下载包含内置足球模板的版本，或设置 CADILLAC_INPUT_ZIP 指向兼容模板 zip。';
    }
    if (!File(path).existsSync()) {
      return '模板 zip 不存在，请检查内置足球模板或 CADILLAC_INPUT_ZIP: $path';
    }
    return null;
  }

  void _appendCliOutput(String line) {
    if (line.startsWith('[cadillac-packager]')) {
      _appendLog(line);
      return;
    }
    _appendLog('CLI: $line');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _lastResult?.reportSummary;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _AppHeader(mode: _mode, running: _running, summary: summary),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;
                  final sidebar = _Sidebar(
                    mode: _mode,
                    lightImagePath: _lightImagePath,
                    darkImagePath: _darkImagePath,
                    lightProbe: _lightProbe,
                    darkProbe: _darkProbe,
                    outputZipController: _outputZipController,
                    themeNameController: _themeNameController,
                    authorController: _authorController,
                    notesController: _notesController,
                    templateZipPath: _templateZipPath,
                    factoryTemplate: _factoryTemplate,
                    libraryRootPath: _libraryRootPath,
                    running: _running,
                    onModeChanged: (mode) => setState(() => _mode = mode),
                    onPickLight: () => _selectImage(isLight: true),
                    onPickDark: () => _selectImage(isLight: false),
                    onEditLight: () => _openCropEditor(isLight: true),
                    onEditDark: () => _openCropEditor(isLight: false),
                    onDropLight: (paths) =>
                        _dropImage(isLight: true, paths: paths),
                    onDropDark: (paths) =>
                        _dropImage(isLight: false, paths: paths),
                    onPickOutput: _selectOutputZip,
                    onPickTemplate: _selectTemplateZip,
                    onUseBuiltInTemplate: () =>
                        setState(() => _templateZipPath = null),
                    onFactoryTemplateChanged: (value) => setState(() {
                      _factoryTemplate = value;
                      _templateZipPath = null;
                    }),
                    onRun: _running ? null : _runPackaging,
                  );
                  final workbench = _Workbench(
                    mode: _mode,
                    factoryTemplate: _factoryTemplate,
                    lightImagePath: _lightImagePath,
                    darkImagePath: _darkImagePath,
                    lightProbe: _lightProbe,
                    darkProbe: _darkProbe,
                    editingLight: _editingLight,
                    lightAdjustment: _lightAdjustment,
                    darkAdjustment: _darkAdjustment,
                    onEditingLightChanged: (value) =>
                        setState(() => _editingLight = value),
                    onLightAdjustmentChanged: (value) => setState(() =>
                        _lightAdjustment = _lightProbe == null
                            ? value
                            : _clampCropAdjustment(value, _lightProbe!)),
                    onDarkAdjustmentChanged: (value) => setState(() =>
                        _darkAdjustment = _darkProbe == null
                            ? value
                            : _clampCropAdjustment(value, _darkProbe!)),
                    result: _lastResult,
                    packagePath: _lastPackagePath,
                    outputFolderPath: _lastOutputFolderPath,
                    summary: summary,
                    logs: _logs,
                    themes: _themes,
                    onDeleteTheme: _deleteTheme,
                    onOpenOutputFolder: _openOutputFolder,
                    onOpenThemeFolder: _openThemeFolder,
                    onRefreshLibrary: _loadLibrary,
                  );

                  if (compact) {
                    return CustomScrollView(
                      slivers: <Widget>[
                        SliverToBoxAdapter(child: sidebar),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                          sliver: SliverToBoxAdapter(child: workbench),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(width: 338, child: sidebar),
                      const VerticalDivider(width: 1),
                      Expanded(child: workbench),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.mode,
    required this.running,
    required this.summary,
  });

  final PackageMode mode;
  final bool running;
  final PackageReportSummary? summary;

  @override
  Widget build(BuildContext context) {
    final status = summary?.allPassed;
    final statusText = running
        ? '打包中'
        : status == null
            ? '待打包'
            : status
                ? '校验通过'
                : '校验异常';
    final statusColor = running
        ? _AppColors.accent
        : status == null
            ? _AppColors.tertiaryText
            : status
                ? _AppColors.success
                : _AppColors.danger;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: _AppColors.surface),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/app_icon_source.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 26, color: _AppColors.chromeLine),
          const SizedBox(width: 12),
          Text(
            'Cadillac Packager',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(width: 10),
          Text(
            mode == PackageMode.standardOta ? '标准 OTA' : '主题包',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AppColors.secondaryText,
                ),
          ),
          const Spacer(),
          _StatusPill(text: statusText, color: statusColor),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.mode,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.outputZipController,
    required this.themeNameController,
    required this.authorController,
    required this.notesController,
    required this.templateZipPath,
    required this.factoryTemplate,
    required this.libraryRootPath,
    required this.running,
    required this.onModeChanged,
    required this.onPickLight,
    required this.onPickDark,
    required this.onEditLight,
    required this.onEditDark,
    required this.onDropLight,
    required this.onDropDark,
    required this.onPickOutput,
    required this.onPickTemplate,
    required this.onUseBuiltInTemplate,
    required this.onFactoryTemplateChanged,
    required this.onRun,
  });

  final PackageMode mode;
  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final TextEditingController outputZipController;
  final TextEditingController themeNameController;
  final TextEditingController authorController;
  final TextEditingController notesController;
  final String? templateZipPath;
  final _FactoryTemplate factoryTemplate;
  final String? libraryRootPath;
  final bool running;
  final ValueChanged<PackageMode> onModeChanged;
  final VoidCallback onPickLight;
  final VoidCallback onPickDark;
  final VoidCallback onEditLight;
  final VoidCallback onEditDark;
  final Future<void> Function(List<String> paths) onDropLight;
  final Future<void> Function(List<String> paths) onDropDark;
  final VoidCallback onPickOutput;
  final VoidCallback onPickTemplate;
  final VoidCallback onUseBuiltInTemplate;
  final ValueChanged<_FactoryTemplate> onFactoryTemplateChanged;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _AppColors.sidebar,
        border: Border(right: BorderSide(color: _AppColors.separator)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SidebarTitle(),
            const SizedBox(height: 14),
            _ModePicker(mode: mode, onChanged: onModeChanged),
            const SizedBox(height: 20),
            const _SectionLabel(
              icon: CupertinoIcons.layers,
              title: '原厂模板',
              trailing: '自动识别 KZB',
            ),
            const SizedBox(height: 10),
            _TemplatePicker(
              path: templateZipPath,
              factoryTemplate: factoryTemplate,
              onPick: onPickTemplate,
              onUseBuiltIn: onUseBuiltInTemplate,
              onFactoryTemplateChanged: onFactoryTemplateChanged,
            ),
            const SizedBox(height: 20),
            const _SectionLabel(
              icon: CupertinoIcons.photo,
              title: '输入图片',
              trailing: '推荐 8960x1320',
            ),
            const SizedBox(height: 10),
            _ImageInputTile(
              title: '白天',
              path: lightImagePath,
              probe: lightProbe,
              onPick: onPickLight,
              onEdit: onEditLight,
              onDrop: onDropLight,
            ),
            const SizedBox(height: 10),
            _ImageInputTile(
              title: '黑夜',
              path: darkImagePath,
              probe: darkProbe,
              onPick: onPickDark,
              onEdit: onEditDark,
              onDrop: onDropDark,
            ),
            const SizedBox(height: 22),
            if (mode == PackageMode.standardOta)
              _StandardOutputFields(
                outputZipPath: outputZipController.text,
                onPickOutput: onPickOutput,
              )
            else
              _ThemeFields(
                themeNameController: themeNameController,
                authorController: authorController,
                notesController: notesController,
                libraryRootPath: libraryRootPath,
              ),
            const SizedBox(height: 22),
            _RunButton(running: running, onRun: onRun),
          ],
        ),
      ),
    );
  }
}

class _SidebarTitle extends StatelessWidget {
  const _SidebarTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            CupertinoIcons.slider_horizontal_3,
            color: _AppColors.accent,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Inputs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
              Text(
                'OTA / Theme Pack',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AppColors.secondaryText,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});

  final PackageMode mode;
  final ValueChanged<PackageMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PackageMode>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<PackageMode>>[
        ButtonSegment<PackageMode>(
          value: PackageMode.standardOta,
          icon: Icon(CupertinoIcons.archivebox, size: 18),
          label: Text('标准 OTA'),
        ),
        ButtonSegment<PackageMode>(
          value: PackageMode.androidTheme,
          icon: Icon(CupertinoIcons.device_phone_portrait, size: 18),
          label: Text('主题包'),
        ),
      ],
      selected: <PackageMode>{mode},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: _AppColors.secondaryText),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _AppColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
      ],
    );
  }
}

class _ImageInputTile extends StatefulWidget {
  const _ImageInputTile({
    required this.title,
    required this.path,
    required this.probe,
    required this.onPick,
    required this.onEdit,
    required this.onDrop,
  });

  final String title;
  final String? path;
  final ImageProbe? probe;
  final VoidCallback onPick;
  final VoidCallback onEdit;
  final Future<void> Function(List<String> paths) onDrop;

  @override
  State<_ImageInputTile> createState() => _ImageInputTileState();
}

class _ImageInputTileState extends State<_ImageInputTile> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final valid = widget.probe != null;
    final imageProbe = widget.probe;
    final statusColor = imageProbe == null
        ? _AppColors.tertiaryText
        : imageProbe.isUltraClearSize && imageProbe.hasUltraWideAspectRatio
            ? _AppColors.success
            : _AppColors.warning;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        await widget.onDrop(
          details.files.map((file) => file.path).toList(growable: false),
        );
      },
      child: _Panel(
        padding: const EdgeInsets.all(10),
        highlighted: _dragging,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (widget.path != null) ...<Widget>[
                  _IconTextButton(
                    icon: CupertinoIcons.crop,
                    label: '裁切',
                    onPressed: widget.onEdit,
                  ),
                  const SizedBox(width: 4),
                ],
                _IconTextButton(
                  icon: CupertinoIcons.folder,
                  label: '选择',
                  onPressed: widget.onPick,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '拖入 JPG / PNG 或点击选择',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        _dragging ? _AppColors.accent : _AppColors.tertiaryText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 9),
            _PreviewStrip(path: widget.path, compact: true),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  valid
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.info_circle_fill,
                  color: statusColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    imageProbe == null
                        ? '未选择'
                        : '${imageProbe.width}x${imageProbe.height} · ${imageProbe.qualityLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AppColors.secondaryText,
                        ),
                  ),
                ),
              ],
            ),
            if (widget.path != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                p.basename(widget.path!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AppColors.tertiaryText,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({
    required this.path,
    required this.factoryTemplate,
    required this.onPick,
    required this.onUseBuiltIn,
    required this.onFactoryTemplateChanged,
  });

  final String? path;
  final _FactoryTemplate factoryTemplate;
  final VoidCallback onPick;
  final VoidCallback onUseBuiltIn;
  final ValueChanged<_FactoryTemplate> onFactoryTemplateChanged;

  @override
  Widget build(BuildContext context) {
    final custom = path != null;
    return _Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!custom)
            DropdownButtonFormField<_FactoryTemplate>(
              value: factoryTemplate,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '内置原厂包'),
              items: _FactoryTemplate.values
                  .map(
                    (template) => DropdownMenuItem<_FactoryTemplate>(
                      value: template,
                      child: Text(
                        template.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) {
                  onFactoryTemplateChanged(value);
                }
              },
            )
          else
            Row(
              children: <Widget>[
                const Icon(
                  CupertinoIcons.archivebox,
                  size: 18,
                  color: _AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.basename(path!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Text(
            custom
                ? '支持 BFA3、C59D、1DE0、9ADA、36DB、485E 六种已验证映射'
                : '当前映射：${factoryTemplate.mapping}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (custom)
                TextButton(
                  onPressed: onUseBuiltIn,
                  child: const Text('返回内置模板'),
                ),
              _IconTextButton(
                icon: CupertinoIcons.folder,
                label: '选择 ZIP',
                onPressed: onPick,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StandardOutputFields extends StatelessWidget {
  const _StandardOutputFields({
    required this.outputZipPath,
    required this.onPickOutput,
  });

  final String outputZipPath;
  final VoidCallback onPickOutput;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionLabel(
          icon: CupertinoIcons.square_arrow_down,
          title: '输出',
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: onPickOutput,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            isEmpty: outputZipPath.isEmpty,
            decoration: InputDecoration(
              labelText: 'OTA zip',
              suffixIcon: IconButton(
                tooltip: '选择输出路径',
                onPressed: onPickOutput,
                icon: const Icon(CupertinoIcons.ellipsis_circle),
              ),
            ),
            child: Text(
              outputZipPath.isEmpty
                  ? '未选择'
                  : redactSensitivePaths(outputZipPath),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeFields extends StatelessWidget {
  const _ThemeFields({
    required this.themeNameController,
    required this.authorController,
    required this.notesController,
    required this.libraryRootPath,
  });

  final TextEditingController themeNameController;
  final TextEditingController authorController;
  final TextEditingController notesController;
  final String? libraryRootPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionLabel(
          icon: CupertinoIcons.slider_horizontal_3,
          title: '主题信息',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: themeNameController,
          decoration: const InputDecoration(labelText: '主题名称'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: authorController,
          decoration: const InputDecoration(labelText: '作者'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 8),
        Text(
          libraryRootPath == null
              ? '主题库初始化中'
              : redactSensitivePaths(libraryRootPath),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AppColors.tertiaryText,
              ),
        ),
      ],
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.running, required this.onRun});

  final bool running;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: onRun,
        icon: running
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(CupertinoIcons.play_fill, size: 18),
        label: Text(running ? '打包中' : '开始打包'),
        style: FilledButton.styleFrom(
          backgroundColor: _AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _Workbench extends StatelessWidget {
  const _Workbench({
    required this.mode,
    required this.factoryTemplate,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.editingLight,
    required this.lightAdjustment,
    required this.darkAdjustment,
    required this.onEditingLightChanged,
    required this.onLightAdjustmentChanged,
    required this.onDarkAdjustmentChanged,
    required this.result,
    required this.packagePath,
    required this.outputFolderPath,
    required this.summary,
    required this.logs,
    required this.themes,
    required this.onDeleteTheme,
    required this.onOpenOutputFolder,
    required this.onOpenThemeFolder,
    required this.onRefreshLibrary,
  });

  final PackageMode mode;
  final _FactoryTemplate factoryTemplate;
  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final bool editingLight;
  final _CanvasAdjustment lightAdjustment;
  final _CanvasAdjustment darkAdjustment;
  final ValueChanged<bool> onEditingLightChanged;
  final ValueChanged<_CanvasAdjustment> onLightAdjustmentChanged;
  final ValueChanged<_CanvasAdjustment> onDarkAdjustmentChanged;
  final PackageBuildResult? result;
  final String? packagePath;
  final String? outputFolderPath;
  final PackageReportSummary? summary;
  final List<String> logs;
  final List<ThemeLibraryEntry> themes;
  final ValueChanged<ThemeLibraryEntry> onDeleteTheme;
  final VoidCallback onOpenOutputFolder;
  final ValueChanged<ThemeLibraryEntry> onOpenThemeFolder;
  final VoidCallback onRefreshLibrary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1060 && constraints.hasBoundedHeight;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _HeroStatus(
                                mode: mode,
                                lightImagePath: lightImagePath,
                                darkImagePath: darkImagePath,
                                summary: summary,
                                packagePath: packagePath,
                              ),
                              const SizedBox(height: 14),
                              _PreviewPanel(
                                lightImagePath: lightImagePath,
                                darkImagePath: darkImagePath,
                                lightProbe: lightProbe,
                                darkProbe: darkProbe,
                                editingLight: editingLight,
                                lightAdjustment: lightAdjustment,
                                darkAdjustment: darkAdjustment,
                                onEditingLightChanged: onEditingLightChanged,
                                onLightAdjustmentChanged:
                                    onLightAdjustmentChanged,
                                onDarkAdjustmentChanged:
                                    onDarkAdjustmentChanged,
                              ),
                              const SizedBox(height: 14),
                              _ResourcePreviewPanel(
                                lightImagePath: lightImagePath,
                                darkImagePath: darkImagePath,
                                lightProbe: lightProbe,
                                darkProbe: darkProbe,
                                lightAdjustment: lightAdjustment,
                                darkAdjustment: darkAdjustment,
                                hasRid: factoryTemplate.hasRid,
                              ),
                              const SizedBox(height: 14),
                              _ReportPanel(
                                summary: summary,
                                result: result,
                                packagePath: packagePath,
                                outputFolderPath: outputFolderPath,
                                onOpenOutputFolder: onOpenOutputFolder,
                              ),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: constraints.maxWidth >= 1240 ? 420 : 360,
                        child: SingleChildScrollView(
                          child: _ThemeLibraryPanel(
                            themes: themes,
                            onDeleteTheme: onDeleteTheme,
                            onOpenThemeFolder: onOpenThemeFolder,
                            onRefresh: onRefreshLibrary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _LogPanel(logs: logs),
                const SizedBox(height: 14),
              ],
            ),
          );
        }

        final content = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _HeroStatus(
                mode: mode,
                lightImagePath: lightImagePath,
                darkImagePath: darkImagePath,
                summary: summary,
                packagePath: packagePath,
              ),
              const SizedBox(height: 14),
              _PreviewPanel(
                lightImagePath: lightImagePath,
                darkImagePath: darkImagePath,
                lightProbe: lightProbe,
                darkProbe: darkProbe,
                editingLight: editingLight,
                lightAdjustment: lightAdjustment,
                darkAdjustment: darkAdjustment,
                onEditingLightChanged: onEditingLightChanged,
                onLightAdjustmentChanged: onLightAdjustmentChanged,
                onDarkAdjustmentChanged: onDarkAdjustmentChanged,
              ),
              const SizedBox(height: 14),
              _ResourcePreviewPanel(
                lightImagePath: lightImagePath,
                darkImagePath: darkImagePath,
                lightProbe: lightProbe,
                darkProbe: darkProbe,
                lightAdjustment: lightAdjustment,
                darkAdjustment: darkAdjustment,
                hasRid: factoryTemplate.hasRid,
              ),
              const SizedBox(height: 14),
              _ReportPanel(
                summary: summary,
                result: result,
                packagePath: packagePath,
                outputFolderPath: outputFolderPath,
                onOpenOutputFolder: onOpenOutputFolder,
              ),
              const SizedBox(height: 14),
              _LogPanel(logs: logs),
              const SizedBox(height: 14),
              _ThemeLibraryPanel(
                themes: themes,
                onDeleteTheme: onDeleteTheme,
                onOpenThemeFolder: onOpenThemeFolder,
                onRefresh: onRefreshLibrary,
              ),
            ],
          ),
        );

        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: content);
        }
        return content;
      },
    );
  }
}

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({
    required this.mode,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.summary,
    required this.packagePath,
  });

  final PackageMode mode;
  final String? lightImagePath;
  final String? darkImagePath;
  final PackageReportSummary? summary;
  final String? packagePath;

  @override
  Widget build(BuildContext context) {
    final passed = summary?.allPassed;
    final statusText = passed == null ? '待打包' : (passed ? '校验通过' : '校验异常');
    final statusColor = passed == null
        ? _AppColors.tertiaryText
        : (passed ? _AppColors.success : _AppColors.danger);
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: mode == PackageMode.standardOta
                      ? CupertinoIcons.archivebox
                      : CupertinoIcons.cube_box,
                  label: '模式',
                  value: mode == PackageMode.standardOta ? '标准 OTA' : '主题包',
                  color: _AppColors.accent,
                ),
              ),
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: CupertinoIcons.photo_on_rectangle,
                  label: '输入图片',
                  value:
                      '${(lightImagePath == null ? 0 : 1) + (darkImagePath == null ? 0 : 1)} / 2',
                  color: lightImagePath != null && darkImagePath != null
                      ? _AppColors.success
                      : _AppColors.tertiaryText,
                ),
              ),
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: CupertinoIcons.doc_text,
                  label: '输出',
                  value: packagePath == null
                      ? (mode == PackageMode.standardOta
                          ? 'OTA zip'
                          : '.cwtheme')
                      : p.basename(packagePath!),
                  color: packagePath == null
                      ? _AppColors.tertiaryText
                      : _AppColors.success,
                ),
              ),
              SizedBox(
                width: width,
                child: _SummaryTile(
                  icon: CupertinoIcons.checkmark_shield,
                  label: '校验',
                  value: statusText,
                  color: statusColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AppColors.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _AppColors.separator),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _AppColors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.editingLight,
    required this.lightAdjustment,
    required this.darkAdjustment,
    required this.onEditingLightChanged,
    required this.onLightAdjustmentChanged,
    required this.onDarkAdjustmentChanged,
  });

  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final bool editingLight;
  final _CanvasAdjustment lightAdjustment;
  final _CanvasAdjustment darkAdjustment;
  final ValueChanged<bool> onEditingLightChanged;
  final ValueChanged<_CanvasAdjustment> onLightAdjustmentChanged;
  final ValueChanged<_CanvasAdjustment> onDarkAdjustmentChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelHeader(
            icon: CupertinoIcons.crop,
            title: '预览',
            trailingWidget: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('白天')),
                ButtonSegment<bool>(value: false, label: Text('黑夜')),
              ],
              selected: <bool>{editingLight},
              onSelectionChanged: (values) =>
                  onEditingLightChanged(values.single),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 560;
              final children = <Widget>[
                _PreviewFrame(
                  label: '白天',
                  path: lightImagePath,
                  probe: lightProbe,
                  adjustment: lightAdjustment,
                  selected: editingLight,
                  onSelect: () => onEditingLightChanged(true),
                  onPan: (delta) => onLightAdjustmentChanged(
                    lightAdjustment.copyWith(
                      offsetX:
                          (lightAdjustment.offsetX + delta.dx).clamp(-0.5, 0.5),
                      offsetY:
                          (lightAdjustment.offsetY + delta.dy).clamp(-0.5, 0.5),
                    ),
                  ),
                ),
                _PreviewFrame(
                  label: '黑夜',
                  path: darkImagePath,
                  probe: darkProbe,
                  adjustment: darkAdjustment,
                  selected: !editingLight,
                  onSelect: () => onEditingLightChanged(false),
                  onPan: (delta) => onDarkAdjustmentChanged(
                    darkAdjustment.copyWith(
                      offsetX:
                          (darkAdjustment.offsetX + delta.dx).clamp(-0.5, 0.5),
                      offsetY:
                          (darkAdjustment.offsetY + delta.dy).clamp(-0.5, 0.5),
                    ),
                  ),
                ),
              ];
              if (!sideBySide) {
                return Column(
                  children: <Widget>[
                    children[0],
                    const SizedBox(height: 12),
                    children[1],
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: children[0]),
                  const SizedBox(width: 12),
                  Expanded(child: children[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _AdjustmentControls(
            label: editingLight ? '白天画面' : '黑夜画面',
            value: editingLight ? lightAdjustment : darkAdjustment,
            probe: editingLight ? lightProbe : darkProbe,
            onChanged: editingLight
                ? onLightAdjustmentChanged
                : onDarkAdjustmentChanged,
          ),
          const SizedBox(height: 6),
          Text(
            '可直接拖动画面；右侧 3950×1320 是中控实际取图区域。调整只重绘一次母图，不会反复压缩。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
        ],
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.label,
    required this.path,
    required this.probe,
    required this.adjustment,
    required this.selected,
    required this.onSelect,
    required this.onPan,
  });

  final String label;
  final String? path;
  final ImageProbe? probe;
  final _CanvasAdjustment adjustment;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onPan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _AppColors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            if (path != null)
              Flexible(
                child: Text(
                  p.basename(path!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _AppColors.tertiaryText,
                      ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _CanvasPreviewStrip(
          path: path,
          probe: probe,
          adjustment: adjustment,
          selected: selected,
          onTap: onSelect,
          onPan: onPan,
        ),
      ],
    );
  }
}

class _CanvasPreviewStrip extends StatelessWidget {
  const _CanvasPreviewStrip({
    required this.path,
    required this.probe,
    required this.adjustment,
    required this.selected,
    required this.onTap,
    required this.onPan,
  });

  final String? path;
  final ImageProbe? probe;
  final _CanvasAdjustment adjustment;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onPan;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: ImageProbe.ultraClearWidth / ImageProbe.ultraClearHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTap: onTap,
              onPanStart: (_) => onTap(),
              onPanUpdate: (details) => onPan(Offset(
                details.delta.dx / constraints.maxWidth,
                details.delta.dy / constraints.maxHeight,
              )),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff161a1d),
                  border: Border.all(
                    color: selected ? _AppColors.accent : _AppColors.separator,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (path == null)
                      const Center(
                        child: Icon(
                          CupertinoIcons.photo,
                          color: Color(0xff6f777d),
                          size: 22,
                        ),
                      )
                    else
                      _CanvasLayeredImage(
                        path: path!,
                        probe: probe,
                        adjustment: adjustment,
                      ),
                    Positioned(
                      left: constraints.maxWidth * 5010 / 8960,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 1.5, color: Colors.redAccent),
                    ),
                    Positioned(
                      right: 7,
                      bottom: 5,
                      child: Text(
                        '右屏 3950',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CanvasLayeredImage extends StatelessWidget {
  const _CanvasLayeredImage({
    required this.path,
    required this.probe,
    required this.adjustment,
  });

  final String path;
  final ImageProbe? probe;
  final _CanvasAdjustment adjustment;

  @override
  Widget build(BuildContext context) {
    final imageProbe = probe;
    if (imageProbe == null) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    final normalized = _clampCropAdjustment(adjustment, imageProbe);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widthScale = constraints.maxWidth / imageProbe.width;
          final heightScale = constraints.maxHeight / imageProbe.height;
          final coverScale =
              widthScale > heightScale ? widthScale : heightScale;
          final renderedWidth = imageProbe.width *
              coverScale *
              normalized.zoom *
              normalized.scaleX;
          final renderedHeight = imageProbe.height *
              coverScale *
              normalized.zoom *
              normalized.scaleY;
          final left = (constraints.maxWidth - renderedWidth) / 2 +
              normalized.offsetX * constraints.maxWidth;
          final top = (constraints.maxHeight - renderedHeight) / 2 +
              normalized.offsetY * constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Transform.scale(
                  scale: 1.08,
                  child: Image.file(File(path), fit: BoxFit.cover),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: renderedWidth,
                height: renderedHeight,
                child: Transform.rotate(
                  angle: normalized.rotation * math.pi / 180,
                  child: Image.file(File(path), fit: BoxFit.fill),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SourceCropCanvas extends StatelessWidget {
  const _SourceCropCanvas({
    required this.path,
    required this.probe,
    required this.adjustment,
    required this.onChanged,
  });

  final String path;
  final ImageProbe probe;
  final _CanvasAdjustment adjustment;
  final ValueChanged<_CanvasAdjustment> onChanged;

  @override
  Widget build(BuildContext context) {
    if (probe.width > 0 && probe.height > 0) {
      return _SubjectCanvasPreview(
        path: path,
        probe: probe,
        adjustment: adjustment,
        onChanged: onChanged,
      );
    }
    return SizedBox(
      height: 430,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: const Color(0xff161a1d),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widthScale = constraints.maxWidth / probe.width;
              final heightScale = constraints.maxHeight / probe.height;
              final displayScale =
                  widthScale < heightScale ? widthScale : heightScale;
              final displayWidth = probe.width * displayScale;
              final displayHeight = probe.height * displayScale;
              final imageLeft = (constraints.maxWidth - displayWidth) / 2;
              final imageTop = (constraints.maxHeight - displayHeight) / 2;

              final normalized = _clampCropAdjustment(adjustment, probe);
              final nativeWidthScale = ImageProbe.ultraClearWidth / probe.width;
              final nativeHeightScale =
                  ImageProbe.ultraClearHeight / probe.height;
              final baseScale = nativeWidthScale > nativeHeightScale
                  ? nativeWidthScale
                  : nativeHeightScale;
              final renderedScale = baseScale * normalized.zoom;
              final cropWidth = ImageProbe.ultraClearWidth / renderedScale;
              final cropHeight = ImageProbe.ultraClearHeight / renderedScale;
              final centerX = probe.width / 2 - normalized.offsetX * cropWidth;
              final centerY =
                  probe.height / 2 - normalized.offsetY * cropHeight;
              final cropRect = Rect.fromCenter(
                center: Offset(
                  imageLeft + centerX * displayScale,
                  imageTop + centerY * displayScale,
                ),
                width: cropWidth * displayScale,
                height: cropHeight * displayScale,
              );

              void moveCrop(Offset displayDelta) {
                final nextCenterX = (centerX + displayDelta.dx / displayScale)
                    .clamp(cropWidth / 2, probe.width - cropWidth / 2)
                    .toDouble();
                final nextCenterY = (centerY + displayDelta.dy / displayScale)
                    .clamp(cropHeight / 2, probe.height - cropHeight / 2)
                    .toDouble();
                onChanged(_CanvasAdjustment(
                  zoom: normalized.zoom,
                  offsetX: (probe.width / 2 - nextCenterX) / cropWidth,
                  offsetY: (probe.height / 2 - nextCenterY) / cropHeight,
                ));
              }

              Widget shade(Rect rect) => Positioned.fromRect(
                    rect: rect,
                    child: const ColoredBox(color: Color(0x99000000)),
                  );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => moveCrop(details.delta),
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: imageLeft,
                        top: imageTop,
                        width: displayWidth,
                        height: displayHeight,
                        child: Image.file(File(path), fit: BoxFit.fill),
                      ),
                      shade(Rect.fromLTWH(
                        imageLeft,
                        imageTop,
                        displayWidth,
                        (cropRect.top - imageTop)
                            .clamp(0.0, displayHeight)
                            .toDouble(),
                      )),
                      shade(Rect.fromLTWH(
                        imageLeft,
                        cropRect.bottom,
                        displayWidth,
                        (imageTop + displayHeight - cropRect.bottom)
                            .clamp(0.0, displayHeight)
                            .toDouble(),
                      )),
                      shade(Rect.fromLTWH(
                        imageLeft,
                        cropRect.top,
                        (cropRect.left - imageLeft)
                            .clamp(0.0, displayWidth)
                            .toDouble(),
                        cropRect.height,
                      )),
                      shade(Rect.fromLTWH(
                        cropRect.right,
                        cropRect.top,
                        (imageLeft + displayWidth - cropRect.right)
                            .clamp(0.0, displayWidth)
                            .toDouble(),
                        cropRect.height,
                      )),
                      Positioned.fromRect(
                        rect: cropRect,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _AppColors.accent,
                              width: 3,
                            ),
                          ),
                          child: Stack(
                            children: <Widget>[
                              Positioned(
                                left: cropRect.width * 5010 / 8960,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1.5,
                                  color: Colors.redAccent,
                                ),
                              ),
                              Positioned(
                                left: 8,
                                bottom: 5,
                                child: Text(
                                  '左屏 5010',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                    color: Colors.white,
                                    shadows: const <Shadow>[
                                      Shadow(
                                          color: Colors.black, blurRadius: 3),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 5,
                                child: Text(
                                  '右屏 3950',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                    color: Colors.white,
                                    shadows: const <Shadow>[
                                      Shadow(
                                          color: Colors.black, blurRadius: 3),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _StatusPill(
                          text:
                              '保留约 ${cropWidth.round()} × ${cropHeight.round()} 原图像素',
                          color: _AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SubjectCanvasPreview extends StatelessWidget {
  const _SubjectCanvasPreview({
    required this.path,
    required this.probe,
    required this.adjustment,
    required this.onChanged,
  });

  final String path;
  final ImageProbe probe;
  final _CanvasAdjustment adjustment;
  final ValueChanged<_CanvasAdjustment> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalized = _clampCropAdjustment(adjustment, probe);
    final minimumZoom = _minimumZoomForProbe(probe);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: ImageProbe.ultraClearWidth / ImageProbe.ultraClearHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final widthScale = constraints.maxWidth / probe.width;
            final heightScale = constraints.maxHeight / probe.height;
            final coverScale =
                widthScale > heightScale ? widthScale : heightScale;
            final renderedWidth =
                probe.width * coverScale * normalized.zoom * normalized.scaleX;
            final renderedHeight =
                probe.height * coverScale * normalized.zoom * normalized.scaleY;
            final left = (constraints.maxWidth - renderedWidth) / 2 +
                normalized.offsetX * constraints.maxWidth;
            final top = (constraints.maxHeight - renderedHeight) / 2 +
                normalized.offsetY * constraints.maxHeight;
            final completeMode = normalized.zoom < 0.9999;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onChanged(_clampCropAdjustment(
                normalized.copyWith(
                  offsetX: normalized.offsetX +
                      details.delta.dx / constraints.maxWidth,
                  offsetY: normalized.offsetY +
                      details.delta.dy / constraints.maxHeight,
                ),
                probe,
              )),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Transform.scale(
                        scale: 1.08,
                        child: Image.file(File(path), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      left: left,
                      top: top,
                      width: renderedWidth,
                      height: renderedHeight,
                      child: Transform.rotate(
                        angle: normalized.rotation * math.pi / 180,
                        child: Image.file(File(path), fit: BoxFit.fill),
                      ),
                    ),
                    Positioned(
                      left: constraints.maxWidth * 5010 / 8960,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 1.5, color: Colors.redAccent),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: _AppColors.accent, width: 3),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 9,
                      bottom: 6,
                      child: Text(
                        '左屏 5010',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 9,
                      bottom: 6,
                      child: Text(
                        '右屏 3950',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: _StatusPill(
                        text: completeMode
                            ? '完整人物 · ${normalized.zoom.toStringAsFixed(2)}× · ${normalized.rotation.toStringAsFixed(1)}°'
                            : '放大裁切 · ${normalized.zoom.toStringAsFixed(2)}× · ${normalized.rotation.toStringAsFixed(1)}°',
                        color: completeMode
                            ? _AppColors.success
                            : _AppColors.accent,
                      ),
                    ),
                    if ((normalized.zoom - minimumZoom).abs() < 0.002)
                      const Positioned(
                        left: 10,
                        top: 10,
                        child: _StatusPill(
                          text: '整张原图已完整放入',
                          color: _AppColors.success,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CropZoomControl extends StatelessWidget {
  const _CropZoomControl({
    required this.value,
    required this.probe,
    required this.onChanged,
  });

  final _CanvasAdjustment value;
  final ImageProbe probe;
  final ValueChanged<_CanvasAdjustment> onChanged;

  @override
  Widget build(BuildContext context) {
    final minimumZoom = _minimumZoomForProbe(probe);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 14,
          runSpacing: 10,
          children: <Widget>[
            _AdjustmentSlider(
              label: '整体缩放',
              value: value.zoom.clamp(minimumZoom, 4).toDouble(),
              min: minimumZoom,
              max: 4,
              suffix: '×',
              onChanged: (v) => onChanged(value.copyWith(zoom: v)),
            ),
            _AdjustmentSlider(
              label: '宽度比例',
              value: value.scaleX,
              min: 0.25,
              max: 4,
              suffix: '×',
              onChanged: (v) => onChanged(value.copyWith(scaleX: v)),
            ),
            _AdjustmentSlider(
              label: '高度比例',
              value: value.scaleY,
              min: 0.25,
              max: 4,
              suffix: '×',
              onChanged: (v) => onChanged(value.copyWith(scaleY: v)),
            ),
            _AdjustmentSlider(
              label: '旋转角度',
              value: value.rotation,
              min: -180,
              max: 180,
              suffix: '°',
              onChanged: (v) => onChanged(value.copyWith(rotation: v)),
            ),
            _AdjustmentSlider(
              label: '左右位置',
              value: value.offsetX,
              min: -1,
              max: 1,
              onChanged: (v) => onChanged(value.copyWith(offsetX: v)),
            ),
            _AdjustmentSlider(
              label: '上下位置',
              value: value.offsetY,
              min: -1,
              max: 1,
              onChanged: (v) => onChanged(value.copyWith(offsetY: v)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '数值可直接输入并按 Enter 应用；正角度为顺时针。人物不变形时请保持宽度和高度比例相同。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AppColors.secondaryText,
              ),
        ),
      ],
    );
  }
}

class _AdjustmentControls extends StatelessWidget {
  const _AdjustmentControls({
    required this.label,
    required this.value,
    required this.probe,
    required this.onChanged,
  });

  final String label;
  final _CanvasAdjustment value;
  final ImageProbe? probe;
  final ValueChanged<_CanvasAdjustment> onChanged;

  @override
  Widget build(BuildContext context) {
    final minimumZoom = probe == null ? 0.05 : _minimumZoomForProbe(probe!);
    void change(_CanvasAdjustment adjustment) {
      onChanged(
        probe == null ? adjustment : _clampCropAdjustment(adjustment, probe!),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$label调整',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: () => change(_CanvasAdjustment(zoom: minimumZoom)),
              icon: const Icon(CupertinoIcons.refresh, size: 16),
              label: const Text('重置'),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            _AdjustmentSlider(
              label: '缩放',
              value: value.zoom.clamp(minimumZoom, 2.5).toDouble(),
              min: minimumZoom,
              max: 2.5,
              onChanged: (v) => change(value.copyWith(zoom: v)),
            ),
            _AdjustmentSlider(
              label: '宽度比例',
              value: value.scaleX,
              min: 0.25,
              max: 4,
              suffix: '×',
              onChanged: (v) => change(value.copyWith(scaleX: v)),
            ),
            _AdjustmentSlider(
              label: '高度比例',
              value: value.scaleY,
              min: 0.25,
              max: 4,
              suffix: '×',
              onChanged: (v) => change(value.copyWith(scaleY: v)),
            ),
            _AdjustmentSlider(
              label: '旋转角度',
              value: value.rotation,
              min: -180,
              max: 180,
              suffix: '°',
              onChanged: (v) => change(value.copyWith(rotation: v)),
            ),
            _AdjustmentSlider(
              label: '左右位置',
              value: value.offsetX,
              min: -0.5,
              max: 0.5,
              onChanged: (v) => change(value.copyWith(offsetX: v)),
            ),
            _AdjustmentSlider(
              label: '上下位置',
              value: value.offsetY,
              min: -0.5,
              max: 0.5,
              onChanged: (v) => change(value.copyWith(offsetY: v)),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdjustmentSlider extends StatefulWidget {
  const _AdjustmentSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String suffix;

  @override
  State<_AdjustmentSlider> createState() => _AdjustmentSliderState();
}

class _AdjustmentSliderState extends State<_AdjustmentSlider> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(2));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _AdjustmentSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        (oldWidget.value - widget.value).abs() > 0.0001) {
      _controller.text = widget.value.toStringAsFixed(2);
    }
  }

  void _commit(String text) {
    final parsed = double.tryParse(text.trim().replaceAll(',', '.'));
    if (parsed == null) {
      _controller.text = widget.value.toStringAsFixed(2);
      return;
    }
    final next = parsed.clamp(widget.min, widget.max).toDouble();
    _controller.text = next.toStringAsFixed(2);
    widget.onChanged(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 345,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(widget.label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              value: widget.value.clamp(widget.min, widget.max).toDouble(),
              min: widget.min,
              max: widget.max,
              onChanged: widget.onChanged,
            ),
          ),
          SizedBox(
            width: 82,
            height: 36,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
                suffixText: widget.suffix.isEmpty ? null : widget.suffix,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _commit,
              onTapOutside: (_) {
                _commit(_controller.text);
                _focusNode.unfocus();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.path, required this.compact});

  final String? path;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 8 : 10),
      child: AspectRatio(
        // Match the native KZB canvas so the preview shows the actual
        // center-crop that will appear across the ultra-wide display.
        aspectRatio: ImageProbe.ultraClearWidth / ImageProbe.ultraClearHeight,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xff161a1d)),
          child: path == null
              ? const Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    color: Color(0xff6f777d),
                    size: 22,
                  ),
                )
              : Image.file(File(path!), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

enum _ResourcePreviewKind {
  wideDark,
  wideLight,
  lightAmbient,
  mapMask,
  dimDark,
  dimLight,
  maskDark,
  maskLight,
  vcdDark,
  vcdLight,
  ridDark,
  ridLight,
}

class _ResourcePreviewSpec {
  const _ResourcePreviewSpec(
    this.kind,
    this.title,
    this.size,
    this.description,
  );

  final _ResourcePreviewKind kind;
  final String title;
  final String size;
  final String description;

  double get aspectRatio => switch (kind) {
        _ResourcePreviewKind.dimDark ||
        _ResourcePreviewKind.dimLight ||
        _ResourcePreviewKind.vcdDark ||
        _ResourcePreviewKind.vcdLight =>
          3950 / 1320,
        _ResourcePreviewKind.maskDark ||
        _ResourcePreviewKind.maskLight =>
          2198 / 367,
        _ResourcePreviewKind.ridDark ||
        _ResourcePreviewKind.ridLight =>
          1920 / 1080,
        _ => 8960 / 1320,
      };
}

class _ResourcePreviewPanel extends StatelessWidget {
  const _ResourcePreviewPanel({
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.lightAdjustment,
    required this.darkAdjustment,
    required this.hasRid,
  });

  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final _CanvasAdjustment lightAdjustment;
  final _CanvasAdjustment darkAdjustment;
  final bool hasRid;

  static const _baseSpecs = <_ResourcePreviewSpec>[
    _ResourcePreviewSpec(
      _ResourcePreviewKind.wideDark,
      '深色完整壁纸',
      '8960 × 1320',
      '车机深色模式最终效果',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.wideLight,
      '浅色完整壁纸',
      '8960 × 1320',
      '车机浅色模式最终效果',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.lightAmbient,
      '浅色氛围背景',
      '8960 × 1320',
      '浅色模式模糊背景效果',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.mapMask,
      '地图遮罩预览',
      '8960 × 1320',
      '地图视图叠层效果',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.dimDark,
      '深色右屏背景',
      '3950 × 1320',
      '车机右屏深色裁剪',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.dimLight,
      '浅色右屏背景',
      '3950 × 1320',
      '车机右屏浅色裁剪',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.maskDark,
      '深色透明预览',
      '2198 × 367',
      '带原厂形状遮罩的深色预览图',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.maskLight,
      '浅色透明预览',
      '2198 × 367',
      '带原厂形状遮罩的浅色预览图',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.vcdDark,
      '深色右屏裁剪',
      '3950 × 1320',
      '车机右屏深色显示范围',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.vcdLight,
      '浅色右屏裁剪',
      '3950 × 1320',
      '车机右屏浅色显示范围',
    ),
  ];

  static const _ridSpecs = <_ResourcePreviewSpec>[
    _ResourcePreviewSpec(
      _ResourcePreviewKind.ridDark,
      '深色屏保预览',
      '1920 × 1080',
      '深色 RID 屏保显示范围',
    ),
    _ResourcePreviewSpec(
      _ResourcePreviewKind.ridLight,
      '浅色屏保预览',
      '1920 × 1080',
      '浅色 RID 屏保显示范围',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final specs = <_ResourcePreviewSpec>[
      ..._baseSpecs,
      if (hasRid) ..._ridSpecs,
    ];
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PanelHeader(
            icon: CupertinoIcons.eye,
            title: '实时预览效果',
            trailing: '车机实际资源',
          ),
          const SizedBox(height: 5),
          Text(
            '展示最终资源包会使用的主要图层；所有画面都由当前 8960×1320 母图实时派生。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              final width = columns == 2
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: specs
                    .map(
                      (spec) => SizedBox(
                        width: width,
                        child: _ResourcePreviewCard(
                          spec: spec,
                          lightImagePath: lightImagePath,
                          darkImagePath: darkImagePath,
                          lightProbe: lightProbe,
                          darkProbe: darkProbe,
                          lightAdjustment: lightAdjustment,
                          darkAdjustment: darkAdjustment,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ResourcePreviewCard extends StatelessWidget {
  const _ResourcePreviewCard({
    required this.spec,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.lightAdjustment,
    required this.darkAdjustment,
  });

  final _ResourcePreviewSpec spec;
  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final _CanvasAdjustment lightAdjustment;
  final _CanvasAdjustment darkAdjustment;

  void _showLarge(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${spec.title} · ${spec.size}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(CupertinoIcons.xmark),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: AspectRatio(
                    aspectRatio: spec.aspectRatio,
                    child: _ResourcePreviewImage(
                      spec: spec,
                      lightImagePath: lightImagePath,
                      darkImagePath: darkImagePath,
                      lightProbe: lightProbe,
                      darkProbe: darkProbe,
                      lightAdjustment: lightAdjustment,
                      darkAdjustment: darkAdjustment,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _AppColors.field,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _AppColors.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showLarge(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          spec.title,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      Text(
                        spec.size,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _AppColors.tertiaryText,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spec.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AppColors.secondaryText,
                        ),
                  ),
                ],
              ),
            ),
            AspectRatio(
              aspectRatio: spec.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _ResourcePreviewImage(
                    spec: spec,
                    lightImagePath: lightImagePath,
                    darkImagePath: darkImagePath,
                    lightProbe: lightProbe,
                    darkProbe: darkProbe,
                    lightAdjustment: lightAdjustment,
                    darkAdjustment: darkAdjustment,
                  ),
                  Positioned(
                    right: 7,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xaa111827),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        child: Text(
                          '点击放大',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourcePreviewImage extends StatelessWidget {
  const _ResourcePreviewImage({
    required this.spec,
    required this.lightImagePath,
    required this.darkImagePath,
    required this.lightProbe,
    required this.darkProbe,
    required this.lightAdjustment,
    required this.darkAdjustment,
  });

  final _ResourcePreviewSpec spec;
  final String? lightImagePath;
  final String? darkImagePath;
  final ImageProbe? lightProbe;
  final ImageProbe? darkProbe;
  final _CanvasAdjustment lightAdjustment;
  final _CanvasAdjustment darkAdjustment;

  bool get _usesDark => switch (spec.kind) {
        _ResourcePreviewKind.wideDark ||
        _ResourcePreviewKind.dimDark ||
        _ResourcePreviewKind.maskDark ||
        _ResourcePreviewKind.vcdDark ||
        _ResourcePreviewKind.ridDark =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final path = _usesDark ? darkImagePath : lightImagePath;
    final probe = _usesDark ? darkProbe : lightProbe;
    final adjustment = _usesDark ? darkAdjustment : lightAdjustment;
    final crop = switch (spec.kind) {
      _ResourcePreviewKind.dimDark ||
      _ResourcePreviewKind.dimLight ||
      _ResourcePreviewKind.vcdDark ||
      _ResourcePreviewKind.vcdLight =>
        const Rect.fromLTWH(5010, 0, 3950, 1320),
      _ResourcePreviewKind.ridDark ||
      _ResourcePreviewKind.ridLight =>
        const Rect.fromLTWH(3520, 120, 1920, 1080),
      _ => const Rect.fromLTWH(0, 0, 8960, 1320),
    };
    Widget image = _WallpaperCropImage(
      path: path,
      probe: probe,
      adjustment: adjustment,
      crop: crop,
    );

    if (spec.kind == _ResourcePreviewKind.lightAmbient) {
      image = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: image,
          ),
          const ColoredBox(color: Color(0x29ffffff)),
        ],
      );
    } else if (spec.kind == _ResourcePreviewKind.mapMask) {
      image = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          image,
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Color(0xb30f172a),
                  Color(0x2e0f172a),
                  Color(0xc70f172a),
                ],
                stops: <double>[0, 0.35, 1],
              ),
            ),
          ),
        ],
      );
    } else if (spec.kind == _ResourcePreviewKind.dimDark ||
        spec.kind == _ResourcePreviewKind.dimLight) {
      final dark = spec.kind == _ResourcePreviewKind.dimDark;
      image = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          image,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const <Color>[Color(0x80000000), Color(0xcc000000)]
                    : const <Color>[Color(0x1affffff), Color(0x8cffffff)],
              ),
            ),
          ),
        ],
      );
    } else if (spec.kind == _ResourcePreviewKind.maskDark ||
        spec.kind == _ResourcePreviewKind.maskLight) {
      image = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Color(0xff090d12)),
          _AlphaMaskedPreview(
            maskAsset: spec.kind == _ResourcePreviewKind.maskDark
                ? 'packager/preview_masks/dark_preview_mask.png'
                : 'packager/preview_masks/light_preview_mask.png',
            child: image,
          ),
        ],
      );
    } else if (spec.kind == _ResourcePreviewKind.wideDark ||
        spec.kind == _ResourcePreviewKind.wideLight) {
      final dark = spec.kind == _ResourcePreviewKind.wideDark;
      image = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          image,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.25, 0),
                end: Alignment.centerRight,
                colors: dark
                    ? const <Color>[Color(0x00000000), Color(0x9e030712)]
                    : const <Color>[Color(0x00ffffff), Color(0x6bffffff)],
              ),
            ),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xff10151c)),
      child: image,
    );
  }
}

class _WallpaperCropImage extends StatelessWidget {
  const _WallpaperCropImage({
    required this.path,
    required this.probe,
    required this.adjustment,
    required this.crop,
  });

  final String? path;
  final ImageProbe? probe;
  final _CanvasAdjustment adjustment;
  final Rect crop;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return const Center(
        child: Icon(CupertinoIcons.photo, color: Color(0xff6f777d)),
      );
    }
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / crop.width;
          final fullWidth = 8960 * scale;
          final fullHeight = 1320 * scale;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Positioned(
                left: -crop.left * scale,
                top: -crop.top * scale,
                width: fullWidth,
                height: fullHeight,
                child: _CanvasLayeredImage(
                  path: path!,
                  probe: probe,
                  adjustment: adjustment,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlphaMaskedPreview extends StatelessWidget {
  const _AlphaMaskedPreview({
    required this.maskAsset,
    required this.child,
  });

  final String maskAsset;
  final Widget child;

  static final Map<String, Future<ui.Image>> _cache =
      <String, Future<ui.Image>>{};

  static Future<ui.Image> _load(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    final future = _cache.putIfAbsent(maskAsset, () => _load(maskAsset));
    return FutureBuilder<ui.Image>(
      future: future,
      builder: (context, snapshot) {
        final mask = snapshot.data;
        if (mask == null) {
          return child;
        }
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final matrix = Matrix4.identity()
              ..scale(
                bounds.width / mask.width,
                bounds.height / mask.height,
              );
            return ui.ImageShader(
              mask,
              TileMode.clamp,
              TileMode.clamp,
              matrix.storage,
            );
          },
          child: child,
        );
      },
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.summary,
    required this.result,
    required this.packagePath,
    required this.outputFolderPath,
    required this.onOpenOutputFolder,
  });

  final PackageReportSummary? summary;
  final PackageBuildResult? result;
  final String? packagePath;
  final String? outputFolderPath;
  final VoidCallback onOpenOutputFolder;

  @override
  Widget build(BuildContext context) {
    final checks = summary?.checks ?? const <ReportCheck>[];
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelHeader(
            icon: CupertinoIcons.checkmark_shield,
            title: '校验报告',
            trailing: result == null ? 'report.json' : null,
            trailingWidget: result == null
                ? null
                : _IconTextButton(
                    icon: CupertinoIcons.folder,
                    label: '打开输出文件夹',
                    onPressed: onOpenOutputFolder,
                  ),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 12),
            if (packagePath != null)
              _PathLine(label: '最终产物', value: packagePath!),
            _PathLine(label: 'OTA zip', value: result!.outputZipPath),
            _PathLine(label: 'report', value: result!.reportPath),
            if (outputFolderPath != null)
              _PathLine(label: '文件夹', value: outputFolderPath!),
          ],
          const SizedBox(height: 14),
          if (checks.isEmpty)
            const _EmptyState(icon: CupertinoIcons.doc_text, text: '暂无报告')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 820 ? 2 : 1;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: checks
                      .map(
                        (check) => SizedBox(
                          width: (constraints.maxWidth - (columns - 1) * 10) /
                              columns,
                          child: _CheckTile(check: check),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final ReportCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.passed ? _AppColors.success : _AppColors.danger;
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            check.passed
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.exclamationmark_circle_fill,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  check.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  check.detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _AppColors.secondaryText,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogPanel extends StatefulWidget {
  const _LogPanel({required this.logs});

  final List<String> logs;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final _scrollController = ScrollController();
  int _previousLogCount = 0;

  @override
  void didUpdateWidget(covariant _LogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != _previousLogCount) {
      _previousLogCount = widget.logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PanelHeader(
            icon: CupertinoIcons.doc_text,
            title: '日志',
            trailing: 'CLI',
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 108, maxHeight: 168),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _AppColors.terminal,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Text(
                widget.logs.isEmpty ? '等待开始打包' : widget.logs.join('\n'),
                style: const TextStyle(
                  color: Color(0xffe8eeee),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeLibraryPanel extends StatelessWidget {
  const _ThemeLibraryPanel({
    required this.themes,
    required this.onDeleteTheme,
    required this.onOpenThemeFolder,
    required this.onRefresh,
  });

  final List<ThemeLibraryEntry> themes;
  final ValueChanged<ThemeLibraryEntry> onDeleteTheme;
  final ValueChanged<ThemeLibraryEntry> onOpenThemeFolder;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelHeader(
            icon: CupertinoIcons.square_stack_3d_up,
            title: '本地主题库',
            trailingWidget: IconButton(
              tooltip: '刷新主题库',
              onPressed: onRefresh,
              icon: const Icon(CupertinoIcons.refresh, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          if (themes.isEmpty)
            const _EmptyState(icon: CupertinoIcons.archivebox, text: '无历史主题')
          else
            ...themes.map(
              (entry) => _ThemeTile(
                entry: entry,
                onDelete: () => onDeleteTheme(entry),
                onOpenFolder: () => onOpenThemeFolder(entry),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.entry,
    required this.onDelete,
    required this.onOpenFolder,
  });

  final ThemeLibraryEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        entry.allChecksPassed ? _AppColors.success : _AppColors.danger;
    return LayoutBuilder(
      builder: (context, constraints) {
        final thumbWidth = constraints.maxWidth < 390 ? 118.0 : 166.0;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _AppColors.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _AppColors.separator),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: thumbWidth,
                child: Column(
                  children: <Widget>[
                    _Thumb(path: entry.lightThumbnailPath),
                    const SizedBox(height: 6),
                    _Thumb(path: entry.darkThumbnailPath),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(entry.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _AppColors.secondaryText,
                          ),
                    ),
                    if (entry.author.isNotEmpty)
                      Text(
                        entry.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (entry.notes.isNotEmpty)
                      Text(
                        entry.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _AppColors.secondaryText,
                            ),
                      ),
                    const SizedBox(height: 6),
                    _StatusPill(
                      text: entry.allChecksPassed ? '校验通过' : '校验异常',
                      color: statusColor,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '打开主题文件夹',
                onPressed: onOpenFolder,
                icon: const Icon(CupertinoIcons.folder, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              IconButton(
                tooltip: '删除主题',
                onPressed: onDelete,
                icon: const Icon(CupertinoIcons.delete, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: AspectRatio(
        aspectRatio: 2198 / 367,
        child: File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover)
            : const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xffd9dddc)),
              ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    this.trailing,
    this.trailingWidget,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: _AppColors.secondaryText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
          ),
        ),
        if (trailingWidget != null)
          trailingWidget!
        else if (trailing != null)
          Text(
            trailing!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _AppColors.tertiaryText,
                ),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    required this.padding,
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? _AppColors.accentWash : _AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? _AppColors.accent : _AppColors.separator,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0d000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _IconTextButton extends StatelessWidget {
  const _IconTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  const _PathLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AppColors.secondaryText,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              redactSensitivePaths(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _AppColors.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _AppColors.separator),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: _AppColors.tertiaryText, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AppColors.secondaryText,
                ),
          ),
        ],
      ),
    );
  }
}

class _BuildPaths {
  const _BuildPaths({
    required this.outputZipPath,
    required this.workDirPath,
    required this.reportPath,
  });

  final String outputZipPath;
  final String workDirPath;
  final String reportPath;
}

class _BuildResources {
  const _BuildResources({
    required this.inputZipPath,
    required this.astcencPath,
    required this.lightDimMaskPath,
    required this.darkDimMaskPath,
  });

  final String? inputZipPath;
  final String? astcencPath;
  final String? lightDimMaskPath;
  final String? darkDimMaskPath;
}

class _AppColors {
  static const chrome = Color(0xfff3f2ef);
  static const sidebar = Color(0xfffaf9f6);
  static const surface = Color(0xffffffff);
  static const field = Color(0xfff6f6f3);
  static const separator = Color(0xffdedbd4);
  static const chromeLine = Color(0xffd0ccc2);
  static const terminal = Color(0xff14191d);
  static const accent = Color(0xff00616b);
  static const accentWash = Color(0xffe5f3f2);
  static const success = Color(0xff18864b);
  static const warning = Color(0xffa86700);
  static const danger = Color(0xffb3261e);
  static const secondaryText = Color(0xff5c666c);
  static const tertiaryText = Color(0xff879098);
}

String _timestamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String? _envPath(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
