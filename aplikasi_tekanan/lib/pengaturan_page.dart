import 'package:flutter/material.dart';

import 'mqtt_service.dart';
import 'theme_widgets.dart';

/// Layar ke-8: "Pengaturan" (Koneksi & Sensor, Satuan, Tampilan, Penyimpanan, Tentang).
class PengaturanPage extends StatelessWidget {
  const PengaturanPage({super.key, required this.layanan, this.onKembali});

  final MqttService layanan;
  final VoidCallback? onKembali;

  Future<void> _dialogKoneksi(BuildContext context) async {
    final hostCtrl = TextEditingController(text: layanan.host);
    final portCtrl = TextEditingController(text: layanan.port.toString());
    final idCtrl = TextEditingController(text: layanan.idAlat);

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
        title: const Text(
          'Koneksi & Sensor MQTT',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID Alat ESP32',
                  helperText: 'Harus sama dengan ID_ALAT di kode ESP32',
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(labelText: 'Broker MQTT'),
              ),
              const SizedBox(height: AppSpacing.s12),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port MQTT'),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            height: AppSpacing.minTouchTarget,
            child: TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
          ),
          SizedBox(
            height: AppSpacing.minTouchTarget,
            child: FilledButton(
              onPressed: () => Navigator.pop(c, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              child: const Text('Simpan & Sambung'),
            ),
          ),
        ],
      ),
    );

    if (simpan == true) {
      final idBersih = idCtrl.text.trim().replaceAll(RegExp(r'[#+/\s]'), '');
      await layanan.simpanPengaturanKoneksi(
        hostCtrl.text.trim().isEmpty
            ? MqttService.brokerBawaan
            : hostCtrl.text.trim(),
        int.tryParse(portCtrl.text.trim()) ?? MqttService.portBawaan,
        idBersih.isEmpty ? MqttService.idAlatBawaan : idBersih,
      );
      await layanan.sambung();
    }
  }

  Future<void> _dialogSatuan(BuildContext context) async {
    String p = layanan.satuanTekanan;
    String t = layanan.satuanSuhu;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
          title: const Text(
            'Pilih Satuan Pengukuran',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Satuan Tekanan:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'kPa', label: Text('kPa')),
                  ButtonSegment(value: 'Pa', label: Text('Pa')),
                  ButtonSegment(value: 'bar', label: Text('bar')),
                ],
                selected: {p},
                onSelectionChanged: (v) => setModal(() => p = v.first),
              ),
              const SizedBox(height: AppSpacing.s16),
              const Text(
                'Satuan Suhu:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '°C', label: Text('°C (Celsius)')),
                  ButtonSegment(value: 'K', label: Text('K (Kelvin)')),
                ],
                selected: {t},
                onSelectionChanged: (v) => setModal(() => t = v.first),
              ),
            ],
          ),
          actions: [
            SizedBox(
              height: AppSpacing.minTouchTarget,
              child: TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Batal'),
              ),
            ),
            SizedBox(
              height: AppSpacing.minTouchTarget,
              child: FilledButton(
                onPressed: () {
                  layanan.aturSatuan(tekanan: p, suhu: t);
                  Navigator.pop(c);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.buttonBorder,
                  ),
                ),
                child: const Text('Simpan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _dialogTentang(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
        title: const Row(
          children: [
            FlaskAtomLogo(size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'The 4 Sense Burden',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'Media pembelajaran & praktikum IPA SMP berbasis sensor ESP32:\n'
          '• Tekanan Zat Padat (HX711 & 4× HC-SR04)\n'
          '• Tekanan Hidrostatis Zat Cair (HX710B)\n'
          '• Tekanan & Gas Ideal (HX710B & DHT22)\n\n'
          'Versi 1.0.0',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          SizedBox(
            height: AppSpacing.minTouchTarget,
            child: FilledButton(
              onPressed: () => Navigator.pop(c),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              child: const Text('Tutup'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final terhubung =
        layanan.status == StatusKoneksi.tersambung && layanan.alatOnline;

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
            judul: 'Pengaturan',
            subjudul: 'Atur koneksi alat, satuan, dan tampilan',
            onBack: onKembali,
            modeTerang: layanan.modeTerang,
          ),

          EspConnectionBanner(layanan: layanan),
          const SizedBox(height: AppSpacing.cardGap),

          // 1. Koneksi & Sensor
          _ItemPengaturan(
            ikon: Icons.wifi_rounded,
            role: MetricRole.mol,
            judul: 'Koneksi & Sensor ESP32',
            subjudul: terhubung
                ? 'Terhubung ke ${layanan.idAlat} (${layanan.host})'
                : 'ID Alat: ${layanan.idAlat} • Ketuk untuk ubah',
            modeTerang: layanan.modeTerang,
            onTap: () => _dialogKoneksi(context),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 2. Satuan
          _ItemPengaturan(
            ikon: Icons.straighten_rounded,
            role: MetricRole.suhu,
            judul: 'Satuan Pengukuran',
            subjudul:
                '${layanan.satuanTekanan}, ${layanan.satuanSuhu}, m³, mol',
            modeTerang: layanan.modeTerang,
            onTap: () => _dialogSatuan(context),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 3. Tampilan (Mode Terang)
          _ItemPengaturan(
            ikon: Icons.contrast_rounded,
            role: MetricRole.tekanan,
            judul: 'Tampilan Layar',
            subjudul: layanan.modeTerang ? 'Mode Terang' : 'Mode Malam',
            modeTerang: layanan.modeTerang,
            trailing: Switch(
              value: layanan.modeTerang,
              activeTrackColor: AppColors.primary,
              onChanged: layanan.aturModeTerang,
            ),
            onTap: () => layanan.aturModeTerang(!layanan.modeTerang),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 4. Penyimpanan (Simpan Otomatis)
          _ItemPengaturan(
            ikon: Icons.storage_rounded,
            role: MetricRole.volume,
            judul: 'Penyimpanan Riwayat',
            subjudul: layanan.simpanOtomatis
                ? 'Simpan Otomatis Aktif'
                : 'Simpan Manual',
            modeTerang: layanan.modeTerang,
            trailing: Switch(
              value: layanan.simpanOtomatis,
              activeTrackColor: AppColors.primary,
              onChanged: layanan.aturSimpanOtomatis,
            ),
            onTap: () => layanan.aturSimpanOtomatis(!layanan.simpanOtomatis),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 5. Tentang Aplikasi
          _ItemPengaturan(
            ikon: Icons.info_outline_rounded,
            role: MetricRole.tekanan,
            judul: 'Tentang Aplikasi',
            subjudul: 'Versi 1.0.0 • The 4 Sense Burden',
            modeTerang: layanan.modeTerang,
            onTap: () => _dialogTentang(context),
          ),
          const SizedBox(height: AppSpacing.s16),

          const Center(
            child: WoodenBanner(
              judul: '“Belajar Sains, Meraih Masa Depan”',
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemPengaturan extends StatelessWidget {
  const _ItemPengaturan({
    required this.ikon,
    required this.role,
    required this.judul,
    required this.subjudul,
    required this.modeTerang,
    this.trailing,
    this.onTap,
  });

  final IconData ikon;
  final MetricRole role;
  final String judul;
  final String subjudul;
  final bool modeTerang;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palet = AppColors.paletteFor(role);
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? AppColors.borderLight : AppColors.borderDark;
    final iconBg = modeTerang ? palet.cardBgLight : palet.cardBgDark;

    return Semantics(
      button: true,
      label: '$judul. $subjudul',
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
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(ikon, color: palet.accent, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          judul,
                          style: AppTextStyles.labelBold(
                            modeTerang: modeTerang,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subjudul,
                          style: AppTextStyles.caption(modeTerang: modeTerang),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        color: modeTerang
                            ? AppColors.textSecondaryLight
                            : AppColors.textSecondaryDark,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
