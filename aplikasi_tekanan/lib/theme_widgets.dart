import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'mqtt_service.dart';
import 'theme/app_theme.dart';

export 'theme/app_theme.dart';

/// Status tahapan tombol aksi praktikum (maksimal 2 tombol, tinggi 52dp).
enum PraktikumActionState {
  awal, // [Mulai]
  berjalan, // [Jeda] [Selesai]
  dijeda, // [Lanjut] [Selesai]
  selesai, // [Simpan] [Ulangi]
}

/// Latar aplikasi: konten berada di atas latar polos lembut, sedangkan aksen
/// Jepang (sakura, Gunung Fuji, dan ombak Seigaiha) hanya di header/footer
/// (atau penuh khusus di Splash Screen bila `fullIllustration = true`).
class JapaneseScienceBackground extends StatelessWidget {
  const JapaneseScienceBackground({
    super.key,
    required this.child,
    this.modeTerang = true,
    this.fullIllustration = false,
  });

  final Widget child;
  final bool modeTerang;
  final bool fullIllustration;

  @override
  Widget build(BuildContext context) {
    final bgColor = modeTerang ? AppColors.bgLight : AppColors.bgDark;
    return ColoredBox(
      color: bgColor,
      child: Stack(
        children: [
          if (fullIllustration)
            Positioned.fill(
              child: CustomPaint(
                painter: _JapaneseSplashPainter(modeTerang: modeTerang),
              ),
            )
          else ...[
            // Aksen Header Jepang lembut di bagian atas saja (tinggi 128dp)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 128,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _JapaneseHeaderAccentPainter(modeTerang: modeTerang),
                ),
              ),
            ),
            // Aksen Ombak Seigaiha tipis di bagian paling bawah (tinggi 28dp)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 28,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SeigaihaFooterPainter(modeTerang: modeTerang),
                ),
              ),
            ),
          ],
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class _JapaneseHeaderAccentPainter extends CustomPainter {
  const _JapaneseHeaderAccentPainter({required this.modeTerang});
  final bool modeTerang;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: modeTerang
              ? const [Color(0xFFDCEBFF), Color(0xFFEEF5FF), Color(0x00F6F8FC)]
              : const [Color(0xFF172554), Color(0xFF131F3A), Color(0x000F172A)],
        ).createShader(rect),
    );

    // Siluet Gunung Fuji lembut di kanan atas
    final fujiBaseY = size.height * 0.82;
    final fujiPath = Path()
      ..moveTo(size.width * 0.56, fujiBaseY)
      ..quadraticBezierTo(
        size.width * 0.70,
        fujiBaseY - 8,
        size.width * 0.75,
        fujiBaseY - 38,
      )
      ..lineTo(size.width * 0.83, fujiBaseY - 38)
      ..quadraticBezierTo(
        size.width * 0.88,
        fujiBaseY - 8,
        size.width * 1.02,
        fujiBaseY,
      )
      ..close();
    canvas.drawPath(
      fujiPath,
      Paint()
        ..color = modeTerang
            ? const Color(0xFF93C5FD).withValues(alpha: 0.28)
            : const Color(0xFF3B82F6).withValues(alpha: 0.14),
    );

    // Kelopak Sakura lembut di sudut kiri & kanan atas
    _drawSoftSakura(canvas, const Offset(24, 22), 18, modeTerang ? 0.45 : 0.20);
    _drawSoftSakura(
      canvas,
      Offset(size.width - 28, 24),
      16,
      modeTerang ? 0.45 : 0.20,
    );
  }

  void _drawSoftSakura(Canvas canvas, Offset center, double r, double opacity) {
    final p = Paint()
      ..color = const Color(0xFFF472B6).withValues(alpha: opacity);
    for (var i = 0; i < 5; i++) {
      final angle = (i * 72) * math.pi / 180;
      final offset =
          center +
          Offset(math.cos(angle) * r * 0.55, math.sin(angle) * r * 0.55);
      canvas.drawCircle(offset, r * 0.36, p);
    }
    canvas.drawCircle(
      center,
      r * 0.20,
      Paint()..color = const Color(0xFFFBBF24).withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _JapaneseHeaderAccentPainter oldDelegate) =>
      oldDelegate.modeTerang != modeTerang;
}

class _SeigaihaFooterPainter extends CustomPainter {
  const _SeigaihaFooterPainter({required this.modeTerang});
  final bool modeTerang;

  @override
  void paint(Canvas canvas, Size size) {
    const waveR = 22.0;
    final baseY = size.height;
    final linePaint = Paint()
      ..color = (modeTerang ? const Color(0xFF93C5FD) : const Color(0xFF1E3A8A))
          .withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (double x = 0; x < size.width + waveR; x += waveR * 2) {
      final center = Offset(x, baseY);
      for (final frac in [1.0, 0.68, 0.38]) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: waveR * frac),
          math.pi,
          math.pi,
          false,
          linePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeigaihaFooterPainter oldDelegate) =>
      oldDelegate.modeTerang != modeTerang;
}

class _JapaneseSplashPainter extends CustomPainter {
  const _JapaneseSplashPainter({required this.modeTerang});
  final bool modeTerang;

  @override
  void paint(Canvas canvas, Size size) {
    final skyRect = Offset.zero & size;
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1D4ED8),
            Color(0xFF3B82F6),
            Color(0xFFDBEAFE),
            Color(0xFFF6F8FC),
          ],
          stops: [0.0, 0.30, 0.65, 1.0],
        ).createShader(skyRect),
    );

    // Gunung Fuji di kejauhan
    final fujiBaseY = size.height * 0.36;
    final fujiPath = Path()
      ..moveTo(size.width * 0.10, fujiBaseY)
      ..quadraticBezierTo(
        size.width * 0.36,
        fujiBaseY - 18,
        size.width * 0.44,
        fujiBaseY - 72,
      )
      ..lineTo(size.width * 0.56, fujiBaseY - 72)
      ..quadraticBezierTo(
        size.width * 0.64,
        fujiBaseY - 18,
        size.width * 0.90,
        fujiBaseY,
      )
      ..close();
    canvas.drawPath(
      fujiPath,
      Paint()..color = const Color(0xFF2563EB).withValues(alpha: 0.45),
    );

    // Salju puncak Fuji
    final snowPath = Path()
      ..moveTo(size.width * 0.44, fujiBaseY - 72)
      ..lineTo(size.width * 0.56, fujiBaseY - 72)
      ..lineTo(size.width * 0.60, fujiBaseY - 46)
      ..lineTo(size.width * 0.50, fujiBaseY - 52)
      ..lineTo(size.width * 0.40, fujiBaseY - 46)
      ..close();
    canvas.drawPath(
      snowPath,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Sakura lembut di sudut atas
    final petal = Paint()
      ..color = const Color(0xFFF9A8D4).withValues(alpha: 0.75);
    canvas.drawCircle(const Offset(32, 42), 20, petal);
    canvas.drawCircle(const Offset(62, 26), 14, petal);
    canvas.drawCircle(Offset(size.width - 32, 42), 20, petal);
    canvas.drawCircle(Offset(size.width - 62, 26), 14, petal);
  }

  @override
  bool shouldRepaint(covariant _JapaneseSplashPainter oldDelegate) =>
      oldDelegate.modeTerang != modeTerang;
}

/// AppBar seragam untuk seluruh layar:
/// Tombol kembali di kiri (target sentuh >=48dp) + Judul (22-24 bold) + aksi di kanan.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.judul,
    this.subjudul,
    this.leadingIcon,
    this.onBack,
    this.trailing,
    this.modeTerang = true,
  });

  final String judul;
  final String? subjudul;
  final Widget? leadingIcon;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    final textPrimary = modeTerang
        ? AppColors.textPrimaryLight
        : AppColors.textPrimaryDark;
    final cardColor = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final borderColor = modeTerang
        ? AppColors.borderLight
        : AppColors.borderDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Row(
        children: [
          if (onBack != null) ...[
            Semantics(
              button: true,
              label: 'Kembali',
              child: Material(
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: borderColor),
                ),
                child: InkWell(
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: AppSpacing.minTouchTarget,
                    height: AppSpacing.minTouchTarget,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: textPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
          ],
          if (leadingIcon != null) ...[
            leadingIcon!,
            const SizedBox(width: AppSpacing.s12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judul,
                  style: AppTextStyles.screenTitle(modeTerang: modeTerang),
                ),
                if (subjudul != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subjudul!,
                    style: AppTextStyles.caption(modeTerang: modeTerang),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Banner status koneksi ESP32 lengkap:
/// - Menyambung (loading skeleton/progress)
/// - Terputus / Error (banner kuning/merah + tombol "Sambungkan" >=48dp)
/// - Terhubung (indikator hijau ramah)
class EspConnectionBanner extends StatelessWidget {
  const EspConnectionBanner({
    super.key,
    required this.layanan,
    this.onBukaPengaturan,
  });

  final MqttService layanan;
  final VoidCallback? onBukaPengaturan;

  @override
  Widget build(BuildContext context) {
    final status = layanan.status;
    final terhubung = status == StatusKoneksi.tersambung && layanan.alatOnline;
    final menyambung = status == StatusKoneksi.menyambung;
    final adaError =
        layanan.pesanError != null && status == StatusKoneksi.putus;

    if (terhubung) {
      return Semantics(
        label: 'Status alat: ESP32 ${layanan.idAlat} terhubung dan aktif',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8 + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: AppColors.successBorder, width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  'ESP32 Terhubung (${layanan.idAlat}) • Sensor Aktif',
                  style: AppTextStyles.labelBold(color: AppColors.success),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (menyambung) {
      return Semantics(
        label: 'Sedang menyambungkan ke alat ESP32',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: AppColors.tekananPalette.cardBorderLight,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  'Menyambungkan ke ESP32 (${layanan.idAlat})...',
                  style: AppTextStyles.labelBold(color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // State Terputus / Menunggu ESP32 / Error
    final bg = adaError ? AppColors.dangerBg : AppColors.warningBg;
    final border = adaError ? AppColors.dangerBorder : AppColors.warningBorder;
    final fg = adaError ? AppColors.danger : AppColors.warning;
    final pesan = adaError
        ? layanan.pesanError!
        : status == StatusKoneksi.tersambung
        ? 'MQTT aktif, menunggu data dari ESP32 (${layanan.idAlat}).'
        : 'Alat ESP32 (${layanan.idAlat}) belum terhubung.';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            adaError
                ? Icons.error_outline_rounded
                : Icons.wifi_tethering_error_rounded,
            color: fg,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(pesan, style: AppTextStyles.caption(color: fg)),
          ),
          const SizedBox(width: AppSpacing.s8),
          SizedBox(
            height: AppSpacing.minTouchTarget,
            child: FilledButton.icon(
              onPressed: layanan.sambung,
              style: FilledButton.styleFrom(
                backgroundColor: fg,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Sambungkan',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu nilai sensor seragam dengan kontras >= 4.5:1, animasi 250ms,
/// angka 28 bold + satuan lebih kecil di sampingnya, serta dukungan Semantics.
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.judul,
    required this.nilai,
    required this.satuan,
    required this.role,
    required this.ikon,
    this.sublabel,
    this.sedangMemuat = false,
    this.modeTerang = true,
    this.compact = false,
    this.onTap,
  });

  final String judul;
  final String nilai;
  final String satuan;
  final MetricRole role;
  final IconData ikon;
  final String? sublabel;
  final bool sedangMemuat;
  final bool modeTerang;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palet = AppColors.paletteFor(role);
    final bg = modeTerang ? palet.cardBgLight : palet.cardBgDark;
    final border = modeTerang ? palet.cardBorderLight : palet.cardBorderDark;
    final textColor = modeTerang ? palet.textLight : palet.textDark;
    final subColor = modeTerang ? palet.subtextLight : palet.textDark;

    return Semantics(
      button: onTap != null,
      label:
          '$judul: $nilai $satuan${sublabel != null ? ", $sublabel" : ""}${onTap != null ? ". Ketuk untuk lihat rumus dan penjelasan." : ""}',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
          side: BorderSide(color: border, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.all(
                compact ? AppSpacing.s12 : AppSpacing.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Baris Atas: Ikon + Label (14sp) + Ikon Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: palet.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(ikon, color: palet.accent, size: 18),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: Text(
                          judul,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelBold(color: subColor),
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: subColor.withValues(alpha: 0.75),
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? AppSpacing.s8 : AppSpacing.s12),

                  // Angka Sensor (28 bold) + Satuan di sampingnya (14 bold)
                  if (sedangMemuat)
                    const _SkeletonBar(width: 96, height: 30)
                  else
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: FittedBox(
                        key: ValueKey('$nilai-$satuan'),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              nilai,
                              style: AppTextStyles.sensorValue(
                                color: textColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              satuan,
                              style: AppTextStyles.sensorUnit(color: subColor),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (sublabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      sublabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(color: subColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatefulWidget {
  const _SkeletonBar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  State<_SkeletonBar> createState() => _SkeletonBarState();
}

class _SkeletonBarState extends State<_SkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.85).animate(_ctrl),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF94A3B8).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Kartu grafik standar (tinggi grafik 200dp, label >= 12sp, radius 20dp).
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.judul,
    required this.chart,
    this.trailingHeader,
    this.legenda,
    this.catatanBawah,
    this.modeTerang = true,
    this.tinggiGrafik = 200.0,
  });

  final String judul;
  final Widget chart;
  final Widget? trailingHeader;
  final Widget? legenda;
  final String? catatanBawah;
  final bool modeTerang;
  final double tinggiGrafik;

  @override
  Widget build(BuildContext context) {
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? AppColors.borderLight : AppColors.borderDark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.show_chart_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  judul,
                  style: AppTextStyles.sectionTitle(modeTerang: modeTerang),
                ),
              ),
              ?trailingHeader,
            ],
          ),
          if (legenda != null) ...[
            const SizedBox(height: AppSpacing.s8),
            legenda!,
          ],
          const SizedBox(height: AppSpacing.s12),
          SizedBox(height: tinggiGrafik, child: chart),
          if (catatanBawah != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              catatanBawah!,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(modeTerang: modeTerang),
            ),
          ],
        ],
      ),
    );
  }
}

/// Legenda titik warna + teks (>= 12sp) untuk grafik.
class ChartLegendItem extends StatelessWidget {
  const ChartLegendItem({
    super.key,
    required this.warna,
    required this.label,
    this.modeTerang = true,
  });

  final Color warna;
  final String label;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: warna, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.caption(modeTerang: modeTerang)),
      ],
    );
  }
}

/// Komponen tombol aksi tunggal berbasis state (tinggi 52dp, radius 16dp, maks 2 tombol):
/// - awal     : [Mulai]
/// - berjalan : [Jeda] [Selesai]
/// - dijeda   : [Lanjut] [Selesai]
/// - selesai  : [Simpan] [Ulangi]
class PraktikumActionBar extends StatelessWidget {
  const PraktikumActionBar({
    super.key,
    required this.state,
    required this.onMulai,
    required this.onJeda,
    required this.onLanjut,
    required this.onSelesai,
    required this.onSimpan,
    required this.onUlangi,
  });

  final PraktikumActionState state;
  final VoidCallback onMulai;
  final VoidCallback onJeda;
  final VoidCallback onLanjut;
  final VoidCallback onSelesai;
  final VoidCallback onSimpan;
  final VoidCallback onUlangi;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _buildForState(context),
    );
  }

  Widget _buildForState(BuildContext context) {
    switch (state) {
      case PraktikumActionState.awal:
        return SizedBox(
          key: const ValueKey('state_awal'),
          height: AppSpacing.actionButtonHeight,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onMulai,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.buttonBorder,
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 24),
            label: const Text(
              'Mulai Praktikum',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        );

      case PraktikumActionState.berjalan:
        return Row(
          key: const ValueKey('state_berjalan'),
          children: [
            Expanded(
              child: SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: OutlinedButton.icon(
                  onPressed: onJeda,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(
                      color: AppColors.warning,
                      width: 1.8,
                    ),
                    backgroundColor: AppColors.warningBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  icon: const Icon(Icons.pause_rounded, size: 22),
                  label: const Text(
                    'Jeda',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: FilledButton.icon(
                  onPressed: onSelesai,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 22),
                  label: const Text(
                    'Selesai',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        );

      case PraktikumActionState.dijeda:
        return Row(
          key: const ValueKey('state_dijeda'),
          children: [
            Expanded(
              child: SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: FilledButton.icon(
                  onPressed: onLanjut,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'Lanjut',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: FilledButton.icon(
                  onPressed: onSelesai,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 22),
                  label: const Text(
                    'Selesai',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        );

      case PraktikumActionState.selesai:
        return Row(
          key: const ValueKey('state_selesai'),
          children: [
            Expanded(
              child: SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: FilledButton.icon(
                  onPressed: onSimpan,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 22),
                  label: const Text(
                    'Simpan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: OutlinedButton.icon(
                  onPressed: onUlangi,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 22),
                  label: const Text(
                    'Ulangi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

/// Toggle 2 tab seragam ("Pengukuran" | "Teori" atau "Riwayat" | "Ekspor")
/// dengan target sentuh >= 48dp dan animasi 220ms.
class ModeTabSwitch extends StatelessWidget {
  const ModeTabSwitch({
    super.key,
    required this.kiri,
    required this.kanan,
    required this.indexAktif,
    required this.onChanged,
    this.ikonKiri,
    this.ikonKanan,
    this.modeTerang = true,
  });

  final String kiri;
  final String kanan;
  final int indexAktif;
  final ValueChanged<int> onChanged;
  final IconData? ikonKiri;
  final IconData? ikonKanan;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    final bg = modeTerang ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.buttonBorder,
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabPill(
              label: kiri,
              ikon: ikonKiri,
              aktif: indexAktif == 0,
              modeTerang: modeTerang,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabPill(
              label: kanan,
              ikon: ikonKanan,
              aktif: indexAktif == 1,
              modeTerang: modeTerang,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.aktif,
    required this.modeTerang,
    required this.onTap,
    this.ikon,
  });

  final String label;
  final IconData? ikon;
  final bool aktif;
  final bool modeTerang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactiveColor = modeTerang
        ? AppColors.textSecondaryLight
        : AppColors.textSecondaryDark;
    return Semantics(
      button: true,
      selected: aktif,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: aktif ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (ikon != null) ...[
                Icon(
                  ikon,
                  size: 18,
                  color: aktif ? Colors.white : inactiveColor,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: aktif ? Colors.white : inactiveColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu kontainer bersih (radius 20dp).
class ParchmentCard extends StatelessWidget {
  const ParchmentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.modeTerang = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: modeTerang ? AppColors.cardLight : AppColors.cardDark,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(
          color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: modeTerang ? 0.04 : 0.20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Papan motivasi/aksen kayu yang kini lebih bersih & rapi.
class WoodenBanner extends StatelessWidget {
  const WoodenBanner({
    super.key,
    required this.judul,
    this.leading,
    this.onBack,
    this.compact = false,
  });

  final String judul;
  final Widget? leading;
  final VoidCallback? onBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: const Color(0xFFFDBA74), width: 1.8),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (onBack != null) ...[
            SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF7C2D12),
                ),
              ),
            ),
          ],
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Flexible(
            child: Text(
              judul,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 15 : 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF7C2D12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper membuat FlTitlesData yang selalu memakai teks >= 12sp.
FlTitlesData buildStandardChartTitles({
  required bool modeTerang,
  double? leftInterval,
  double? bottomInterval,
  String Function(double)? bottomLabelBuilder,
}) {
  final textStyle = AppTextStyles.caption(modeTerang: modeTerang);
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: leftInterval,
        reservedSize: 38,
        getTitlesWidget: (v, _) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(v.toInt().toString(), style: textStyle),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: bottomInterval,
        reservedSize: 26,
        getTitlesWidget: (v, _) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            bottomLabelBuilder != null
                ? bottomLabelBuilder(v)
                : '${v.toInt()}s',
            style: textStyle,
          ),
        ),
      ),
    ),
  );
}

/// Logo Labu Sains + Cincin Atom ("The 4 Sense Burden").
class FlaskAtomLogo extends StatelessWidget {
  const FlaskAtomLogo({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          'assets/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Ikon 3 Kubus 3D untuk Zat Padat.
class Cubes3DIcon extends StatelessWidget {
  const Cubes3DIcon({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _Cubes3DPainter()),
    );
  }
}

class _Cubes3DPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.22;
    _drawIsoCube(canvas, Offset(size.width * 0.33, size.height * 0.64), r);
    _drawIsoCube(canvas, Offset(size.width * 0.67, size.height * 0.64), r);
    _drawIsoCube(canvas, Offset(size.width * 0.50, size.height * 0.34), r);
  }

  void _drawIsoCube(Canvas canvas, Offset center, double r) {
    final dx = r * 0.866;
    final dy = r * 0.5;

    final top = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + dx, center.dy - dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(center.dx - dx, center.dy - dy)
      ..close();
    final left = Path()
      ..moveTo(center.dx - dx, center.dy - dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - dx, center.dy + dy)
      ..close();
    final right = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + dx, center.dy - dy)
      ..lineTo(center.dx + dx, center.dy + dy)
      ..lineTo(center.dx, center.dy + r)
      ..close();

    canvas.drawPath(top, Paint()..color = const Color(0xFFDBEAFE));
    canvas.drawPath(left, Paint()..color = const Color(0xFF60A5FA));
    canvas.drawPath(right, Paint()..color = const Color(0xFF2563EB));

    final border = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(top, border);
    canvas.drawPath(left, border);
    canvas.drawPath(right, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Ikon Gelas Ukur (Beaker) berisi air biru untuk Zat Cair.
class BeakerWaterIcon extends StatelessWidget {
  const BeakerWaterIcon({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BeakerPainter()),
    );
  }
}

class _BeakerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.20, h * 0.14, w * 0.60, h * 0.74),
      bottomLeft: Radius.circular(w * 0.10),
      bottomRight: Radius.circular(w * 0.10),
    );
    final waterRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.22, h * 0.38, w * 0.56, h * 0.48),
      bottomLeft: Radius.circular(w * 0.08),
      bottomRight: Radius.circular(w * 0.08),
    );
    canvas.drawRRect(
      waterRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
        ).createShader(waterRect.outerRect),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.38),
        width: w * 0.56,
        height: h * 0.08,
      ),
      Paint()..color = const Color(0xFF7DD3FC),
    );
    final markPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.6;
    for (var i = 1; i <= 3; i++) {
      final y = h * (0.38 + i * 0.11);
      canvas.drawLine(Offset(w * 0.56, y), Offset(w * 0.70, y), markPaint);
    }
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFF1E3A8A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Ikon Balon Merah untuk Zat Gas.
class RedBalloonIcon extends StatelessWidget {
  const RedBalloonIcon({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BalloonPainter()),
    );
  }
}

class _BalloonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final oval = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.42),
      width: w * 0.62,
      height: h * 0.68,
    );
    canvas.drawOval(
      oval,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [Color(0xFFFCA5A5), Color(0xFFDC2626), Color(0xFF991B1B)],
        ).createShader(oval),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.38, h * 0.28),
        width: w * 0.14,
        height: h * 0.20,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    final knot = Path()
      ..moveTo(w * 0.45, h * 0.75)
      ..lineTo(w * 0.55, h * 0.75)
      ..lineTo(w * 0.50, h * 0.81)
      ..close();
    canvas.drawPath(knot, Paint()..color = const Color(0xFFB91C1C));

    final stringPath = Path()
      ..moveTo(w * 0.50, h * 0.81)
      ..quadraticBezierTo(w * 0.38, h * 0.89, w * 0.54, h * 0.96);
    canvas.drawPath(
      stringPath,
      Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
