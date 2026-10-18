import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgi_video_editor/features/editor/presentation/widgets/video_preview_panel.dart';

void main() {
  testWidgets('video preview transport keeps a compact vertical footprint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: VideoPreviewPanel(
              item: null,
              timelineDuration: const Duration(seconds: 30),
              onTimelineSeek: (_) {},
              onTimelinePlaybackChanged: (_) {},
              transportLeadingControl: const SizedBox(width: 180, height: 32),
              transportTrailingControl: const SizedBox.square(dimension: 32),
            ),
          ),
        ),
      ),
    );

    final transport = find.byKey(
      const ValueKey('video_preview_transport_controls'),
    );
    expect(transport, findsOneWidget);
    expect(tester.getSize(transport).height, lessThanOrEqualTo(76));
    expect(find.byTooltip('Retroceder 5 segundos'), findsOneWidget);
    expect(find.byTooltip('Avançar 5 segundos'), findsOneWidget);
  });

  testWidgets('empty preview offers a direct media import action', (
    tester,
  ) async {
    var importRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: VideoPreviewPanel(
              item: null,
              onImportRequested: () => importRequests++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Nenhum vídeo ou imagem na timeline'), findsOneWidget);
    expect(find.text('Adicionar vídeo ou imagem'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preview_add_media_button')));
    expect(importRequests, 1);
  });
}
