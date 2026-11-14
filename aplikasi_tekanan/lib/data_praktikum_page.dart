import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mqtt_service.dart';
import 'theme_widgets.dart';

/// Layar ke-7: "Data Praktikum" (Riwayat & Ekspor CSV / Laporan).
class DataPraktikumPage extends StatefulWidget {
  const DataPraktikumPage({super.key, required this.layanan, this.onKembali});

  final MqttService layanan;
  final VoidCallback? onKembali;

  @override
  State<DataPraktikumPage> createState() => _DataPraktikumPageState();
}

class _DataPraktikumPageState extends State<DataPraktikumPage> {
  int _tab = 0; // 0 = Riwayat, 1 = Ekspor

  String _formatWaktu(DateTime w) {
    const bulan = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final jam = w.hour.toString().padLeft(2, '0');
    final mnt = w.minute.toString().padLeft(2, '0');
    return '${w.day} ${bulan[w.month - 1]} ${w.year} • $jam:$mnt';
  }

  Widget _ikonSesi(int mode) {
    if (mode == 0) return const BeakerWaterIcon(size: 44);
    if (mode == 2) return const Cubes3DIcon(size: 44);
    return const RedBalloonIcon(size: 44);
  }

  Future<void> _eksporCsv() async {
    final csv = widget.layanan.buatCsvRiwayat();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Data CSV disalin! Tempelkan ke Excel atau Google Sheets.',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _eksporPdf() async {
    final laporan = widget.layanan.buatLaporanTeks();
    await Clipboard.setData(ClipboardData(text: laporan));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
        title: const Text(
          'Laporan Praktikum',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            laporan,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
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

  void _bukaDetailSesi(SesiPraktikum sesi) {
    final s = widget.layanan;
    final pPa = sesi.ringkasan['p_pa'];
    final bg = s.modeTerang ? AppColors.cardLight : AppColors.cardDark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _ikonSesi(sesi.mode),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Praktikum ${sesi.judul}',
                          style: AppTextStyles.sectionTitle(
                            modeTerang: s.modeTerang,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatWaktu(sesi.waktu),
                          style: AppTextStyles.caption(
                            modeTerang: s.modeTerang,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: AppSpacing.minTouchTarget,
                    height: AppSpacing.minTouchTarget,
                    child: IconButton(
                      tooltip: 'Hapus data ini',
                      onPressed: () {
                        s.hapusSesiPraktikum(sesi.id);
                        Navigator.pop(c);
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _BarisDetail(
                'Tekanan (P)',
                '${s.formatTekanan(pPa)} ${s.satuanTekanan}',
                modeTerang: s.modeTerang,
              ),
              if (sesi.mode == 2) ...[
                _BarisDetail(
                  'Gaya (F)',
                  '${(sesi.ringkasan['gaya_n'] ?? 0).toStringAsFixed(2)} N',
                  modeTerang: s.modeTerang,
                ),
                _BarisDetail(
                  'Luas Permukaan (A)',
                  '${(sesi.ringkasan['luas_cm2'] ?? 0).toStringAsFixed(2)} cm²',
                  modeTerang: s.modeTerang,
                ),
              ] else if (sesi.mode == 0) ...[
                _BarisDetail(
                  'Kedalaman (h)',
                  '${((sesi.ringkasan['tinggi_cm'] ?? 0) / 100.0).toStringAsFixed(2)} m',
                  modeTerang: s.modeTerang,
                ),
                _BarisDetail(
                  'Massa Jenis (ρ)',
                  '${(sesi.ringkasan['rho'] ?? 1000).toStringAsFixed(0)} kg/m³',
                  modeTerang: s.modeTerang,
                ),
              ] else ...[
                _BarisDetail(
                  'Suhu Gas (T)',
                  '${s.formatSuhu(sesi.ringkasan['suhu_k'])} ${s.satuanSuhu}',
                  modeTerang: s.modeTerang,
                ),
                _BarisDetail(
                  'Volume Bola (V)',
                  '${(sesi.ringkasan['volume_m3'] ?? 0).toStringAsFixed(6)} m³',
                  modeTerang: s.modeTerang,
                ),
                _BarisDetail(
                  'Jumlah Mol (n)',
                  '${(sesi.ringkasan['n_mol'] ?? 0).toStringAsFixed(6)} mol',
                  modeTerang: s.modeTerang,
                ),
              ],
              _BarisDetail(
                'Jumlah sampel terekam',
                '${sesi.sampel.length} titik data',
                modeTerang: s.modeTerang,
              ),
              const SizedBox(height: AppSpacing.s16),
              SizedBox(
                height: AppSpacing.actionButtonHeight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonBorder,
                    ),
                  ),
                  child: const Text(
                    'Tutup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.layanan;
    final daftar = s.riwayatSesi;

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
            judul: 'Data Praktikum',
            subjudul: '${daftar.length} riwayat sesi tersimpan',
            onBack: widget.onKembali,
            modeTerang: s.modeTerang,
          ),

          ModeTabSwitch(
            kiri: 'Riwayat',
            kanan: 'Ekspor Data',
            ikonKiri: Icons.history_rounded,
            ikonKanan: Icons.ios_share_rounded,
            indexAktif: _tab,
            modeTerang: s.modeTerang,
            onChanged: (v) => setState(() => _tab = v),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _tab == 0
                ? _bangunTabRiwayat(s, daftar)
                : _bangunTabEkspor(s, daftar),
          ),
        ],
      ),
    );
  }

  Widget _bangunTabRiwayat(MqttService s, List<SesiPraktikum> daftar) {
    if (daftar.isEmpty) {
      return ParchmentCard(
        key: const ValueKey('riwayat_kosong'),
        modeTerang: s.modeTerang,
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.history_edu_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Belum Ada Data Praktikum',
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionTitle(modeTerang: s.modeTerang),
            ),
            const SizedBox(height: 6),
            Text(
              'Mulai pengukuran di menu Praktikum, lalu tekan Selesai dan Simpan agar hasilnya muncul di sini.',
              textAlign: TextAlign.center,
              style: AppTextStyles.label(modeTerang: s.modeTerang),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('riwayat_isi'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in daftar) ...[
          _KartuItemRiwayat(
            sesi: item,
            waktuFormatted: _formatWaktu(item.waktu),
            ikon: _ikonSesi(item.mode),
            tekananFormatted:
                '${s.formatTekanan(item.ringkasan['p_pa'])} ${s.satuanTekanan}',
            modeTerang: s.modeTerang,
            onTap: () => _bukaDetailSesi(item),
          ),
          const SizedBox(height: AppSpacing.cardGap),
        ],
        _BarTombolEkspor(onCsv: _eksporCsv, onPdf: _eksporPdf),
      ],
    );
  }

  Widget _bangunTabEkspor(MqttService s, List<SesiPraktikum> daftar) {
    return Column(
      key: const ValueKey('tab_ekspor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParchmentCard(
          modeTerang: s.modeTerang,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.description_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      'Salin & Bagikan Laporan',
                      style: AppTextStyles.sectionTitle(
                        modeTerang: s.modeTerang,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                daftar.isEmpty
                    ? 'Belum ada sesi yang disimpan. Laporan di bawah masih kosong.'
                    : 'Tersedia ${daftar.length} sesi praktikum yang siap disalin ke tabel CSV atau laporan teks.',
                style: AppTextStyles.label(modeTerang: s.modeTerang),
              ),
              const SizedBox(height: AppSpacing.s16),
              _BarTombolEkspor(onCsv: _eksporCsv, onPdf: _eksporPdf),
            ],
          ),
        ),
      ],
    );
  }
}

class _KartuItemRiwayat extends StatelessWidget {
  const _KartuItemRiwayat({
    required this.sesi,
    required this.waktuFormatted,
    required this.ikon,
    required this.tekananFormatted,
    required this.modeTerang,
    required this.onTap,
  });

  final SesiPraktikum sesi;
  final String waktuFormatted;
  final Widget ikon;
  final String tekananFormatted;
  final bool modeTerang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? AppColors.borderLight : AppColors.borderDark;

    return Semantics(
      button: true,
      label:
          'Praktikum ${sesi.judul}, $waktuFormatted, tekanan $tekananFormatted',
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
                ikon,
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sesi.judul,
                        style: AppTextStyles.sectionTitle(
                          modeTerang: modeTerang,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        waktuFormatted,
                        style: AppTextStyles.caption(modeTerang: modeTerang),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tekananFormatted,
                    style: AppTextStyles.labelBold(
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
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
    );
  }
}

class _BarTombolEkspor extends StatelessWidget {
  const _BarTombolEkspor({required this.onCsv, required this.onPdf});

  final VoidCallback onCsv;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: AppSpacing.actionButtonHeight,
            child: FilledButton.icon(
              onPressed: onCsv,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              icon: const Icon(Icons.table_view_rounded, size: 20),
              label: const Text(
                'Export CSV',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.cardGap),
        Expanded(
          child: SizedBox(
            height: AppSpacing.actionButtonHeight,
            child: FilledButton.icon(
              onPressed: onPdf,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.volumePalette.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: const Text(
                'Laporan PDF',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarisDetail extends StatelessWidget {
  const _BarisDetail(this.label, this.nilai, {required this.modeTerang});

  final String label;
  final String nilai;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.label(modeTerang: modeTerang),
            ),
          ),
          const SizedBox(width: 8),
          Text(nilai, style: AppTextStyles.labelBold(modeTerang: modeTerang)),
        ],
      ),
    );
  }
}
