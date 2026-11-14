import 'package:flutter/material.dart';

import 'theme_widgets.dart';

/// Layar ke-3: "Pilih Jenis Praktikum" (Zat Padat, Zat Cair, Zat Gas).
class PraktikumMenuPage extends StatelessWidget {
  const PraktikumMenuPage({
    super.key,
    required this.onPilihMode,
    this.onKembali,
    this.modeTerang = true,
  });

  final ValueChanged<int> onPilihMode; // 2 = Padat, 0 = Cair, 1 = Gas
  final VoidCallback? onKembali;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMargin,
        AppSpacing.s8,
        AppSpacing.screenMargin,
        AppSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTopBar(
            judul: 'Pilih Jenis Praktikum',
            subjudul: 'Pilih materi yang ingin kamu pelajari hari ini',
            onBack: onKembali,
            modeTerang: modeTerang,
          ),

          // 1. Zat Padat (mode 2 di ESP32)
          _KartuPilihPraktikum(
            judul: 'Zat Padat',
            rumus: 'P = F / A',
            deskripsi: 'Ukur hubungan gaya tekan dan luas bidang sentuh.',
            ikon: const Cubes3DIcon(size: 64),
            role: MetricRole.tekanan,
            modeTerang: modeTerang,
            onTap: () => onPilihMode(2),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 2. Zat Cair (mode 0 di ESP32)
          _KartuPilihPraktikum(
            judul: 'Zat Cair',
            rumus: 'P = ρ · g · h',
            deskripsi: 'Ukur tekanan hidrostatis air pada berbagai kedalaman.',
            ikon: const BeakerWaterIcon(size: 64),
            role: MetricRole.mol,
            modeTerang: modeTerang,
            onTap: () => onPilihMode(0),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 3. Zat Gas (mode 1 di ESP32)
          _KartuPilihPraktikum(
            judul: 'Zat Gas',
            rumus: 'P · V = n · R · T',
            deskripsi: 'Ukur tekanan, suhu, volume bola, dan jumlah mol gas.',
            ikon: const RedBalloonIcon(size: 64),
            role: MetricRole.suhu,
            modeTerang: modeTerang,
            onTap: () => onPilihMode(1),
          ),
        ],
      ),
    );
  }
}

class _KartuPilihPraktikum extends StatelessWidget {
  const _KartuPilihPraktikum({
    required this.judul,
    required this.rumus,
    required this.deskripsi,
    required this.ikon,
    required this.role,
    required this.modeTerang,
    required this.onTap,
  });

  final String judul;
  final String rumus;
  final String deskripsi;
  final Widget ikon;
  final MetricRole role;
  final bool modeTerang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palet = AppColors.paletteFor(role);
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? palet.cardBorderLight : palet.cardBorderDark;
    final iconBg = modeTerang ? palet.cardBgLight : palet.cardBgDark;

    return Semantics(
      button: true,
      label: 'Praktikum $judul, rumus $rumus. $deskripsi',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
          side: BorderSide(color: border, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.cardBorder,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: ikon,
                ),
                const SizedBox(width: AppSpacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            judul,
                            style: AppTextStyles.sectionTitle(
                              modeTerang: modeTerang,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              rumus,
                              style: AppTextStyles.caption(
                                color: modeTerang
                                    ? palet.textLight
                                    : palet.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        deskripsi,
                        style: AppTextStyles.label(modeTerang: modeTerang),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: palet.accent,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
