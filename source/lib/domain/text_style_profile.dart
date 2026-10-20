/// Opt-in font preset for newly created text. Stored in v14's existing
/// fontFamily field; legacy font names keep their original rendering.
abstract final class NewTextStyle {
  static const fontFamily = 'Lato Caption';
  static const textColor = 0xFFFFFFFF;
  static const backgroundColor = 0x00000000;
  static const outlineWidth = 2.0;
  static const shadowColor = 0x73000000;

  static bool appliesTo(String family) => family == fontFamily;
}
