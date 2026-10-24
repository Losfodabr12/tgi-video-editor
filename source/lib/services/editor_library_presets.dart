import '../domain/models/clip.dart';
import '../domain/models/timeline_transition.dart';
import '../domain/text_style_profile.dart';

class EditorTitlePreset {
  const EditorTitlePreset(
    this.id,
    this.name,
    this.text,
    this.fontFamily,
    this.fontSize,
    this.animation, {
    this.caption = false,
  });
  final String id, name, text, fontFamily;
  final double fontSize;
  final TextClipAnimation animation;
  final bool caption;
}

const editorTitlePresets = [
  EditorTitlePreset(
    'title_simple',
    'Título simples',
    'Seu título',
    NewTextStyle.fontFamily,
    48,
    TextClipAnimation.none,
  ),
  EditorTitlePreset(
    'title_caption',
    'Legenda',
    'Sua legenda',
    NewTextStyle.fontFamily,
    36,
    TextClipAnimation.fade,
    caption: true,
  ),
  EditorTitlePreset(
    'title_highlight',
    'Destaque',
    'EM DESTAQUE',
    'Bebas Neue',
    64,
    TextClipAnimation.rise,
  ),
];

const editorTransitionPresets = [
  TimelineTransitionAsset(
    id: 'preset_fade_black',
    name: 'Fade para preto',
    preset: TimelineTransitionPreset.fade,
    color: 0xFF000000,
    duration: Duration(milliseconds: 800),
  ),
  TimelineTransitionAsset(
    id: 'preset_flash_white',
    name: 'Flash branco',
    preset: TimelineTransitionPreset.flash,
    color: 0xFFFFFFFF,
    intensity: .95,
    duration: Duration(milliseconds: 420),
  ),
  TimelineTransitionAsset(
    id: 'preset_dissolve',
    name: 'Dissolve suave',
    preset: TimelineTransitionPreset.dissolve,
    duration: Duration(milliseconds: 900),
  ),
  TimelineTransitionAsset(
    id: 'preset_blur',
    name: 'Desfoque cinema',
    preset: TimelineTransitionPreset.blur,
    intensity: .86,
    duration: Duration(milliseconds: 720),
  ),
  TimelineTransitionAsset(
    id: 'preset_glitch',
    name: 'Glitch RGB',
    preset: TimelineTransitionPreset.glitch,
    color: 0xFFFF2AA3,
    intensity: .9,
    duration: Duration(milliseconds: 520),
  ),
  TimelineTransitionAsset(
    id: 'preset_spin',
    name: 'Giro rápido',
    preset: TimelineTransitionPreset.spin,
    duration: Duration(milliseconds: 620),
  ),
  TimelineTransitionAsset(
    id: 'preset_pixelate',
    name: 'Pixelado digital',
    preset: TimelineTransitionPreset.pixelate,
    duration: Duration(milliseconds: 680),
  ),
  TimelineTransitionAsset(
    id: 'preset_zoom',
    name: 'Zoom impacto',
    preset: TimelineTransitionPreset.zoom,
    duration: Duration(milliseconds: 650),
  ),
  TimelineTransitionAsset(
    id: 'preset_wipe',
    name: 'Wipe lateral',
    preset: TimelineTransitionPreset.wipe,
    direction: TimelineTransitionDirection.rightToLeft,
    color: 0xFF05070A,
    intensity: .96,
    duration: Duration(milliseconds: 760),
  ),
  TimelineTransitionAsset(
    id: 'preset_light_leak',
    name: 'Light leak quente',
    preset: TimelineTransitionPreset.lightLeak,
    direction: TimelineTransitionDirection.leftToRight,
    color: 0xFFFF8A3D,
    intensity: .82,
    duration: Duration(milliseconds: 780),
  ),
];
