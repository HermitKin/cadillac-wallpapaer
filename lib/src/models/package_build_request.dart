class PackageBuildRequest {
  const PackageBuildRequest({
    required this.lightImagePath,
    required this.darkImagePath,
    required this.outputZipPath,
    required this.workDirPath,
    required this.reportPath,
    this.inputZipPath,
    this.astcencPath,
    this.lightDimMaskPath,
    this.darkDimMaskPath,
    this.quality = '-exhaustive',
    this.previewBlur = 0,
    this.sharpen = true,
    this.decodeVerify = true,
    this.maxStitchMae = 4.0,
    this.lightZoom = 1.0,
    this.lightScaleX = 1.0,
    this.lightScaleY = 1.0,
    this.lightOffsetX = 0.0,
    this.lightOffsetY = 0.0,
    this.lightRotation = 0.0,
    this.darkZoom = 1.0,
    this.darkScaleX = 1.0,
    this.darkScaleY = 1.0,
    this.darkOffsetX = 0.0,
    this.darkOffsetY = 0.0,
    this.darkRotation = 0.0,
  });

  final String lightImagePath;
  final String darkImagePath;
  final String outputZipPath;
  final String workDirPath;
  final String reportPath;
  final String? inputZipPath;
  final String? astcencPath;
  final String? lightDimMaskPath;
  final String? darkDimMaskPath;
  final String quality;
  final double previewBlur;
  final bool sharpen;
  final bool decodeVerify;
  final double maxStitchMae;
  final double lightZoom;
  final double lightScaleX;
  final double lightScaleY;
  final double lightOffsetX;
  final double lightOffsetY;
  final double lightRotation;
  final double darkZoom;
  final double darkScaleX;
  final double darkScaleY;
  final double darkOffsetX;
  final double darkOffsetY;
  final double darkRotation;

  List<String> toCliArguments() {
    return <String>[
      '--light-image',
      lightImagePath,
      '--dark-image',
      darkImagePath,
      '--output-zip',
      outputZipPath,
      '--work-dir',
      workDirPath,
      '--report',
      reportPath,
      if (inputZipPath != null) ...<String>['--input-zip', inputZipPath!],
      if (astcencPath != null) ...<String>['--astcenc', astcencPath!],
      if (lightDimMaskPath != null) ...<String>[
        '--light-dim-mask',
        lightDimMaskPath!,
      ],
      if (darkDimMaskPath != null) ...<String>[
        '--dark-dim-mask',
        darkDimMaskPath!,
      ],
      '--quality=$quality',
      '--preview-blur',
      previewBlur.toString(),
      '--max-stitch-mae',
      maxStitchMae.toString(),
      '--light-zoom',
      lightZoom.toString(),
      '--light-scale-x',
      lightScaleX.toString(),
      '--light-scale-y',
      lightScaleY.toString(),
      '--light-offset-x',
      lightOffsetX.toString(),
      '--light-offset-y',
      lightOffsetY.toString(),
      '--light-rotation',
      lightRotation.toString(),
      '--dark-zoom',
      darkZoom.toString(),
      '--dark-scale-x',
      darkScaleX.toString(),
      '--dark-scale-y',
      darkScaleY.toString(),
      '--dark-offset-x',
      darkOffsetX.toString(),
      '--dark-offset-y',
      darkOffsetY.toString(),
      '--dark-rotation',
      darkRotation.toString(),
      if (!sharpen) '--no-sharpen',
      if (!decodeVerify) '--skip-decode-verify',
    ];
  }
}
