import 'package:flutter/material.dart';

import 'theme_widgets.dart';

/// Layar pembuka (Splash Screen) yang responsif untuk 360x640 & 412x915
/// serta mendukung textScale 1.3 tanpa overflow.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onSelesai});
  final VoidCallback onSelesai;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            widget.onSelesai();
          }
        });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: JapaneseScienceBackground(
        fullIllustration: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 680;
            final logoSize = compact ? 112.0 : 144.0;
            final heroHeight = compact ? 150.0 : 196.0;

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenMargin,
                vertical: AppSpacing.s16,
              ),
              child: Column(
                children: [
                  SizedBox(height: compact ? AppSpacing.s8 : AppSpacing.s16),
                  FlaskAtomLogo(size: logoSize),
                  const SizedBox(height: AppSpacing.s12),
                  const Text(
                    'The 4 Sense Burden',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Color(0x55000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Learn • Measure • Explore',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    flex: 3,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: heroHeight,
                        maxWidth: 260,
                      ),
                      child: const SizedBox.expand(
                        child: CustomPaint(painter: _StudentsHeroPainter()),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  const WoodenBanner(
                    judul: '“Sains Lebih Dekat untuk Masa Depan”',
                    compact: true,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppRadius.cardBorder,
                          border: Border.all(
                            color: AppColors.borderLight,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Memuat Aplikasi...',
                                  style: AppTextStyles.labelBold(),
                                ),
                                Text(
                                  '${(_ctrl.value * 100).toInt()}%',
                                  style: AppTextStyles.caption(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _ctrl.value,
                                minHeight: 10,
                                backgroundColor: AppColors.primarySoft,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StudentsHeroPainter extends CustomPainter {
  const _StudentsHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _drawStudent(
      canvas,
      center: Offset(size.width * 0.30, size.height * 0.56),
      hairColor: const Color(0xFF3A2418),
      tieColor: AppColors.primary,
      isGirl: false,
    );
    _drawStudent(
      canvas,
      center: Offset(size.width * 0.70, size.height * 0.60),
      hairColor: const Color(0xFF4E2F1E),
      tieColor: const Color(0xFFE04556),
      isGirl: true,
    );
  }

  void _drawStudent(
    Canvas canvas, {
    required Offset center,
    required Color hairColor,
    required Color tieColor,
    required bool isGirl,
  }) {
    final skin = Paint()..color = const Color(0xFFFFDFC4);
    final hair = Paint()..color = hairColor;
    final shirt = Paint()..color = Colors.white;
    final bag = Paint()..color = AppColors.primaryDark;

    if (isGirl) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + const Offset(0, -18),
            width: 72,
            height: 68,
          ),
          const Radius.circular(26),
        ),
        hair,
      );
    }

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + const Offset(0, 38),
        width: 76,
        height: 66,
      ),
      const Radius.circular(20),
    );
    canvas.drawRRect(bodyRect, shirt);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(-22, 38),
          width: 10,
          height: 58,
        ),
        const Radius.circular(5),
      ),
      bag,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(22, 38),
          width: 10,
          height: 58,
        ),
        const Radius.circular(5),
      ),
      bag,
    );

    final tiePath = Path()
      ..moveTo(center.dx - 7, center.dy + 12)
      ..lineTo(center.dx + 7, center.dy + 12)
      ..lineTo(center.dx + 5, center.dy + 42)
      ..lineTo(center.dx, center.dy + 49)
      ..lineTo(center.dx - 5, center.dy + 42)
      ..close();
    canvas.drawPath(tiePath, Paint()..color = tieColor);

    canvas.drawRect(
      Rect.fromCenter(
        center: center + const Offset(0, 6),
        width: 16,
        height: 16,
      ),
      skin,
    );
    canvas.drawCircle(center + const Offset(0, -20), 28, skin);

    final bangPath = Path()
      ..addArc(
        Rect.fromCircle(center: center + const Offset(0, -22), radius: 30),
        3.14,
        3.14,
      )
      ..close();
    canvas.drawPath(bangPath, hair);

    final eyePaint = Paint()..color = const Color(0xFF2B1B12);
    canvas.drawCircle(center + const Offset(-10, -20), 3.4, eyePaint);
    canvas.drawCircle(center + const Offset(10, -20), 3.4, eyePaint);

    final blush = Paint()
      ..color = const Color(0xFFFF9E9E).withValues(alpha: 0.6);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(-15, -13),
        width: 9,
        height: 5,
      ),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(15, -13),
        width: 9,
        height: 5,
      ),
      blush,
    );

    canvas.drawArc(
      Rect.fromCenter(
        center: center + const Offset(0, -13),
        width: 14,
        height: 10,
      ),
      0.1,
      2.9,
      false,
      Paint()
        ..color = const Color(0xFF8C2D2D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    final handOffset = isGirl ? const Offset(40, 22) : const Offset(-40, 22);
    canvas.drawCircle(center + handOffset, 10, skin);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + handOffset + const Offset(0, -10),
          width: 7,
          height: 11,
        ),
        const Radius.circular(4),
      ),
      skin,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
