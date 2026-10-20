import '../../../../app/app_identity.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';

const _notificationDefaultAsset =
    'assets/notifications/notification_default.png';
const _notificationBirraAsset = 'assets/notifications/notification_birra.png';

enum TgiNotificationTone { standard, error }

class TgiMascotNotification extends StatelessWidget {
  const TgiMascotNotification({
    required this.message,
    required this.tone,
    this.onDismiss,
    this.compact = false,
    super.key,
  });

  final String message;
  final TgiNotificationTone tone;
  final VoidCallback? onDismiss;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isError = tone == TgiNotificationTone.error;
    final title = isError ? 'Atenção' : AppIdentity.name;
    final accentColor = isError ? TgiColors.accent : TgiColors.accent;
    final softAccent = isError ? TgiColors.accent : TgiColors.accentSoft;
    final borderColor = isError ? TgiColors.accent : TgiColors.accentDim;
    final backgroundColor = isError
        ? TgiColors.surfacePanel
        : TgiColors.surfacePanel.withValues(alpha: 0.98);
    final mascotSize = compact ? 56.0 : 72.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: mascotSize,
          height: mascotSize,
          child: kStandalone
              ? Icon(
                  isError ? Icons.error_outline : Icons.movie_outlined,
                  color: accentColor,
                  size: mascotSize * .6,
                )
              : Image.asset(
                  isError ? _notificationBirraAsset : _notificationDefaultAsset,
                  key: Key(
                    isError
                        ? 'tgi_notification_birra_character'
                        : 'tgi_notification_default_character',
                  ),
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  errorBuilder: (_, _, _) => Icon(
                    isError ? Icons.priority_high_rounded : Icons.bolt_outlined,
                    color: softAccent,
                    size: TgiIconSizes.lg,
                  ),
                ),
        ),
        const SizedBox(width: TgiSpacing.xs),
        Expanded(
          child: CustomPaint(
            painter: _SpeechBubblePainter(
              color: backgroundColor,
              borderColor: borderColor,
              shadowColor: accentColor.withValues(alpha: isError ? 0.18 : 0.12),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 20,
                compact ? 8 : 8,
                compact ? 8 : 12,
                compact ? 8 : 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isError
                            ? Icons.priority_high_rounded
                            : Icons.bolt_outlined,
                        color: softAccent,
                        size: TgiIconSizes.sm,
                      ),
                      const SizedBox(width: TgiSpacing.xs),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: softAccent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TgiSpacing.xxs),
                  Text(
                    message,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TgiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onDismiss != null) ...[
          const SizedBox(width: TgiSpacing.sm),
          IconButton(
            tooltip: 'Dispensar',
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
            color: TgiColors.textSecondary,
            style: IconButton.styleFrom(
              backgroundColor: TgiColors.background.withValues(alpha: 0.48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TgiRadii.md),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  const _SpeechBubblePainter({
    required this.color,
    required this.borderColor,
    required this.shadowColor,
  });

  final Color color;
  final Color borderColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    const tailWidth = 9.0;
    if (size.width <= tailWidth || size.height <= 0) {
      return;
    }
    final bubbleRect = Rect.fromLTWH(
      tailWidth,
      0,
      size.width - tailWidth,
      size.height,
    );
    final bubble = RRect.fromRectAndRadius(
      bubbleRect,
      const Radius.circular(TgiRadii.lg),
    );
    final tailTop = size.height * 0.58;
    final tailBottom = size.height * 0.78;
    final path = Path()
      ..addRRect(bubble)
      ..moveTo(tailWidth + 1, tailTop)
      ..lineTo(0, tailTop + 7)
      ..lineTo(tailWidth + 1, tailBottom)
      ..close();

    canvas.drawShadow(path, shadowColor, 10, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter oldDelegate) {
    return color != oldDelegate.color ||
        borderColor != oldDelegate.borderColor ||
        shadowColor != oldDelegate.shadowColor;
  }
}
