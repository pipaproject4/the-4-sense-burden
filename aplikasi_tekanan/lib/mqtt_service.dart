import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StatusKoneksi { putus, menyambung, tersambung }

/// Satu paket data dari ESP32 (JSON di topik `tekanan/ID_ALAT/data`).
class Pembacaan {
  Pembacaan(this.waktu, this.data);

  final DateTime waktu;
  final Map<String, dynamic> data;

  int get mode => (data['mode'] as num?)?.toInt() ?? -1;
  String get namaMode => (data['mode_nama'] as String?) ?? '-';
  double? angka(String kunci) => (data[kunci] as num?)?.toDouble();

  Map<String, dynamic> toJson() => {
    'waktu': waktu.toIso8601String(),
    'data': data,
  };

  factory Pembacaan.fromJson(Map<String, dynamic> json) {
    return Pembacaan(
      DateTime.tryParse(json['waktu'] as String? ?? '') ?? DateTime.now(),
      Map<String, dynamic>.from(json['data'] as Map? ?? {}),
    );
  }
}

/// Satu sesi hasil praktikum (Zat Padat / Zat Cair / Zat Gas) yang disimpan ke Riwayat.
class SesiPraktikum {
  SesiPraktikum({
    required this.id,
    required this.mode,
    required this.judul,
    required this.waktu,
    required this.ringkasan,
    required this.sampel,
  });

  final String id;
  final int mode; // 0 = Zat Cair, 1 = Zat Gas, 2 = Zat Padat
  final String judul;
  final DateTime waktu;
  final Map<String, double> ringkasan;
  final List<Pembacaan> sampel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mode': mode,
    'judul': judul,
    'waktu': waktu.toIso8601String(),
    'ringkasan': ringkasan,
    'sampel': sampel.map((e) => e.toJson()).toList(),
  };

  factory SesiPraktikum.fromJson(Map<String, dynamic> json) {
    final rawRingkasan = Map<String, dynamic>.from(
      json['ringkasan'] as Map? ?? {},
    );
    final ringkasan = <String, double>{};
    for (final entry in rawRingkasan.entries) {
      if (entry.value is num) {
        ringkasan[entry.key] = (entry.value as num).toDouble();
      }
    }
    final rawSampel = (json['sampel'] as List?) ?? const [];
    return SesiPraktikum(
      id:
          json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      mode: (json['mode'] as num?)?.toInt() ?? 1,
      judul: json['judul'] as String? ?? 'Zat Gas',
      waktu:
          DateTime.tryParse(json['waktu'] as String? ?? '') ?? DateTime.now(),
      ringkasan: ringkasan,
      sampel: rawSampel
          .whereType<Map>()
          .map((e) => Pembacaan.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Layanan utama MQTT, pengaturan satuan, dan penyimpanan riwayat praktikum.
class MqttService extends ChangeNotifier {
  static const String brokerBawaan = 'broker.hivemq.com';
  static const int portBawaan = 1883;
  static const String idAlatBawaan = 'alat01';
  static const int batasRiwayat = 300;

  String host = brokerBawaan;
  int port = portBawaan;
  String idAlat = idAlatBawaan;

  // Pengaturan aplikasi sesuai layar Pengaturan
  String satuanTekanan = 'kPa'; // 'kPa', 'Pa', 'bar'
  String satuanSuhu = '°C'; // '°C', 'K'
  bool modeTerang = true;
  bool simpanOtomatis = true;

  StatusKoneksi status = StatusKoneksi.putus;
  bool alatOnline = false;
  String? pesanError;

  Pembacaan? terakhir;
  Pembacaan? terakhirCair;
  Pembacaan? terakhirGas;
  Pembacaan? terakhirPadat;

  final List<Pembacaan> riwayat = [];
  final List<SesiPraktikum> riwayatSesi = [];

  MqttServerClient? _klien;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _langganan;

  String get topikData => 'tekanan/$idAlat/data';
  String get topikStatus => 'tekanan/$idAlat/status';
  String get topikPerintah => 'tekanan/$idAlat/perintah';

  /// Kirim perintah ganti mode ke ESP32 (`0` = Zat Cair, `1` = Zat Gas, `2` = Zat Padat).
  void kirimPerintahMode(int mode) {
    final klien = _klien;
    if (klien == null || status != StatusKoneksi.tersambung) return;
    final builder = MqttClientPayloadBuilder()..addString('MODE:$mode');
    final payload = builder.payload;
    if (payload != null) {
      klien.publishMessage(topikPerintah, MqttQos.atLeastOnce, payload);
    }
  }

  /// Hitung statistik (min, max, rata-rata) suatu besaran dari riwayat live.
  Map<String, double>? statistikBesaran(
    int mode,
    String kunci, {
    double pengali = 1.0,
    double offset = 0.0,
  }) {
    final nilaiList = <double>[];
    for (final p in riwayat) {
      if (p.mode == mode || mode < 0) {
        final raw = p.angka(kunci);
        if (raw != null) {
          nilaiList.add(raw * pengali + offset);
        }
      }
    }
    if (nilaiList.isEmpty) return null;
    var minV = nilaiList.first;
    var maxV = nilaiList.first;
    var sumV = 0.0;
    for (final v in nilaiList) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
      sumV += v;
    }
    return {
      'min': minV,
      'max': maxV,
      'avg': sumV / nilaiList.length,
      'count': nilaiList.length.toDouble(),
    };
  }

  // Helper konversi nilai untuk tampilan
  double konversiTekanan(double pa) {
    if (satuanTekanan == 'Pa') return pa;
    if (satuanTekanan == 'bar') return pa / 100000.0;
    return pa / 1000.0; // kPa
  }

  String formatTekanan(double? pa, {int? desimal}) {
    if (pa == null) return '--';
    final v = konversiTekanan(pa);
    final d =
        desimal ??
        (satuanTekanan == 'Pa'
            ? 1
            : satuanTekanan == 'bar'
            ? 4
            : 2);
    return v.toStringAsFixed(d);
  }

  double konversiSuhu(double kelvin) {
    if (satuanSuhu == 'K') return kelvin;
    return kelvin - 273.15;
  }

  String formatSuhu(double? kelvin, {int desimal = 1}) {
    if (kelvin == null) return '--';
    return konversiSuhu(kelvin).toStringAsFixed(desimal);
  }

  // Ambil nilai terakhir untuk masing-masing besaran (dari paket terbaru atau cache mode)
  double? get tekananGasKPa {
    final pa =
        terakhirGas?.angka('p_gauge_pa') ??
        terakhirGas?.angka('p_pa') ??
        terakhir?.angka('p_pa');
    return pa != null ? pa / 1000.0 : null;
  }

  double? get tekananGasPa =>
      terakhirGas?.angka('p_gauge_pa') ??
      terakhirGas?.angka('p_pa') ??
      (terakhir?.mode == 1 ? terakhir?.angka('p_pa') : null);

  double? get suhuGasK =>
      terakhirGas?.angka('suhu_k') ?? terakhir?.angka('suhu_k');

  double? get volumeGasM3 =>
      terakhirGas?.angka('volume_m3') ?? terakhir?.angka('volume_m3');

  double? get molGas => terakhirGas?.angka('n_mol') ?? terakhir?.angka('n_mol');

  double? get tekananCairPa =>
      terakhirCair?.angka('p_cair_pa') ??
      terakhirCair?.angka('p_pa') ??
      (terakhir?.mode == 0 ? terakhir?.angka('p_pa') : null);

  double? get tinggiCairCm =>
      terakhirCair?.angka('tinggi_cm') ?? terakhir?.angka('tinggi_cm');

  double? get rhoCair =>
      terakhirCair?.angka('rho') ?? terakhir?.angka('rho') ?? 1000.0;

  double? get tekananPadatPa =>
      terakhirPadat?.angka('p_padat_pa') ??
      terakhirPadat?.angka('p_pa') ??
      (terakhir?.mode == 2 ? terakhir?.angka('p_pa') : null);

  double? get gayaPadatN =>
      terakhirPadat?.angka('gaya_n') ?? terakhir?.angka('gaya_n');

  double? get luasPadatCm2 =>
      terakhirPadat?.angka('luas_cm2') ?? terakhir?.angka('luas_cm2');

  double? get massaPadatG =>
      terakhirPadat?.angka('massa_g') ?? terakhir?.angka('massa_g');

  Future<void> muatPengaturan() async {
    final prefs = await SharedPreferences.getInstance();
    host = prefs.getString('host') ?? brokerBawaan;
    port = prefs.getInt('port') ?? portBawaan;
    idAlat = prefs.getString('idAlat') ?? idAlatBawaan;
    satuanTekanan = prefs.getString('satuanTekanan') ?? 'kPa';
    satuanSuhu = prefs.getString('satuanSuhu') ?? '°C';
    modeTerang = prefs.getBool('modeTerang') ?? true;
    simpanOtomatis = prefs.getBool('simpanOtomatis') ?? true;

    final rawSesi = prefs.getString('riwayatSesi_v2');
    riwayatSesi.clear();
    if (rawSesi != null && rawSesi.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSesi) as List;
        for (final item in decoded) {
          if (item is Map) {
            riwayatSesi.add(
              SesiPraktikum.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> simpanPengaturanKoneksi(
    String hostBaru,
    int portBaru,
    String idAlatBaru,
  ) async {
    host = hostBaru;
    port = portBaru;
    idAlat = idAlatBaru;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', host);
    await prefs.setInt('port', port);
    await prefs.setString('idAlat', idAlat);
    notifyListeners();
  }

  Future<void> aturSatuan({String? tekanan, String? suhu}) async {
    if (tekanan != null) satuanTekanan = tekanan;
    if (suhu != null) satuanSuhu = suhu;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('satuanTekanan', satuanTekanan);
    await prefs.setString('satuanSuhu', satuanSuhu);
    notifyListeners();
  }

  Future<void> aturModeTerang(bool nilai) async {
    modeTerang = nilai;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('modeTerang', modeTerang);
    notifyListeners();
  }

  Future<void> aturSimpanOtomatis(bool nilai) async {
    simpanOtomatis = nilai;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('simpanOtomatis', simpanOtomatis);
    notifyListeners();
  }

  Future<void> tambahSesiPraktikum(SesiPraktikum sesi) async {
    riwayatSesi.insert(0, sesi);
    await _simpanRiwayatKeDisk();
    notifyListeners();
  }

  Future<void> hapusSesiPraktikum(String id) async {
    riwayatSesi.removeWhere((e) => e.id == id);
    await _simpanRiwayatKeDisk();
    notifyListeners();
  }

  Future<void> kosongkanSesiPraktikum() async {
    riwayatSesi.clear();
    await _simpanRiwayatKeDisk();
    notifyListeners();
  }

  Future<void> _simpanRiwayatKeDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(riwayatSesi.map((e) => e.toJson()).toList());
    await prefs.setString('riwayatSesi_v2', encoded);
  }

  String buatCsvRiwayat() {
    final b = StringBuffer()
      ..writeln(
        'No,Waktu,Jenis Praktikum,Tekanan (kPa),Gaya (N),Luas (cm2),Kedalaman (m),Massa Jenis (kg/m3),Suhu (C),Volume (m3),Jumlah Mol (mol)',
      );
    for (var i = 0; i < riwayatSesi.length; i++) {
      final s = riwayatSesi[i];
      final w = _formatTanggalJam(s.waktu);
      final pKpa = ((s.ringkasan['p_pa'] ?? 0) / 1000.0).toStringAsFixed(2);
      final f = s.ringkasan['gaya_n']?.toStringAsFixed(2) ?? '-';
      final a = s.ringkasan['luas_cm2']?.toStringAsFixed(2) ?? '-';
      final hM = s.ringkasan['tinggi_cm'] != null
          ? (s.ringkasan['tinggi_cm']! / 100.0).toStringAsFixed(2)
          : '-';
      final rho = s.ringkasan['rho']?.toStringAsFixed(0) ?? '-';
      final suhuC = s.ringkasan['suhu_k'] != null
          ? (s.ringkasan['suhu_k']! - 273.15).toStringAsFixed(1)
          : '-';
      final vol = s.ringkasan['volume_m3']?.toStringAsFixed(6) ?? '-';
      final mol = s.ringkasan['n_mol']?.toStringAsFixed(6) ?? '-';
      b.writeln(
        '${i + 1},"$w","${s.judul}",$pKpa,$f,$a,$hM,$rho,$suhuC,$vol,$mol',
      );
    }
    return b.toString();
  }

  String buatLaporanTeks() {
    final b = StringBuffer()
      ..writeln('============================================')
      ..writeln('   LAPORAN PRAKTIKUM - THE 4 SENSE BURDEN   ')
      ..writeln('============================================')
      ..writeln('ID Alat : $idAlat')
      ..writeln('Dicetak : ${_formatTanggalJam(DateTime.now())}')
      ..writeln('--------------------------------------------\n');
    if (riwayatSesi.isEmpty) {
      b.writeln('Belum ada data riwayat praktikum.');
    } else {
      for (var i = 0; i < riwayatSesi.length; i++) {
        final s = riwayatSesi[i];
        b.writeln('${i + 1}. ${s.judul} (${_formatTanggalJam(s.waktu)})');
        final pKpa = ((s.ringkasan['p_pa'] ?? 0) / 1000.0).toStringAsFixed(2);
        b.writeln('   • Tekanan (P)     : $pKpa kPa');
        if (s.mode == 2) {
          b.writeln(
            '   • Gaya (F)        : ${(s.ringkasan['gaya_n'] ?? 0).toStringAsFixed(2)} N',
          );
          b.writeln(
            '   • Luas (A)        : ${(s.ringkasan['luas_cm2'] ?? 0).toStringAsFixed(2)} cm²',
          );
        } else if (s.mode == 0) {
          b.writeln(
            '   • Kedalaman (h)   : ${((s.ringkasan['tinggi_cm'] ?? 0) / 100.0).toStringAsFixed(2)} m',
          );
          b.writeln(
            '   • Massa Jenis (ρ) : ${(s.ringkasan['rho'] ?? 1000).toStringAsFixed(0)} kg/m³',
          );
        } else if (s.mode == 1) {
          final suhuC = s.ringkasan['suhu_k'] != null
              ? (s.ringkasan['suhu_k']! - 273.15).toStringAsFixed(1)
              : '--';
          b.writeln('   • Suhu Gas (T)    : $suhuC °C');
          b.writeln(
            '   • Volume Bola (V) : ${(s.ringkasan['volume_m3'] ?? 0).toStringAsFixed(6)} m³',
          );
          b.writeln(
            '   • Jumlah Mol (n)  : ${(s.ringkasan['n_mol'] ?? 0).toStringAsFixed(6)} mol',
          );
        }
        b.writeln('   • Jumlah Sampel   : ${s.sampel.length} titik data\n');
      }
    }
    return b.toString();
  }

  String _formatTanggalJam(DateTime w) {
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

  Future<void> sambung() async {
    await putuskan();
    status = StatusKoneksi.menyambung;
    pesanError = null;
    alatOnline = false;
    notifyListeners();

    final idKlien = 'sense4-${DateTime.now().millisecondsSinceEpoch}';
    final klien = MqttServerClient.withPort(host, idKlien, port)
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..logging(on: false)
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(idKlien)
          .startClean();

    klien.onConnected = () {
      status = StatusKoneksi.tersambung;
      notifyListeners();
    };
    klien.onAutoReconnect = () {
      status = StatusKoneksi.menyambung;
      notifyListeners();
    };
    klien.onAutoReconnected = () {
      status = StatusKoneksi.tersambung;
      notifyListeners();
    };
    klien.onDisconnected = () {
      if (_klien == klien) {
        status = StatusKoneksi.putus;
        alatOnline = false;
        notifyListeners();
      }
    };

    _klien = klien;
    try {
      await klien.connect().timeout(const Duration(seconds: 10));
    } catch (_) {
      klien.disconnect();
      _klien = null;
      status = StatusKoneksi.putus;
      pesanError = 'Gagal terhubung ke broker MQTT. Periksa koneksi internet.';
      notifyListeners();
      return;
    }

    klien.subscribe(topikData, MqttQos.atMostOnce);
    klien.subscribe(topikStatus, MqttQos.atMostOnce);
    _langganan = klien.updates?.listen(_terimaPesan);
  }

  void _terimaPesan(List<MqttReceivedMessage<MqttMessage>> pesan) {
    for (final p in pesan) {
      final isi = p.payload as MqttPublishMessage;
      final teks = MqttPublishPayload.bytesToStringAsString(
        isi.payload.message,
      );
      if (p.topic == topikStatus) {
        alatOnline = teks.trim() == 'online';
      } else if (p.topic == topikData) {
        try {
          final json = jsonDecode(teks);
          if (json is Map<String, dynamic>) {
            final baru = Pembacaan(DateTime.now(), json);
            terakhir = baru;
            alatOnline = true;
            if (baru.mode == 0) terakhirCair = baru;
            if (baru.mode == 1) terakhirGas = baru;
            if (baru.mode == 2) terakhirPadat = baru;
            riwayat.add(baru);
            if (riwayat.length > batasRiwayat) riwayat.removeAt(0);
          }
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> putuskan() async {
    await _langganan?.cancel();
    _langganan = null;
    final klien = _klien;
    _klien = null;
    klien?.disconnect();
    status = StatusKoneksi.putus;
    alatOnline = false;
  }

  @override
  void dispose() {
    putuskan();
    super.dispose();
  }
}
