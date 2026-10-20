/// All product identity and integration policy lives here.
const kStandalone = bool.fromEnvironment(
  'EDITOR_STANDALONE',
  defaultValue: true,
);

abstract final class AppIdentity {
  static const iconBackgroundArgb = 0xFF121826;
  static const iconAccentArgb = 0xFF4C8DFF;
  static const name = String.fromEnvironment(
    'EDITOR_NAME',
    defaultValue: 'Frame Studio',
  );
  static const shortName = String.fromEnvironment(
    'EDITOR_SHORT_NAME',
    defaultValue: 'FRAME',
  );
  static const tagline = 'VIDEO EDITOR';
  // Retain existing user data; changing this requires an explicit data migration.
  static const dataDirectory = 'TGI_VIDEO_EDITOR';
  static const unixDataDirectory = '.tgi_video_editor';
}

void requireOnlineIntegrations() {
  if (kStandalone) {
    throw StateError(
      'Modo offline: importe um arquivo local. Instale os componentes com tool/setup_tools.ps1 antes de usar.',
    );
  }
}
