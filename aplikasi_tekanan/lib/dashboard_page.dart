import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'mqtt_service.dart';
import 'theme_widgets.dart';

class _SpecKartuDashboard {
  const _SpecKartuDashboard({
    required this.judul,
    required this.nilai,
    required this.satuan,
    required this.role,
    required this.ikon,
    required this.rumus,
    required this.penjelasan,
    required this.kunciData,
    this.pengaliStat = 1.0,
    this.offsetStat = 0.0,
    this.desimalStat = 2,
  });

  final String judul;
  final String nilai;
  final String satuan;
  final MetricRole role;
  final IconData ikon;
  final String rumus;
  final String penjelasan;
  final String kunciData;
  final double pengaliStat;
  final double offsetStat;
  final int desimalStat;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.layanan,
    required this.onBukaPraktikum,
    required this.onMulaiPraktikum,
    required this.onBukaPengaturan,
  });

  final MqttService layanan;
  final ValueChanged<int> onBukaPraktikum;
  final VoidCallback onMulaiPraktikum;
  final VoidCallback onBukaPengaturan;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _rentangMenit = 1; // 1, 5, atau 10 menit
  int _modePilihan = 1; // 2=Padat, 0=Cair, 1=Gas
  int? _modeEspTerakhir;

  @override
  void initState() {
    super.initState();
    final modeAwal = widget.layanan.terakhir?.mode;
    if (modeAwal != null && modeAwal >= 0 && modeAwal <= 2) {
      _modePilihan = modeAwal;
      _modeEspTerakhir = modeAwal;
    }
  }

  void _sinkronModeEsp() {
    final modeEsp = widget.layanan.terakhir?.mode;
    if (modeEsp != null &&
        modeEsp >= 0 &&
        modeEsp <= 2 &&
        modeEsp != _modeEspTerakhir) {
      _modeEspTerakhir = modeEsp;
      _modePilihan = modeEsp;
    }
  }

  void _pilihModeDashboard(int modeBaru) {
    setState(() {
      _modePilihan = modeBaru;
      _modeEspTerakhir = modeBaru;
    });
    widget.layanan.kirimPerintahMode(modeBaru);
    if (!mounted) return;
    final nama = modeBaru == 2
        ? 'Zat Padat'
        : modeBaru == 0
        ? 'Zat Cair'
        : 'Zat Gas';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Mode diubah ke $nama',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryDark,
        ),
      );
  }

  List<_SpecKartuDashboard> _bangunDaftarKartu(MqttService s) {
    final faktorTekanan = s.satuanTekanan == 'Pa'
        ? 1.0
        : s.satuanTekanan == 'bar'
        ? 0.00001
        : 0.001;
    final desimalTekanan = s.satuanTekanan == 'Pa'
        ? 1
        : s.satuanTekanan == 'bar'
        ? 4
        : 2;

    if (_modePilihan == 2) {
      // ZAT PADAT (mode = 2)
      final pPa = s.tekananPadatPa;
      final gayaN = s.gayaPadatN;
      final massaG = s.massaPadatG;
      final luasCm2 = s.luasPadatCm2;
      return [
        _SpecKartuDashboard(
          judul: 'Tekanan Padat',
          nilai: pPa != null ? s.formatTekanan(pPa) : '0.00',
          satuan: s.satuanTekanan,
          role: MetricRole.tekanan,
          ikon: Icons.speed_rounded,
          rumus: 'P = F / A',
          penjelasan: 'Tekanan zat padat semakin besar jika gaya tekan (F) besar atau luas bidang sentuh (A) kecil.',
          kunciData: 'p_pa',
          pengaliStat: faktorTekanan,
          desimalStat: desimalTekanan,
        ),
        _SpecKartuDashboard(
          judul: 'Gaya Tekan (F)',
          nilai: gayaN != null ? gayaN.toStringAsFixed(2) : '0.00',
          satuan: 'N',
          role: MetricRole.suhu,
          ikon: Icons.fitness_center_rounded,
          rumus: 'F = m × g',
          penjelasan: 'Gaya tekan berasal dari berat beban pada sensor Load Cell dikali gravitasi bumi (9,81 m/s²).',
          kunciData: 'gaya_n',
          desimalStat: 2,
        ),
        _SpecKartuDashboard(
          judul: 'Massa Beban',
          nilai: massaG != null ? massaG.toStringAsFixed(1) : '0.0',
          satuan: 'g',
          role: MetricRole.volume,
          ikon: Icons.scale_rounded,
          rumus: 'm = F / g',
          penjelasan: 'Massa benda padat yang ditimbang langsung oleh sensor Load Cell HX711.',
          kunciData: 'massa_g',
          desimalStat: 1,
        ),
        _SpecKartuDashboard(
          judul: 'Luas Bidang (A)',
          nilai: luasCm2 != null ? luasCm2.toStringAsFixed(2) : '0.00',
          satuan: 'cm²',
          role: MetricRole.mol,
          ikon: Icons.grid_on_rounded,
          rumus: 'A = p × l',
          penjelasan: 'Luas permukaan bawah benda yang diukur otomatis oleh 4 sensor ultrasonik HC-SR04.',
          kunciData: 'luas_cm2',
          desimalStat: 2,
        ),
      ];
    } else if (_modePilihan == 0) {
      // ZAT CAIR (mode = 0)
      final pPa = s.tekananCairPa;
      final hCm = s.tinggiCairCm;
      final rho = s.rhoCair ?? 1000.0;
      return [
        _SpecKartuDashboard(
          judul: 'Tekanan Cair',
          nilai: pPa != null ? s.formatTekanan(pPa) : '0.00',
          satuan: s.satuanTekanan,
          role: MetricRole.tekanan,
          ikon: Icons.speed_rounded,
          rumus: 'P = ρ × g × h',
          penjelasan: 'Tekanan hidrostatis zat cair meningkat seiring bertambahnya kedalaman sensor.',
          kunciData: 'p_pa',
          pengaliStat: faktorTekanan,
          desimalStat: desimalTekanan,
        ),
        _SpecKartuDashboard(
          judul: 'Kedalaman (h)',
          nilai: hCm != null ? hCm.toStringAsFixed(1) : '0.0',
          satuan: 'cm',
          role: MetricRole.suhu,
          ikon: Icons.height_rounded,
          rumus: 'h = P / (ρ × g)',
          penjelasan: 'Jarak titik ukur dari permukaan air. Semakin dalam, tekanan air semakin kuat.',
          kunciData: 'tinggi_cm',
          desimalStat: 1,
        ),
        _SpecKartuDashboard(
          judul: 'Massa Jenis (ρ)',
          nilai: rho.toStringAsFixed(0),
          satuan: 'kg/m³',
          role: MetricRole.volume,
          ikon: Icons.water_drop_rounded,
          rumus: 'ρ = m / V',
          penjelasan: 'Kerapatan zat cair (air murni ≈ 1000 kg/m³). Cairan yang lebih rapat memberi tekanan lebih besar.',
          kunciData: 'rho',
          desimalStat: 0,
        ),
        const _SpecKartuDashboard(
          judul: 'Gravitasi (g)',
          nilai: '9.81',
          satuan: 'm/s²',
          role: MetricRole.mol,
          ikon: Icons.public_rounded,
          rumus: 'g ≈ 9,81 m/s²',
          penjelasan: 'Percepatan gravitasi bumi yang menarik zat cair ke bawah sehingga menimbulkan tekanan hidrostatis.',
          kunciData: '',
          desimalStat: 2,
        ),
      ];
    } else {
      // ZAT GAS (mode = 1)
      final pPa = s.tekananGasPa ?? s.terakhir?.angka('p_pa');
      final teksTekanan = pPa != null ? s.formatTekanan(pPa) : '0.00';
      final teksSuhu = s.suhuGasK != null ? s.formatSuhu(s.suhuGasK) : '--';
      final teksVolume = s.volumeGasM3 != null
          ? s.volumeGasM3!.toStringAsFixed(5)
          : '0.00000';
      final teksMol = s.molGas != null
          ? s.molGas!.toStringAsFixed(5)
          : '0.00000';

      return [
        _SpecKartuDashboard(
          judul: 'Tekanan Gas',
          nilai: teksTekanan,
          satuan: s.satuanTekanan,
          role: MetricRole.tekanan,
          ikon: Icons.speed_rounded,
          rumus: 'P · V = n · R · T',
          penjelasan: 'Tekanan udara di dalam wadah tertutup yang diukur oleh sensor tekanan HX710B.',
          kunciData: 'p_pa',
          pengaliStat: faktorTekanan,
          desimalStat: desimalTekanan,
        ),
        _SpecKartuDashboard(
          judul: 'Suhu Udara',
          nilai: teksSuhu,
          satuan: s.satuanSuhu,
          role: MetricRole.suhu,
          ikon: Icons.thermostat_rounded,
          rumus: 'T(K) = T(°C) + 273,15',
          penjelasan: 'Suhu gas dari sensor DHT22. Saat suhu naik di ruang tertutup, tekanan gas ikut naik.',
          kunciData: 'suhu_k',
          pengaliStat: 1.0,
          offsetStat: s.satuanSuhu == 'K' ? 0.0 : -273.15,
          desimalStat: 1,
        ),
        _SpecKartuDashboard(
          judul: 'Volume Bola',
          nilai: teksVolume,
          satuan: 'm³',
          role: MetricRole.volume,
          ikon: Icons.panorama_photosphere_rounded,
          rumus: 'V = 4/3 × π × r³',
          penjelasan: 'Volume ruang bola tempat partikel gas bergerak dan menumbuk dinding wadah.',
          kunciData: 'volume_m3',
          desimalStat: 6,
        ),
        _SpecKartuDashboard(
          judul: 'Jumlah Mol',
          nilai: teksMol,
          satuan: 'mol',
          role: MetricRole.mol,
          ikon: Icons.bubble_chart_rounded,
          rumus: 'n = (P × V) / (R × T)',
          penjelasan: 'Jumlah partikel gas yang dihitung dari persamaan gas ideal dengan R = 8,314 J/(mol·K).',
          kunciData: 'n_mol',
          desimalStat: 6,
        ),
      ];
    }
  }

  void _tampilkanInfoKartu(
    BuildContext context,
    _SpecKartuDashboard spec,
    MqttService s,
  ) {
    final palet = AppColors.paletteFor(spec.role);
    final stat = spec.kunciData.isNotEmpty
        ? s.statistikBesaran(
            _modePilihan,
            spec.kunciData,
            pengali: spec.pengaliStat,
            offset: spec.offsetStat,
          )
        : null;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
          backgroundColor: s.modeTerang
              ? AppColors.cardLight
              : AppColors.cardDark,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  decoration: BoxDecoration(
                    color: s.modeTerang ? palet.cardBgLight : palet.cardBgDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: s.modeTerang
                          ? palet.cardBorderLight
                          : palet.cardBorderDark,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(spec.ikon, color: palet.accent, size: 32),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              spec.judul,
                              style: AppTextStyles.labelBold(
                                color: s.modeTerang
                                    ? palet.subtextLight
                                    : palet.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(
                                    spec.nilai,
                                    style: AppTextStyles.sensorValue(
                                      color: s.modeTerang
                                          ? palet.textLight
                                          : palet.textDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  spec.satuan,
                                  style: AppTextStyles.sensorUnit(
                                    color: s.modeTerang
                                        ? palet.subtextLight
                                        : palet.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12,
                    vertical: AppSpacing.s8 + 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Rumus: ${spec.rumus}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                Text(
                  spec.penjelasan,
                  style: AppTextStyles.label(modeTerang: s.modeTerang),
                ),
                if (stat != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s12),
                    decoration: BoxDecoration(
                      color: s.modeTerang
                          ? AppColors.bgLight
                          : AppColors.bgDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: s.modeTerang
                            ? AppColors.borderLight
                            : AppColors.borderDark,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          label: 'Minimum',
                          nilai:
                              '${stat['min']!.toStringAsFixed(spec.desimalStat)} ${spec.satuan}',
                          modeTerang: s.modeTerang,
                        ),
                        _StatItem(
                          label: 'Rata-rata',
                          nilai:
                              '${stat['avg']!.toStringAsFixed(spec.desimalStat)} ${spec.satuan}',
                          modeTerang: s.modeTerang,
                        ),
                        _StatItem(
                          label: 'Maksimum',
                          nilai:
                              '${stat['max']!.toStringAsFixed(spec.desimalStat)} ${spec.satuan}',
                          modeTerang: s.modeTerang,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.s16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: AppSpacing.minTouchTarget,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.buttonBorder,
                            ),
                          ),
                          child: const Text(
                            'Tutup',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: SizedBox(
                        height: AppSpacing.minTouchTarget,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.layanan.kirimPerintahMode(_modePilihan);
                            widget.onBukaPraktikum(_modePilihan);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.buttonBorder,
                            ),
                          ),
                          icon: const Icon(Icons.science_rounded, size: 18),
                          label: const Text(
                            'Praktikum',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _sinkronModeEsp();
    final s = widget.layanan;
    final sedangMemuat =
        s.status == StatusKoneksi.menyambung && s.terakhir == null;
    final kartuList = _bangunDaftarKartu(s);

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
          // 1. AppBar Seragam
          AppTopBar(
            judul: 'The 4 Sense Burden',
            subjudul: 'Pantau sensor & mulai praktikum sains',
            leadingIcon: const FlaskAtomLogo(size: 44),
            modeTerang: s.modeTerang,
            trailing: Semantics(
              button: true,
              label: 'Buka Pengaturan',
              child: Material(
                color: s.modeTerang ? AppColors.cardLight : AppColors.cardDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: s.modeTerang
                        ? AppColors.borderLight
                        : AppColors.borderDark,
                  ),
                ),
                child: InkWell(
                  onTap: widget.onBukaPengaturan,
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: AppSpacing.minTouchTarget,
                    height: AppSpacing.minTouchTarget,
                    child: Icon(
                      Icons.tune_rounded,
                      color: s.modeTerang
                          ? AppColors.textPrimaryLight
                          : AppColors.textPrimaryDark,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. Banner Status Koneksi ESP32 (Loading / Terputus / Error / Aktif)
          EspConnectionBanner(
            layanan: s,
            onBukaPengaturan: widget.onBukaPengaturan,
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 3. Pemilih Mode Cepat (Zat Padat | Zat Cair | Zat Gas)
          _ModeSelectorBar(
            modePilihan: _modePilihan,
            modeTerang: s.modeTerang,
            onPilih: _pilihModeDashboard,
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 4. Grid 2x2 Kartu Sensor (Tekanan=Biru, Suhu=Merah-Oranye, Volume=Ungu, Mol=Hijau)
          Row(
            children: [
              Expanded(
                child: SensorCard(
                  judul: kartuList[0].judul,
                  nilai: kartuList[0].nilai,
                  satuan: kartuList[0].satuan,
                  role: kartuList[0].role,
                  ikon: kartuList[0].ikon,
                  sedangMemuat: sedangMemuat,
                  modeTerang: s.modeTerang,
                  onTap: () => _tampilkanInfoKartu(context, kartuList[0], s),
                ),
              ),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(
                child: SensorCard(
                  judul: kartuList[1].judul,
                  nilai: kartuList[1].nilai,
                  satuan: kartuList[1].satuan,
                  role: kartuList[1].role,
                  ikon: kartuList[1].ikon,
                  sedangMemuat: sedangMemuat,
                  modeTerang: s.modeTerang,
                  onTap: () => _tampilkanInfoKartu(context, kartuList[1], s),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.cardGap),
          Row(
            children: [
              Expanded(
                child: SensorCard(
                  judul: kartuList[2].judul,
                  nilai: kartuList[2].nilai,
                  satuan: kartuList[2].satuan,
                  role: kartuList[2].role,
                  ikon: kartuList[2].ikon,
                  sedangMemuat: sedangMemuat,
                  modeTerang: s.modeTerang,
                  onTap: () => _tampilkanInfoKartu(context, kartuList[2], s),
                ),
              ),
              const SizedBox(width: AppSpacing.cardGap),
              Expanded(
                child: SensorCard(
                  judul: kartuList[3].judul,
                  nilai: kartuList[3].nilai,
                  satuan: kartuList[3].satuan,
                  role: kartuList[3].role,
                  ikon: kartuList[3].ikon,
                  sedangMemuat: sedangMemuat,
                  modeTerang: s.modeTerang,
                  onTap: () => _tampilkanInfoKartu(context, kartuList[3], s),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 5. Kartu Grafik Real-Time (tinggi 200dp, label >= 12sp)
          ChartCard(
            judul: 'Grafik Real-Time',
            modeTerang: s.modeTerang,
            tinggiGrafik: 200,
            trailingHeader: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in [1, 5, 10])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Semantics(
                      button: true,
                      selected: _rentangMenit == m,
                      label: 'Rentang grafik $m menit',
                      child: InkWell(
                        onTap: () => setState(() => _rentangMenit = m),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 36,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _rentangMenit == m
                                ? AppColors.primary
                                : (s.modeTerang
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFF334155)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${m}m',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _rentangMenit == m
                                  ? Colors.white
                                  : (s.modeTerang
                                        ? AppColors.textPrimaryLight
                                        : AppColors.textPrimaryDark),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            legenda: _BangunLegendaMode(
              modePilihan: _modePilihan,
              modeTerang: s.modeTerang,
            ),
            catatanBawah: s.riwayat.length < 2
                ? 'Menunggu data sensor ESP32. Menampilkan garis contoh.'
                : 'Ketuk kartu sensor di atas untuk melihat rumus dan nilai rata-rata.',
            chart: _DashboardMultiChart(
              riwayat: s.riwayat,
              rentangMenit: _rentangMenit,
              modePilihan: _modePilihan,
              modeTerang: s.modeTerang,
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),

          // 6. Tombol Aksi Bawah (tinggi 52dp, radius 16dp)
          SizedBox(
            height: AppSpacing.actionButtonHeight,
            child: FilledButton.icon(
              onPressed: widget.onMulaiPraktikum,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonBorder,
                ),
              ),
              icon: const Icon(Icons.science_rounded, size: 22),
              label: const Text(
                'Pilih & Mulai Praktikum',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelectorBar extends StatelessWidget {
  const _ModeSelectorBar({
    required this.modePilihan,
    required this.modeTerang,
    required this.onPilih,
  });

  final int modePilihan;
  final bool modeTerang;
  final ValueChanged<int> onPilih;

  @override
  Widget build(BuildContext context) {
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? AppColors.borderLight : AppColors.borderDark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.buttonBorder,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        children: [
          _ItemModeTab(
            label: 'Zat Padat',
            ikon: Icons.view_in_ar_rounded,
            aktif: modePilihan == 2,
            modeTerang: modeTerang,
            onTap: () => onPilih(2),
          ),
          const SizedBox(width: 4),
          _ItemModeTab(
            label: 'Zat Cair',
            ikon: Icons.water_drop_rounded,
            aktif: modePilihan == 0,
            modeTerang: modeTerang,
            onTap: () => onPilih(0),
          ),
          const SizedBox(width: 4),
          _ItemModeTab(
            label: 'Zat Gas',
            ikon: Icons.bubble_chart_rounded,
            aktif: modePilihan == 1,
            modeTerang: modeTerang,
            onTap: () => onPilih(1),
          ),
        ],
      ),
    );
  }
}

class _ItemModeTab extends StatelessWidget {
  const _ItemModeTab({
    required this.label,
    required this.ikon,
    required this.aktif,
    required this.modeTerang,
    required this.onTap,
  });

  final String label;
  final IconData ikon;
  final bool aktif;
  final bool modeTerang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = aktif
        ? Colors.white
        : (modeTerang
              ? AppColors.textSecondaryLight
              : AppColors.textSecondaryDark);

    return Expanded(
      child: Semantics(
        button: true,
        selected: aktif,
        label: 'Mode $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget - 4,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: aktif ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ikon, size: 18, color: textColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: aktif ? FontWeight.w800 : FontWeight.w600,
                      color: textColor,
                    ),
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

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.nilai,
    required this.modeTerang,
  });

  final String label;
  final String nilai;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTextStyles.caption(modeTerang: modeTerang)),
        const SizedBox(height: 2),
        Text(nilai, style: AppTextStyles.labelBold(modeTerang: modeTerang)),
      ],
    );
  }
}

class _BangunLegendaMode extends StatelessWidget {
  const _BangunLegendaMode({
    required this.modePilihan,
    required this.modeTerang,
  });

  final int modePilihan;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    if (modePilihan == 2) {
      return Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          ChartLegendItem(
            warna: AppColors.tekananPalette.accent,
            label: 'Tekanan',
            modeTerang: modeTerang,
          ),
          ChartLegendItem(
            warna: AppColors.suhuPalette.accent,
            label: 'Gaya (F)',
            modeTerang: modeTerang,
          ),
          ChartLegendItem(
            warna: AppColors.molPalette.accent,
            label: 'Luas (A)',
            modeTerang: modeTerang,
          ),
        ],
      );
    } else if (modePilihan == 0) {
      return Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          ChartLegendItem(
            warna: AppColors.tekananPalette.accent,
            label: 'Tekanan',
            modeTerang: modeTerang,
          ),
          ChartLegendItem(
            warna: AppColors.molPalette.accent,
            label: 'Kedalaman (h)',
            modeTerang: modeTerang,
          ),
        ],
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        ChartLegendItem(
          warna: AppColors.tekananPalette.accent,
          label: 'Tekanan',
          modeTerang: modeTerang,
        ),
        ChartLegendItem(
          warna: AppColors.suhuPalette.accent,
          label: 'Suhu',
          modeTerang: modeTerang,
        ),
        ChartLegendItem(
          warna: AppColors.volumePalette.accent,
          label: 'Volume',
          modeTerang: modeTerang,
        ),
        ChartLegendItem(
          warna: AppColors.molPalette.accent,
          label: 'Mol',
          modeTerang: modeTerang,
        ),
      ],
    );
  }
}

class _DashboardMultiChart extends StatelessWidget {
  const _DashboardMultiChart({
    required this.riwayat,
    required this.rentangMenit,
    required this.modePilihan,
    required this.modeTerang,
  });

  final List<Pembacaan> riwayat;
  final int rentangMenit;
  final int modePilihan;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    final batasWaktu = DateTime.now().subtract(Duration(minutes: rentangMenit));
    final data = riwayat.where((e) => e.waktu.isAfter(batasWaktu)).toList();

    final sTekanan = <FlSpot>[];
    final sSuhu = <FlSpot>[];
    final sVol = <FlSpot>[];
    final sMol = <FlSpot>[];

    if (data.length >= 2) {
      for (var i = 0; i < data.length; i++) {
        final x = i.toDouble();
        final pKpa = (data[i].angka('p_pa') ?? 0) / 1000.0;
        sTekanan.add(FlSpot(x, pKpa.clamp(0, 100)));

        if (modePilihan == 2) {
          final gaya = data[i].angka('gaya_n') ?? 0;
          final luas = data[i].angka('luas_cm2') ?? 0;
          sSuhu.add(FlSpot(x, gaya.clamp(0, 100)));
          sMol.add(FlSpot(x, luas.clamp(0, 100)));
        } else if (modePilihan == 0) {
          final tinggi = data[i].angka('tinggi_cm') ?? 0;
          sMol.add(FlSpot(x, tinggi.clamp(0, 100)));
        } else {
          final suhuC = (data[i].angka('suhu_k') ?? 298.15) - 273.15;
          final volScaled = (data[i].angka('volume_m3') ?? 0) * 100000.0;
          final molScaled = (data[i].angka('n_mol') ?? 0) * 1000.0;
          sSuhu.add(FlSpot(x, suhuC.clamp(0, 100)));
          sVol.add(FlSpot(x, volScaled.clamp(0, 100)));
          sMol.add(FlSpot(x, molScaled.clamp(0, 100)));
        }
      }
    } else {
      for (var i = 0; i <= 4; i++) {
        final x = i.toDouble();
        sTekanan.add(FlSpot(x, 32 + i * 8.0));
        sSuhu.add(FlSpot(x, 26 + i * 1.5));
        sVol.add(FlSpot(x, 20 + i * 2.0));
        sMol.add(FlSpot(x, 12 + i * 1.0));
      }
    }

    final bars = <LineChartBarData>[
      _seri(sTekanan, AppColors.tekananPalette.accent),
      if (modePilihan != 0) _seri(sSuhu, AppColors.suhuPalette.accent),
      if (modePilihan == 1) _seri(sVol, AppColors.volumePalette.accent),
      _seri(sMol, AppColors.molPalette.accent),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
            strokeWidth: 1,
          ),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(
              color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
            ),
            bottom: BorderSide(
              color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
            ),
          ),
        ),
        titlesData: buildStandardChartTitles(
          modeTerang: modeTerang,
          leftInterval: 25,
          bottomInterval: (sTekanan.length / 4).clamp(1, 50).toDouble(),
          bottomLabelBuilder: (v) {
            final idx = v.round();
            if (data.length >= 2 && idx >= 0 && idx < data.length) {
              final t = data[idx].waktu;
              return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
            }
            const labels = ['00s', '15s', '30s', '45s', '60s'];
            return labels[idx.clamp(0, labels.length - 1)];
          },
        ),
        lineBarsData: bars,
      ),
    );
  }

  LineChartBarData _seri(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.6,
      dotData: const FlDotData(show: true),
    );
  }
}
