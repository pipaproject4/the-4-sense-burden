import 'package:flutter/material.dart';

import 'dashboard_page.dart';
import 'data_praktikum_page.dart';
import 'mqtt_service.dart';
import 'pengaturan_page.dart';
import 'praktikum_detail_page.dart';
import 'praktikum_menu_page.dart';
import 'splash_screen.dart';
import 'theme_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Aplikasi4SenseBurden());
}

class Aplikasi4SenseBurden extends StatefulWidget {
  const Aplikasi4SenseBurden({super.key});

  @override
  State<Aplikasi4SenseBurden> createState() => _Aplikasi4SenseBurdenState();
}

class _Aplikasi4SenseBurdenState extends State<Aplikasi4SenseBurden> {
  final MqttService _layanan = MqttService();
  bool _tampilSplash = true;
  int _tabAktif = 0; // 0=Beranda, 1=Praktikum, 2=Data, 3=Pengaturan
  int? _modePraktikumAktif; // null=menu pilih, 2=Padat, 0=Cair, 1=Gas

  @override
  void initState() {
    super.initState();
    _layanan.muatPengaturan().then((_) => _layanan.sambung());
  }

  @override
  void dispose() {
    _layanan.dispose();
    super.dispose();
  }

  void _bukaPraktikumMode(int mode) {
    _layanan.kirimPerintahMode(mode);
    setState(() {
      _tabAktif = 1;
      _modePraktikumAktif = mode;
    });
  }

  void _bukaMenuPraktikum() {
    setState(() {
      _tabAktif = 1;
      _modePraktikumAktif = null;
    });
  }

  bool get _diLayarUtama => !(_tabAktif == 1 && _modePraktikumAktif != null);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _layanan,
      builder: (context, _) {
        return MaterialApp(
          title: 'The 4 Sense Burden',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(modeTerang: _layanan.modeTerang),
          home: _tampilSplash
              ? SplashScreen(
                  onSelesai: () => setState(() => _tampilSplash = false),
                )
              : Scaffold(
                  body: JapaneseScienceBackground(
                    modeTerang: _layanan.modeTerang,
                    child: Column(
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _bangunHalamanAktif(),
                          ),
                        ),
                        if (_diLayarUtama)
                          _BottomNavDock(
                            tabAktif: _tabAktif,
                            modeTerang: _layanan.modeTerang,
                            jumlahData: _layanan.riwayatSesi.length,
                            onPilihTab: (idx) {
                              setState(() {
                                if (idx == 1) {
                                  _modePraktikumAktif = null;
                                }
                                _tabAktif = idx;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _bangunHalamanAktif() {
    switch (_tabAktif) {
      case 0:
        return DashboardPage(
          key: const ValueKey('page_dashboard'),
          layanan: _layanan,
          onBukaPraktikum: _bukaPraktikumMode,
          onMulaiPraktikum: _bukaMenuPraktikum,
          onBukaPengaturan: () => setState(() => _tabAktif = 3),
        );
      case 1:
        if (_modePraktikumAktif == null) {
          return PraktikumMenuPage(
            key: const ValueKey('page_praktikum_menu'),
            modeTerang: _layanan.modeTerang,
            onPilihMode: (m) {
              _layanan.kirimPerintahMode(m);
              setState(() => _modePraktikumAktif = m);
            },
            onKembali: () => setState(() => _tabAktif = 0),
          );
        }
        return PraktikumDetailPage(
          key: ValueKey('page_praktikum_$_modePraktikumAktif'),
          mode: _modePraktikumAktif!,
          layanan: _layanan,
          onKembali: () => setState(() => _modePraktikumAktif = null),
          onSelesaiSimpan: () {
            setState(() {
              _modePraktikumAktif = null;
              _tabAktif = 2;
            });
          },
        );
      case 2:
        return DataPraktikumPage(
          key: const ValueKey('page_data'),
          layanan: _layanan,
          onKembali: () => setState(() => _tabAktif = 0),
        );
      case 3:
      default:
        return PengaturanPage(
          key: const ValueKey('page_pengaturan'),
          layanan: _layanan,
          onKembali: () => setState(() => _tabAktif = 0),
        );
    }
  }
}

/// Navigasi bawah hanya untuk 4 layar utama (Beranda, Praktikum, Data, Pengaturan).
class _BottomNavDock extends StatelessWidget {
  const _BottomNavDock({
    required this.tabAktif,
    required this.modeTerang,
    required this.jumlahData,
    required this.onPilihTab,
  });

  final int tabAktif;
  final bool modeTerang;
  final int jumlahData;
  final ValueChanged<int> onPilihTab;

  @override
  Widget build(BuildContext context) {
    final bg = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final border = modeTerang ? AppColors.borderLight : AppColors.borderDark;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenMargin,
        AppSpacing.s4,
        AppSpacing.screenMargin,
        AppSpacing.s8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: modeTerang ? 0.06 : 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavDockItem(
              ikon: Icons.home_rounded,
              label: 'Beranda',
              aktif: tabAktif == 0,
              modeTerang: modeTerang,
              onTap: () => onPilihTab(0),
            ),
          ),
          Expanded(
            child: _NavDockItem(
              ikon: Icons.science_rounded,
              label: 'Praktikum',
              aktif: tabAktif == 1,
              modeTerang: modeTerang,
              onTap: () => onPilihTab(1),
            ),
          ),
          Expanded(
            child: _NavDockItem(
              ikon: Icons.bar_chart_rounded,
              label: 'Data',
              badge: jumlahData > 0 ? '$jumlahData' : null,
              aktif: tabAktif == 2,
              modeTerang: modeTerang,
              onTap: () => onPilihTab(2),
            ),
          ),
          Expanded(
            child: _NavDockItem(
              ikon: Icons.settings_rounded,
              label: 'Pengaturan',
              aktif: tabAktif == 3,
              modeTerang: modeTerang,
              onTap: () => onPilihTab(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDockItem extends StatelessWidget {
  const _NavDockItem({
    required this.ikon,
    required this.label,
    required this.aktif,
    required this.modeTerang,
    required this.onTap,
    this.badge,
  });

  final IconData ikon;
  final String label;
  final bool aktif;
  final bool modeTerang;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final warna = aktif
        ? AppColors.primary
        : (modeTerang
              ? AppColors.textSecondaryLight
              : AppColors.textSecondaryDark);

    return Semantics(
      button: true,
      selected: aktif,
      label: 'Tab $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.buttonBorder,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: aktif
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: AppRadius.buttonBorder,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badge != null,
                  label: badge != null
                      ? Text(
                          badge!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                  child: Icon(ikon, color: warna, size: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: aktif ? FontWeight.w800 : FontWeight.w600,
                    color: warna,
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
