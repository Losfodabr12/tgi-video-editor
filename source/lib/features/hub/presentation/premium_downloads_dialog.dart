import '../../../app/app_identity.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../services/premium_download_service.dart';
import '../../../services/rewarded_access_service.dart';

Future<void> showPremiumDownloadsDialog(
  BuildContext context, {
  required bool hasPaidPlan,
  String? planLabel,
  VoidCallback? onWatchRewardAd,
  Future<void> Function()? onOpenPlans,
  VoidCallback? onAccessGranted,
}) {
  if (kStandalone) return Future<void>.value();
  return showDialog<void>(
    context: context,
    builder: (_) => PremiumDownloadsDialog(
      hasPaidPlan: hasPaidPlan,
      planLabel: planLabel ?? (hasPaidPlan ? 'Plano ativo' : 'Plano gratuito'),
      onWatchRewardAd: onWatchRewardAd,
      onOpenPlans: onOpenPlans,
      onAccessGranted: onAccessGranted,
      rewardedAccessManager: RewardedAccessService(),
    ),
  );
}

class PremiumDownloadsDialog extends StatefulWidget {
  const PremiumDownloadsDialog({
    required this.hasPaidPlan,
    required this.planLabel,
    this.downloadManager,
    this.onWatchRewardAd,
    this.onOpenPlans,
    this.onAccessGranted,
    this.rewardedAccessManager,
    super.key,
  });

  final bool hasPaidPlan;
  final String planLabel;
  final PremiumDownloadManager? downloadManager;
  final VoidCallback? onWatchRewardAd;
  final Future<void> Function()? onOpenPlans;
  final VoidCallback? onAccessGranted;
  final RewardedAccessManager? rewardedAccessManager;

  @override
  State<PremiumDownloadsDialog> createState() => _PremiumDownloadsDialogState();
}

class _PremiumDownloadsDialogState extends State<PremiumDownloadsDialog> {
  late PremiumDownloadManager _manager;
  final Map<PremiumComponentId, bool> _installed = {};
  PremiumComponentId? _busy;
  PremiumDownloadCancellationToken? _cancellationToken;
  double? _progress;
  String? _message;
  bool _checkingRewardAvailability = false;
  bool _rewardAvailable = false;
  bool _watchingRewardAd = false;
  bool _temporaryAccessGranted = false;

  @override
  void initState() {
    super.initState();
    _manager =
        widget.downloadManager ??
        PremiumDownloadService(hasPaidPlan: widget.hasPaidPlan);
    _rewardAvailable = widget.onWatchRewardAd != null;
    unawaited(_refresh());
    if (widget.rewardedAccessManager != null && !widget.hasPaidPlan) {
      unawaited(_checkRewardAvailability());
    }
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    widget.rewardedAccessManager?.close();
    super.dispose();
  }

  Future<void> _checkRewardAvailability() async {
    setState(() => _checkingRewardAvailability = true);
    final available = await widget.rewardedAccessManager!.isAvailable();
    if (!mounted) return;
    setState(() {
      _checkingRewardAvailability = false;
      _rewardAvailable = available;
    });
  }

  Future<void> _refresh() async {
    final installed = <PremiumComponentId, bool>{};
    for (final info in premiumComponentCatalog) {
      installed[info.id] = await _manager.isInstalled(info.id);
    }
    if (mounted) setState(() => _installed.addAll(installed));
  }

  @override
  Widget build(BuildContext context) {
    final paid = widget.hasPaidPlan || _temporaryAccessGranted;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: TgiColors.surfacePanel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.download_for_offline_outlined,
                    color: paid ? TgiColors.accent : TgiColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Recursos e downloads',
                      style: TextStyle(
                        color: TgiColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                paid
                    ? '${widget.planLabel}: recursos liberados nesta conta.'
                    : 'Plano gratuito: exportacao ate 2K. Libere tudo permanentemente por R\$ 15, sem mensalidade.',
                style: const TextStyle(color: TgiColors.textMuted),
              ),
              if (!paid) ...[const SizedBox(height: 14), _rewardAdCard()],
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  key: const Key('premium_downloads_area'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: paid
                        ? TgiColors.backgroundDeep
                        : TgiColors.textMuted.withValues(alpha: 0.10),
                    border: Border.all(
                      color: paid ? TgiColors.accent : TgiColors.borderStrong,
                    ),
                    borderRadius: BorderRadius.circular(TgiRadii.lg),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final info in premiumComponentCatalog) ...[
                        _componentCard(info, paid: paid),
                        const SizedBox(height: 10),
                      ],
                      _featureCard(
                        icon: Icons.high_quality_outlined,
                        title: 'Exportacao de video em 4K',
                        description: paid
                            ? 'Ativa no seu plano. Nao precisa baixar nada.'
                            : 'Bloqueada no plano gratuito. 2K e resolucoes menores continuam liberadas.',
                        paid: paid,
                      ),
                    ],
                  ),
                ),
              ),
              if (_progress != null) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(value: _progress),
              ],
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: const TextStyle(color: TgiColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _rewardAdCard() {
    return Container(
      key: const Key('reward_ad_card'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgiColors.accent.withValues(alpha: 0.08),
        border: Border.all(color: TgiColors.accent.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.ondemand_video_rounded, color: TgiColors.accent),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Experimente os recursos por 24 horas',
                      style: TextStyle(
                        color: TgiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Assista voluntariamente ao anuncio completo. A rede confirma a visualizacao ao servidor antes da liberacao.',
                      style: TextStyle(
                        color: TgiColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('open_tgi_plans'),
                onPressed: () => unawaited(_openPlans()),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Plano permanente · R\$ 15'),
              ),
              ElevatedButton.icon(
                key: const Key('watch_reward_ad'),
                onPressed:
                    (_rewardAvailable || widget.onWatchRewardAd != null) &&
                        !_watchingRewardAd
                    ? () => unawaited(_watchRewardAd())
                    : null,
                icon: _watchingRewardAd || _checkingRewardAvailability
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline_rounded),
                label: Text(
                  _watchingRewardAd
                      ? 'Aguardando confirmacao'
                      : _checkingRewardAvailability
                      ? 'Verificando'
                      : _rewardAvailable || widget.onWatchRewardAd != null
                      ? 'Assistir anuncio'
                      : 'Em configuracao',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _watchRewardAd() async {
    final callback = widget.onWatchRewardAd;
    if (callback != null) {
      callback();
      return;
    }
    final rewardedAccessManager = widget.rewardedAccessManager;
    if (rewardedAccessManager == null || _watchingRewardAd) return;
    setState(() {
      _watchingRewardAd = true;
      _message = 'O anuncio sera aberto no navegador.';
    });
    final result = await rewardedAccessManager.watchRewardAd();
    if (!mounted) return;
    if (result.granted) {
      _temporaryAccessGranted = true;
      if (widget.downloadManager == null) {
        _manager = PremiumDownloadService(hasPaidPlan: true);
      }
      widget.onAccessGranted?.call();
      unawaited(_refresh());
    }
    setState(() {
      _watchingRewardAd = false;
      _message = result.message;
    });
  }

  Future<void> _openPlans() async {
    final callback = widget.onOpenPlans;
    if (callback != null) {
      await callback();
      return;
    }
    final opened = await launchUrl(
      Uri.parse('https://tgiapp.pages.dev/#planos'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() {
        _message = 'Nao foi possivel abrir o plano no navegador.';
      });
    }
  }

  Widget _componentCard(PremiumComponentInfo info, {required bool paid}) {
    final installed = _installed[info.id] ?? false;
    final busy = _busy == info.id;
    return _featureCard(
      icon: _iconFor(info.id),
      title: info.title,
      description:
          '${info.description} Download: ${_formatMiB(info.downloadSizeBytes)}.',
      paid: paid,
      trailing: busy
          ? OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancelar'),
            )
          : installed
          ? OutlinedButton.icon(
              key: Key('remove_${info.id.name}'),
              onPressed: paid && _busy == null ? () => _remove(info) : null,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Desinstalar'),
            )
          : ElevatedButton.icon(
              key: Key('install_${info.id.name}'),
              onPressed: paid && _busy == null ? () => _install(info) : null,
              icon: Icon(paid ? Icons.download_rounded : Icons.lock_outline),
              label: Text(paid ? 'Instalar' : 'Bloqueado'),
            ),
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String description,
    required bool paid,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: paid
            ? TgiColors.surfacePanel
            : TgiColors.textMuted.withValues(alpha: 0.08),
        border: Border.all(color: TgiColors.borderStrong),
        borderRadius: BorderRadius.circular(TgiRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: paid ? TgiColors.accent : TgiColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: TgiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: TgiColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ] else
            Icon(
              paid ? Icons.check_circle_outline : Icons.lock_outline,
              color: paid ? TgiColors.success : TgiColors.textMuted,
            ),
        ],
      ),
    );
  }

  Future<void> _install(PremiumComponentInfo info) async {
    final token = PremiumDownloadCancellationToken();
    setState(() {
      _busy = info.id;
      _cancellationToken = token;
      _progress = 0;
      _message = 'Baixando ${info.title}...';
    });
    try {
      await _manager.install(
        info.id,
        cancellationToken: token,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress.clamp(0, 1));
        },
      );
      if (mounted) {
        setState(() {
          _installed[info.id] = true;
          _message = '${info.title} instalado.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _cancellationToken = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _remove(PremiumComponentInfo info) async {
    setState(() {
      _busy = info.id;
      _message = 'Desinstalando ${info.title}...';
    });
    try {
      await _manager.remove(info.id);
      if (mounted) {
        setState(() {
          _installed[info.id] = false;
          _message = '${info.title} desinstalado.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _cancel() {
    _cancellationToken?.cancel();
    setState(() => _message = 'Cancelando download...');
  }
}

IconData _iconFor(PremiumComponentId id) => switch (id) {
  PremiumComponentId.realEsrgan => Icons.auto_awesome_outlined,
  PremiumComponentId.biRefNet => Icons.content_cut_rounded,
  PremiumComponentId.whisperSmall => Icons.subtitles_outlined,
};

String _formatMiB(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MiB';
