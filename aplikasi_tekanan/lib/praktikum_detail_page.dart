import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'mqtt_service.dart';
import 'theme_widgets.dart';

/// Layar Praktikum Zat Padat (mode 2), Zat Cair (mode 0), dan Zat Gas (mode 1).
/// Mengikuti struktur seragam:
/// AppBar -> Tab Pengukuran|Teori -> Ilustrasi (<=160dp) -> Kartu Sensor Sama Lebar
/// -> Grafik (200dp, label >=12) -> Tombol Aksi Berbasis State (52dp, maks 2 tombol).
class PraktikumDetailPage extends StatefulWidget {
  const PraktikumDetailPage({
    super.key,
    required this.mode,
    required this.layanan,
    required this.onKembali,
    required this.onSelesaiSimpan,
  });

  final int mode; // 2 = Zat Padat, 0 = Zat Cair, 1 = Zat Gas
  final MqttService layanan;
  final VoidCallback onKembali;
  final VoidCallback onSelesaiSimpan;

  @override
  State<PraktikumDetailPage> createState() => _PraktikumDetailPageState();
}

class _PraktikumDetailPageState extends State<PraktikumDetailPage> {
  int _tab = 0; // 0 = Pengukuran, 1 = Teori
  PraktikumActionState _actionState = PraktikumActionState.awal;
  final List<Pembacaan> _sampelSesi = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ambilSampelSaatIni();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_actionState == PraktikumActionState.berjalan && mounted) {
        setState(_ambilSampelSaatIni);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ambilSampelSaatIni() {
    final s = widget.layanan;
    Pembacaan? sumber;
    if (widget.mode == 2) {
      sumber = s.terakhirPadat ?? (s.terakhir?.mode == 2 ? s.terakhir : null);
    } else if (widget.mode == 0) {
      sumber = s.terakhirCair ?? (s.terakhir?.mode == 0 ? s.terakhir : null);
    } else {
      sumber = s.terakhirGas ?? (s.terakhir?.mode == 1 ? s.terakhir : null);
    }
    if (sumber != null) {
      _sampelSesi.add(
        Pembacaan(DateTime.now(), Map<String, dynamic>.from(sumber.data)),
      );
      if (_sampelSesi.length > 60) _sampelSesi.removeAt(0);
    }
  }

  String get _judulHalaman {
    if (widget.mode == 2) return 'Praktikum Zat Padat';
    if (widget.mode == 0) return 'Praktikum Zat Cair';
    return 'Praktikum Zat Gas';
  }

  String get _judulSingkat {
    if (widget.mode == 2) return 'Zat Padat';
    if (widget.mode == 0) return 'Zat Cair';
    return 'Zat Gas';
  }

  Widget get _ikonHeader {
    if (widget.mode == 2) return const Cubes3DIcon(size: 40);
    if (widget.mode == 0) return const BeakerWaterIcon(size: 40);
    return const RedBalloonIcon(size: 40);
  }

  String get _statusBadgeTeks {
    switch (_actionState) {
      case PraktikumActionState.awal:
        return 'Siap dimulai • Tekan Mulai Praktikum di bawah';
      case PraktikumActionState.berjalan:
        return 'Merekam data sensor (${_sampelSesi.length} sampel)';
      case PraktikumActionState.dijeda:
        return 'Perekaman dijeda (${_sampelSesi.length} sampel)';
      case PraktikumActionState.selesai:
        return 'Pengukuran selesai • Tekan Simpan untuk menyimpan hasil';
    }
  }

  Future<void> _simpanSesi() async {
    final s = widget.layanan;
    final ringkasan = <String, double>{};

    if (widget.mode == 2) {
      ringkasan['p_pa'] = s.tekananPadatPa ?? 0.0;
      ringkasan['gaya_n'] = s.gayaPadatN ?? 0.0;
      ringkasan['luas_cm2'] = s.luasPadatCm2 ?? 0.0;
    } else if (widget.mode == 0) {
      ringkasan['p_pa'] = s.tekananCairPa ?? 0.0;
      ringkasan['tinggi_cm'] = s.tinggiCairCm ?? 0.0;
      ringkasan['rho'] = s.rhoCair ?? 1000.0;
    } else {
      ringkasan['p_pa'] = s.tekananGasPa ?? 0.0;
      ringkasan['suhu_k'] = s.suhuGasK ?? 298.15;
      ringkasan['volume_m3'] = s.volumeGasM3 ?? 0.0;
      ringkasan['n_mol'] = s.molGas ?? 0.0;
    }

    final sesi = SesiPraktikum(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      mode: widget.mode,
      judul: _judulSingkat,
      waktu: DateTime.now(),
      ringkasan: ringkasan,
      sampel: List<Pembacaan>.from(_sampelSesi),
    );

    await s.tambahSesiPraktikum(sesi);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Data praktikum $_judulSingkat disimpan ke Riwayat!',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.success,
      ),
    );
    widget.onSelesaiSimpan();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.layanan;
    final bg = s.modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = s.modeTerang ? AppColors.borderLight : AppColors.borderDark;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
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
                  judul: _judulHalaman,
                  subjudul: _statusBadgeTeks,
                  leadingIcon: _ikonHeader,
                  onBack: widget.onKembali,
                  modeTerang: s.modeTerang,
                ),

                // 2. Banner Koneksi ESP32 bila belum tersambung
                if (!(s.status == StatusKoneksi.tersambung &&
                    s.alatOnline)) ...[
                  EspConnectionBanner(layanan: s),
                  const SizedBox(height: AppSpacing.cardGap),
                ],

                // 3. Toggle Tab Pengukuran | Teori
                ModeTabSwitch(
                  kiri: 'Pengukuran',
                  kanan: 'Teori',
                  ikonKiri: Icons.sensors_rounded,
                  ikonKanan: Icons.menu_book_rounded,
                  indexAktif: _tab,
                  modeTerang: s.modeTerang,
                  onChanged: (v) => setState(() => _tab = v),
                ),
                const SizedBox(height: AppSpacing.cardGap),

                // 4. Isi Tab (Animasi 240ms)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: _tab == 1
                      ? _BagianTeori(
                          key: const ValueKey('tab_teori'),
                          mode: widget.mode,
                          modeTerang: s.modeTerang,
                        )
                      : _BagianPengukuranSeragam(
                          key: const ValueKey('tab_pengukuran'),
                          mode: widget.mode,
                          layanan: s,
                          sampel: _sampelSesi,
                        ),
                ),
              ],
            ),
          ),
        ),

        // 5. Action Bar Bawah (Hanya tampil di tab Pengukuran, tinggi 52dp, maks 2 tombol)
        if (_tab == 0)
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenMargin,
              AppSpacing.s12,
              AppSpacing.screenMargin,
              AppSpacing.s12,
            ),
            decoration: BoxDecoration(
              color: bg,
              border: Border(top: BorderSide(color: border)),
            ),
            child: PraktikumActionBar(
              state: _actionState,
              onMulai: () {
                _ambilSampelSaatIni();
                setState(() => _actionState = PraktikumActionState.berjalan);
              },
              onJeda: () =>
                  setState(() => _actionState = PraktikumActionState.dijeda),
              onLanjut: () =>
                  setState(() => _actionState = PraktikumActionState.berjalan),
              onSelesai: () =>
                  setState(() => _actionState = PraktikumActionState.selesai),
              onSimpan: _simpanSesi,
              onUlangi: () {
                setState(() {
                  _sampelSesi.clear();
                  _ambilSampelSaatIni();
                  _actionState = PraktikumActionState.berjalan;
                });
              },
            ),
          ),
      ],
    );
  }
}

/// Struktur Pengukuran Seragam untuk Padat, Cair, dan Gas:
/// 1) Ilustrasi (maks 160dp)
/// 2) 2-3 Kartu Nilai Sama Lebar
/// 3) Grafik (tinggi 200dp, label >= 12)
class _BagianPengukuranSeragam extends StatelessWidget {
  const _BagianPengukuranSeragam({
    super.key,
    required this.mode,
    required this.layanan,
    required this.sampel,
  });

  final int mode;
  final MqttService layanan;
  final List<Pembacaan> sampel;

  @override
  Widget build(BuildContext context) {
    final sedangMemuat =
        layanan.status == StatusKoneksi.menyambung && layanan.terakhir == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Kartu Ilustrasi Visual (Tinggi 148dp <= 160dp)
        _KartuIlustrasiPraktikum(mode: mode, modeTerang: layanan.modeTerang),
        const SizedBox(height: AppSpacing.cardGap),

        // 2. Kartu Nilai Sensor Sama Lebar
        if (mode == 2)
          _bangunKartuPadat(sedangMemuat)
        else if (mode == 0)
          _bangunKartuCair(sedangMemuat)
        else
          _bangunKartuGas(sedangMemuat),
        const SizedBox(height: AppSpacing.cardGap),

        // 3. Grafik Standar (Tinggi 200dp, Label >= 12sp)
        if (mode == 1)
          _GrafikDualGas(sampel: sampel, modeTerang: layanan.modeTerang)
        else
          _GrafikTunggalTekanan(
            judul: mode == 2
                ? 'Grafik Tekanan Zat Padat'
                : 'Grafik Tekanan Hidrostatis',
            sampel: sampel,
            modeTerang: layanan.modeTerang,
          ),
      ],
    );
  }

  Widget _bangunKartuPadat(bool sedangMemuat) {
    final pPa = layanan.tekananPadatPa;
    final gaya = layanan.gayaPadatN;
    final luas = layanan.luasPadatCm2;

    return Column(
      children: [
        SensorCard(
          judul: 'Tekanan Zat Padat (P = F / A)',
          nilai: pPa != null ? layanan.formatTekanan(pPa) : '0.00',
          satuan: layanan.satuanTekanan,
          role: MetricRole.tekanan,
          ikon: Icons.speed_rounded,
          sedangMemuat: sedangMemuat,
          modeTerang: layanan.modeTerang,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Row(
          children: [
            Expanded(
              child: SensorCard(
                judul: 'Gaya (F)',
                nilai: gaya != null ? gaya.toStringAsFixed(2) : '0.00',
                satuan: 'N',
                role: MetricRole.suhu,
                ikon: Icons.fitness_center_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SensorCard(
                judul: 'Luas (A)',
                nilai: luas != null ? luas.toStringAsFixed(2) : '0.00',
                satuan: 'cm²',
                role: MetricRole.mol,
                ikon: Icons.grid_on_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bangunKartuCair(bool sedangMemuat) {
    final pPa = layanan.tekananCairPa;
    final hCm = layanan.tinggiCairCm;
    final rho = layanan.rhoCair ?? 1000.0;

    return Column(
      children: [
        SensorCard(
          judul: 'Tekanan Hidrostatis (P = ρ · g · h)',
          nilai: pPa != null ? layanan.formatTekanan(pPa) : '0.00',
          satuan: layanan.satuanTekanan,
          role: MetricRole.tekanan,
          ikon: Icons.speed_rounded,
          sedangMemuat: sedangMemuat,
          modeTerang: layanan.modeTerang,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Row(
          children: [
            Expanded(
              child: SensorCard(
                judul: 'Kedalaman (h)',
                nilai: hCm != null ? (hCm / 100.0).toStringAsFixed(2) : '0.00',
                satuan: 'm',
                sublabel: hCm != null
                    ? '${hCm.toStringAsFixed(1)} cm'
                    : '0.0 cm',
                role: MetricRole.suhu,
                ikon: Icons.height_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SensorCard(
                judul: 'Massa Jenis (ρ)',
                nilai: rho.toStringAsFixed(0),
                satuan: 'kg/m³',
                sublabel: 'g = 9,81 m/s²',
                role: MetricRole.volume,
                ikon: Icons.water_drop_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bangunKartuGas(bool sedangMemuat) {
    final pPa = layanan.tekananGasPa;
    final suhuK = layanan.suhuGasK;
    final vol = layanan.volumeGasM3;
    final mol = layanan.molGas;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SensorCard(
                judul: 'Tekanan Gas',
                nilai: pPa != null ? layanan.formatTekanan(pPa) : '0.00',
                satuan: layanan.satuanTekanan,
                role: MetricRole.tekanan,
                ikon: Icons.speed_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SensorCard(
                judul: 'Suhu Gas',
                nilai: suhuK != null ? layanan.formatSuhu(suhuK) : '--',
                satuan: layanan.satuanSuhu,
                role: MetricRole.suhu,
                ikon: Icons.thermostat_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Row(
          children: [
            Expanded(
              child: SensorCard(
                judul: 'Volume Bola',
                nilai: vol != null ? vol.toStringAsFixed(5) : '0.00000',
                satuan: 'm³',
                role: MetricRole.volume,
                ikon: Icons.panorama_photosphere_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: SensorCard(
                judul: 'Jumlah Mol',
                nilai: mol != null ? mol.toStringAsFixed(5) : '0.00000',
                satuan: 'mol',
                role: MetricRole.mol,
                ikon: Icons.bubble_chart_rounded,
                sedangMemuat: sedangMemuat,
                modeTerang: layanan.modeTerang,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KartuIlustrasiPraktikum extends StatelessWidget {
  const _KartuIlustrasiPraktikum({
    required this.mode,
    required this.modeTerang,
  });

  final int mode;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? AppColors.borderLight : AppColors.borderDark;

    final String keterangan;
    final CustomPainter painter;
    if (mode == 2) {
      keterangan = 'Beban menekan meja uji Load Cell & 4 sensor ultrasonik';
      painter = const _BlockForcePainter();
    } else if (mode == 0) {
      keterangan = 'Tekanan air diukur pada kedalaman h dari permukaan';
      painter = const _BeakerDepthPainter();
    } else {
      keterangan = 'Tekanan & suhu gas di dalam bola diukur secara langsung';
      painter = const _BalloonManometerPainter();
    }

    return Container(
      height: 148, // <= 160dp sesuai aturan desain
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: CustomPaint(painter: painter),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            keterangan,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption(modeTerang: modeTerang),
          ),
        ],
      ),
    );
  }
}

class _GrafikTunggalTekanan extends StatelessWidget {
  const _GrafikTunggalTekanan({
    required this.judul,
    required this.sampel,
    required this.modeTerang,
  });

  final String judul;
  final List<Pembacaan> sampel;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < sampel.length; i++) {
      final v = (sampel[i].angka('p_pa') ?? 0) * 0.001; // kPa
      spots.add(FlSpot((i * 2).toDouble(), v));
    }
    final kosong = spots.length < 2;
    if (kosong) {
      spots
        ..clear()
        ..addAll(const [
          FlSpot(0, 0.2),
          FlSpot(10, 0.5),
          FlSpot(20, 0.75),
          FlSpot(30, 0.9),
        ]);
    }

    return ChartCard(
      judul: judul,
      modeTerang: modeTerang,
      tinggiGrafik: 200,
      legenda: ChartLegendItem(
        warna: AppColors.tekananPalette.accent,
        label: 'Tekanan (kPa)',
        modeTerang: modeTerang,
      ),
      catatanBawah: kosong
          ? 'Tekan "Mulai Praktikum" untuk merekam grafik dari sensor.'
          : 'Menampilkan ${sampel.length} titik pengukuran terakhir.',
      chart: LineChart(
        LineChartData(
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(
                color: modeTerang
                    ? AppColors.borderLight
                    : AppColors.borderDark,
              ),
              bottom: BorderSide(
                color: modeTerang
                    ? AppColors.borderLight
                    : AppColors.borderDark,
              ),
            ),
          ),
          titlesData: buildStandardChartTitles(modeTerang: modeTerang),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.tekananPalette.accent,
              barWidth: 2.8,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrafikDualGas extends StatelessWidget {
  const _GrafikDualGas({required this.sampel, required this.modeTerang});

  final List<Pembacaan> sampel;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    final sTekanan = <FlSpot>[];
    final sVolume = <FlSpot>[];

    for (var i = 0; i < sampel.length; i++) {
      final x = (i * 2).toDouble();
      final pKpa = (sampel[i].angka('p_pa') ?? 0) / 1000.0;
      final volScaled = (sampel[i].angka('volume_m3') ?? 0) * 100000.0;
      sTekanan.add(FlSpot(x, pKpa));
      sVolume.add(FlSpot(x, volScaled));
    }

    final kosong = sTekanan.length < 2;
    if (kosong) {
      sTekanan
        ..clear()
        ..addAll(const [
          FlSpot(0, 30),
          FlSpot(10, 50),
          FlSpot(20, 62),
          FlSpot(30, 70),
        ]);
      sVolume
        ..clear()
        ..addAll(const [
          FlSpot(0, 22),
          FlSpot(10, 35),
          FlSpot(20, 44),
          FlSpot(30, 52),
        ]);
    }

    return ChartCard(
      judul: 'Grafik Tekanan & Volume',
      modeTerang: modeTerang,
      tinggiGrafik: 200,
      legenda: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          ChartLegendItem(
            warna: AppColors.tekananPalette.accent,
            label: 'Tekanan (kPa)',
            modeTerang: modeTerang,
          ),
          ChartLegendItem(
            warna: AppColors.volumePalette.accent,
            label: 'Volume (×10⁻⁵ m³)',
            modeTerang: modeTerang,
          ),
        ],
      ),
      catatanBawah: kosong
          ? 'Tekan "Mulai Praktikum" untuk merekam grafik dari sensor.'
          : 'Menampilkan ${sampel.length} titik pengukuran terakhir.',
      chart: LineChart(
        LineChartData(
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(
                color: modeTerang
                    ? AppColors.borderLight
                    : AppColors.borderDark,
              ),
              bottom: BorderSide(
                color: modeTerang
                    ? AppColors.borderLight
                    : AppColors.borderDark,
              ),
            ),
          ),
          titlesData: buildStandardChartTitles(modeTerang: modeTerang),
          lineBarsData: [
            LineChartBarData(
              spots: sTekanan,
              isCurved: true,
              color: AppColors.tekananPalette.accent,
              barWidth: 2.8,
            ),
            LineChartBarData(
              spots: sVolume,
              isCurved: true,
              color: AppColors.volumePalette.accent,
              barWidth: 2.8,
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Materi Teori IPA SMP: Penjelasan Singkat + Rumus Besar + 1 Contoh =====
class _BagianTeori extends StatelessWidget {
  const _BagianTeori({super.key, required this.mode, required this.modeTerang});

  final int mode;
  final bool modeTerang;

  @override
  Widget build(BuildContext context) {
    if (mode == 2) {
      return _KartuMateriTeori(
        modeTerang: modeTerang,
        judul: 'Tekanan pada Zat Padat',
        penjelasanSingkat:
            'Tekanan adalah besarnya gaya tekan yang bekerja pada setiap satuan luas permukaan. '
            'Semakin kecil luas permukaan sentuh benda, semakin besar tekanan yang dihasilkan.',
        rumus: 'P = F / A',
        keteranganRumus: const [
          'P = Tekanan (Pa atau N/m²)',
          'F = Gaya tekan / berat benda (N)',
          'A = Luas bidang sentuh (m² atau cm²)',
        ],
        judulContoh: 'Contoh Penerapan & Hitungan',
        isiContoh:
            'Sebuah balok memiliki berat F = 20 N dan luas alas A = 0,04 m².\n'
            'Maka tekanannya adalah:\n'
            'P = 20 N / 0,04 m² = 500 Pa (0,50 kPa).\n'
            'Itulah sebabnya pisau yang tajam (luas tipis) lebih mudah memotong daripada pisau tumpul!',
      );
    }
    if (mode == 0) {
      return _KartuMateriTeori(
        modeTerang: modeTerang,
        judul: 'Tekanan Hidrostatis (Zat Cair)',
        penjelasanSingkat:
            'Zat cair yang diam memberikan tekanan ke segala arah karena tarikan gravitasi bumi. '
            'Semakin dalam posisi pengukuran dari permukaan air, semakin besar tekanannya.',
        rumus: 'P = ρ · g · h',
        keteranganRumus: const [
          'P = Tekanan hidrostatis (Pa atau kPa)',
          'ρ = Massa jenis cairan (air = 1000 kg/m³)',
          'g = Percepatan gravitasi (9,81 m/s²)',
          'h = Kedalaman dari permukaan (m)',
        ],
        judulContoh: 'Contoh Penerapan & Hitungan',
        isiContoh:
            'Sensor dimasukkan ke dalam air (ρ = 1000 kg/m³) pada kedalaman h = 0,30 m.\n'
            'Maka tekanannya adalah:\n'
            'P = 1000 × 9,81 × 0,30 ≈ 2.943 Pa (2,94 kPa).\n'
            'Karena itu, dinding bendungan bagian bawah selalu dibuat lebih tebal!',
      );
    }
    return _KartuMateriTeori(
      modeTerang: modeTerang,
      judul: 'Tekanan & Persamaan Gas Ideal',
      penjelasanSingkat:
          'Partikel gas di dalam ruang tertutup bergerak bebas dan menumbuk dinding wadah sehingga menghasilkan tekanan. '
          'Tekanan gas dipengaruhi oleh suhu, volume wadah, dan jumlah partikel gas (mol).',
      rumus: 'P · V = n · R · T',
      keteranganRumus: const [
        'P = Tekanan gas (Pa)',
        'V = Volume wadah/bola (m³)',
        'n = Jumlah mol gas (mol)',
        'R = Konstanta gas (8,314 J/mol·K)',
        'T = Suhu mutlak gas (Kelvin)',
      ],
      judulContoh: 'Contoh Penerapan & Hitungan',
      isiContoh:
          'Saat bola dipompa, jumlah partikel gas (n) bertambah sehingga tekanan (P) di dalam bola naik dan bola menjadi keras.\n'
          'Begitu juga saat bola dijemur di bawah matahari, kenaikan suhu (T) membuat tekanan gas ikut meningkat.',
    );
  }
}

class _KartuMateriTeori extends StatelessWidget {
  const _KartuMateriTeori({
    required this.modeTerang,
    required this.judul,
    required this.penjelasanSingkat,
    required this.rumus,
    required this.keteranganRumus,
    required this.judulContoh,
    required this.isiContoh,
  });

  final bool modeTerang;
  final String judul;
  final String penjelasanSingkat;
  final String rumus;
  final List<String> keteranganRumus;
  final String judulContoh;
  final String isiContoh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Penjelasan Singkat + Rumus Besar
        ParchmentCard(
          modeTerang: modeTerang,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.lightbulb_rounded,
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
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                penjelasanSingkat,
                style: AppTextStyles.label(modeTerang: modeTerang),
              ),
              const SizedBox(height: AppSpacing.s16),

              // Kotak Rumus Besar (28sp Bold)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.s16,
                  horizontal: AppSpacing.s12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppRadius.buttonBorder,
                  border: Border.all(
                    color: AppColors.tekananPalette.cardBorderLight,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'RUMUS UTAMA',
                      style: AppTextStyles.caption(
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rumus,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sensorValue(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s12),

              for (final item in keteranganRumus)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item,
                          style: AppTextStyles.label(modeTerang: modeTerang),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),

        // 2. Satu Contoh Nyata & Hitungan
        ParchmentCard(
          modeTerang: modeTerang,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calculate_rounded,
                    color: AppColors.success,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      judulContoh,
                      style: AppTextStyles.sectionTitle(modeTerang: modeTerang),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                isiContoh,
                style: AppTextStyles.label(modeTerang: modeTerang),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===== Lukisan Ilustrasi Praktikum =====

class _BlockForcePainter extends CustomPainter {
  const _BlockForcePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.64;

    final base = Path()
      ..moveTo(cx - 68, cy + 14)
      ..lineTo(cx, cy - 6)
      ..lineTo(cx + 68, cy + 14)
      ..lineTo(cx, cy + 34)
      ..close();
    canvas.drawPath(base, Paint()..color = const Color(0xFF334155));

    const r = 28.0;
    const dx = r * 0.866;
    const dy = r * 0.45;
    final top = Path()
      ..moveTo(cx, cy - r - 10)
      ..lineTo(cx + dx, cy - dy - 10)
      ..lineTo(cx, cy - 10)
      ..lineTo(cx - dx, cy - dy - 10)
      ..close();
    final left = Path()
      ..moveTo(cx - dx, cy - dy - 10)
      ..lineTo(cx, cy - 10)
      ..lineTo(cx, cy + r - 10)
      ..lineTo(cx - dx, cy + dy - 10)
      ..close();
    final right = Path()
      ..moveTo(cx, cy - 10)
      ..lineTo(cx + dx, cy - dy - 10)
      ..lineTo(cx + dx, cy + dy - 10)
      ..lineTo(cx, cy + r - 10)
      ..close();

    canvas.drawPath(top, Paint()..color = const Color(0xFFDBEAFE));
    canvas.drawPath(left, Paint()..color = const Color(0xFF60A5FA));
    canvas.drawPath(right, Paint()..color = const Color(0xFF2563EB));

    final arrowPaint = Paint()..color = const Color(0xFFDC2626);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy - 48), width: 6, height: 12),
      arrowPaint,
    );
    final head = Path()
      ..moveTo(cx - 9, cy - 42)
      ..lineTo(cx + 9, cy - 42)
      ..lineTo(cx, cy - 31)
      ..close();
    canvas.drawPath(head, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BeakerDepthPainter extends CustomPainter {
  const _BeakerDepthPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;

    final waterRect = RRect.fromRectAndCorners(
      Rect.fromCenter(
        center: Offset(cx, h * 0.60),
        width: 68,
        height: h * 0.52,
      ),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
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

    final glassRect = RRect.fromRectAndCorners(
      Rect.fromCenter(
        center: Offset(cx, h * 0.50),
        width: 72,
        height: h * 0.76,
      ),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    canvas.drawRRect(
      glassRect,
      Paint()
        ..color = const Color(0xFF1E3A8A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    final arrowX = cx + 48;
    final arrowPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(arrowX, h * 0.34),
      Offset(arrowX, h * 0.84),
      arrowPaint,
    );

    final tp = TextPainter(
      text: const TextSpan(
        text: 'h',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          color: Color(0xFF1D4ED8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(arrowX + 6, h * 0.52));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BalloonManometerPainter extends CustomPainter {
  const _BalloonManometerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;

    final balloonRect = Rect.fromCenter(
      center: Offset(cx - 28, h * 0.44),
      width: 52,
      height: 64,
    );
    canvas.drawOval(
      balloonRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFCA5A5), Color(0xFFDC2626), Color(0xFF991B1B)],
        ).createShader(balloonRect),
    );

    final tube = Path()
      ..moveTo(cx - 28, h * 0.76)
      ..quadraticBezierTo(cx - 28, h * 0.92, cx + 2, h * 0.86)
      ..quadraticBezierTo(cx + 32, h * 0.80, cx + 32, h * 0.64);
    canvas.drawPath(
      tube,
      Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final gaugeCenter = Offset(cx + 32, h * 0.46);
    canvas.drawCircle(gaugeCenter, 18, Paint()..color = Colors.white);
    canvas.drawCircle(
      gaugeCenter,
      18,
      Paint()
        ..color = const Color(0xFF1E3A8A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
    canvas.drawLine(
      gaugeCenter,
      gaugeCenter + const Offset(8, -8),
      Paint()
        ..color = const Color(0xFFDC2626)
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
