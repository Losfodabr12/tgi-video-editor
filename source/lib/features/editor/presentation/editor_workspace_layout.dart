part of 'editor_screen.dart';

class _EditorWorkspaceLayout {
  const _EditorWorkspaceLayout({
    required this.leftPanelFraction,
    required this.propertiesPanelFraction,
    required this.previewPanelFraction,
    required this.timelineFocusMode,
  });

  final double leftPanelFraction;
  final double propertiesPanelFraction;
  final double previewPanelFraction;
  final bool timelineFocusMode;

  factory _EditorWorkspaceLayout.fromJson(Map<String, dynamic> json) {
    return _EditorWorkspaceLayout(
      leftPanelFraction: _readDouble(
        json,
        'leftPanelFraction',
        _defaultLeftPanelFraction,
      ),
      propertiesPanelFraction: _readDouble(
        json,
        'propertiesPanelFraction',
        _defaultPropertiesPanelFraction,
      ),
      previewPanelFraction: _readDouble(
        json,
        'previewPanelFraction',
        _defaultPreviewPanelFraction,
      ),
      timelineFocusMode: json['timelineFocusMode'] is bool
          ? json['timelineFocusMode'] as bool
          : false,
    ).normalized(resetVerticalSplit: json['layoutVersion'] != 2);
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    if (value is num && value.isFinite) {
      return value.toDouble();
    }
    return fallback;
  }

  _EditorWorkspaceLayout normalized({bool resetVerticalSplit = false}) {
    var properties = propertiesPanelFraction
        .clamp(_minPropertiesPanelFraction, _maxPropertiesPanelFraction)
        .toDouble();
    var maxLeft = math.min(
      _maxLeftPanelFraction,
      1 - _minCenterPanelFraction - properties,
    );
    var left = leftPanelFraction
        .clamp(_minLeftPanelFraction, maxLeft)
        .toDouble();
    final maxProperties = math.min(
      _maxPropertiesPanelFraction,
      1 - _minCenterPanelFraction - left,
    );
    properties = properties
        .clamp(_minPropertiesPanelFraction, maxProperties)
        .toDouble();
    maxLeft = math.min(
      _maxLeftPanelFraction,
      1 - _minCenterPanelFraction - properties,
    );
    left = left.clamp(_minLeftPanelFraction, maxLeft).toDouble();

    return _EditorWorkspaceLayout(
      leftPanelFraction: left,
      propertiesPanelFraction: properties,
      previewPanelFraction:
          (resetVerticalSplit
                  ? _defaultPreviewPanelFraction
                  : previewPanelFraction)
              .clamp(0.28, 0.68)
              .toDouble(),
      timelineFocusMode: timelineFocusMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'layoutVersion': 2,
      'leftPanelFraction': leftPanelFraction,
      'propertiesPanelFraction': propertiesPanelFraction,
      'previewPanelFraction': previewPanelFraction,
      'timelineFocusMode': timelineFocusMode,
    };
  }
}

class _EditorWorkspaceLayoutStore {
  const _EditorWorkspaceLayoutStore._();

  static Future<_EditorWorkspaceLayout?> load() async {
    try {
      final file = File(_statePath);
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return _EditorWorkspaceLayout.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(_EditorWorkspaceLayout layout) async {
    try {
      final file = File(_statePath);
      await file.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(layout.toJson()));
    } catch (_) {
      // Layout persistence should never block editing.
    }
  }

  static String get _statePath {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return [base, 'TGIAPP', 'editor_layout.json'].join(Platform.pathSeparator);
  }
}
