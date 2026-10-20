import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/domain/models/clip.dart';
import 'package:tgi_video_editor/domain/models/project.dart';

import 'support/render_fixture.dart';

void main() {
  final fixture = RenderFixture();
  setUp(fixture.open);
  tearDown(fixture.close);

  test(
    'fixed frames follow preview layer order and alpha compositing',
    () async {
      final red = await fixture.color('red');
      final blue = await fixture.color('blue');
      final project = fixture.project(
        [red, blue],
        [fixture.clip(blue).copyWith(opacity: .5), fixture.clip(red)],
      );
      expect(project.visualClipsAt(Duration.zero).map((c) => c.id), [
        'red',
        'blue',
      ]);
      final output = await fixture.export(project, 'alpha');
      final pixel = await fixture.pixel(output, .5);
      expect(pixel[0], closeTo(127, 18));
      expect(pixel[1], lessThan(18));
      expect(pixel[2], closeTo(127, 18));
      final reversed = await fixture.export(
        project.reorderTrack('blue', 1),
        'order',
      );
      expect((await fixture.pixel(reversed, .5))[0], greaterThan(230));
    },
  );

  test('fixed fade frames reveal the underlying layer at both ends', () async {
    final red = await fixture.color('red');
    final blue = await fixture.color('blue');
    final output = await fixture.export(
      fixture.project(
        [red, blue],
        [
          fixture
              .clip(blue)
              .copyWith(
                fadeIn: const Duration(milliseconds: 500),
                fadeOut: const Duration(milliseconds: 500),
              ),
          fixture.clip(red),
        ],
      ),
      'fades',
    );
    for (final time in [.1, .9]) {
      final pixel = await fixture.pixel(output, time);
      expect(pixel[0], greaterThan(180));
      expect(pixel[2], lessThan(75));
    }
    expect((await fixture.pixel(output, .5))[2], greaterThan(230));
  });

  test('opacity keyframes match the linear model used by preview', () async {
    final red = await fixture.color('red');
    final blue = await fixture.color('blue');
    final animated = fixture
        .clip(blue)
        .copyWith(
          keyframes: const [
            ClipKeyframe(
              id: 'a',
              property: ClipKeyframeProperty.opacity,
              time: 0,
              value: 0,
            ),
            ClipKeyframe(
              id: 'b',
              property: ClipKeyframeProperty.opacity,
              time: 1,
              value: 1,
            ),
          ],
        );
    final output = await fixture.export(
      fixture.project([red, blue], [animated, fixture.clip(red)]),
      'keys',
    );
    for (final time in [.25, .5, .75]) {
      final alpha = animated.keyframedValue(ClipKeyframeProperty.opacity, time);
      final pixel = await fixture.pixel(output, time);
      expect(pixel[2], closeTo(255 * alpha, 20));
      expect(pixel[0], closeTo(255 * (1 - alpha), 20));
    }
  });

  test('chroma removes a solid key and preserves a different color', () async {
    final red = await fixture.color('red');
    final green = await fixture.color('lime');
    final blue = await fixture.color('blue');
    for (final foreground in [green, blue]) {
      final output = await fixture.export(
        fixture.project(
          [red, foreground],
          [
            fixture
                .clip(foreground)
                .copyWith(
                  chromaKeyEnabled: true,
                  chromaKeyColor: 0xFF00FF00,
                  chromaKeySimilarity: .15,
                  chromaKeyBlend: .05,
                ),
            fixture.clip(red),
          ],
        ),
        'chroma_${foreground.id}',
      );
      final pixel = await fixture.pixel(output, .5);
      expect(pixel[foreground == green ? 0 : 2], greaterThan(225));
      expect(pixel[1], lessThan(25));
    }
  });

  for (final shape in VideoMaskShape.values) {
    test(
      'fixed ${shape.name} darken mask affects inside, outside and inversion',
      () async {
        final red = await fixture.color('red');
        for (final inverted in [false, true]) {
          final masked = fixture
              .clip(red)
              .copyWith(
                overlayScale: 1,
                maskEnabled: true,
                maskShape: shape,
                maskEffect: VideoMaskEffect.darken,
                maskWidth: .5,
                maskHeight: .5,
                maskFeather: .01,
                maskIntensity: 1,
                maskInverted: inverted,
              );
          final output = await fixture.export(
            fixture.project([red], [masked]),
            'mask_${shape.name}_$inverted',
          );
          final inside = await fixture.pixel(output, .5);
          final outside = await fixture.pixel(output, .5, x: 4, y: 4);
          expect(inside[0], inverted ? greaterThan(225) : lessThan(190));
          expect(outside[0], inverted ? lessThan(190) : greaterThan(225));
        }
      },
    );
  }
}
