#include <Arduino.h>
#include <DHT.h>
#include <HX711.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <U8g2lib.h>
#include <WiFi.h>
#include <Wire.h>
#include <esp_err.h>
#include <math.h>
#include <nvs.h>
#include <nvs_flash.h>
#include <stdio.h>

// Ganti dengan WiFi 2.4 GHz yang dapat digunakan ESP32 Anda.
const char WIFI_SSID[] = "ABCD-2.4G";
const char WIFI_PASS[] = "qwerty123";

// ===== MQTT =====
// Broker publik gratis (tanpa akun). Siapa pun yang tahu nama topik dapat
// membaca data, jadi gunakan ID_ALAT yang unik untuk tiap alat/kelompok.
const char MQTT_HOST[] = "broker.hivemq.com";
const uint16_t MQTT_PORT = 1883;
const char ID_ALAT[] = "alat01"; // ganti per alat, mis. alat02, alat03
// Topik data (JSON, dikirim berkala): tekanan/<ID_ALAT>/data
// Topik status online/offline (LWT):  tekanan/<ID_ALAT>/status
// ===== PIN ESP32 DEVKIT V1 =====
#define PIN_SDA 21
#define PIN_SCL 22
#define CAIR_OUT 34
#define CAIR_SCK 25
#define GAS_OUT 35
#define GAS_SCK 26
#define HX711_DT 32
#define HX711_SCK 33
// 4 HC-SR04: pasangan 1-2 mengukur panjang, 3-4 mengukur lebar.
// TRIG ke output ESP32. Setiap ECHO 5 V HARUS melalui pembagi tegangan
// atau level shifter ke input 3,3 V ESP32 (termasuk GPIO36 dan GPIO39).
const uint8_t US_TRIG[4] = {18, 16, 23, 4};
const uint8_t US_ECHO[4] = {19, 17, 36, 39};
// GPIO36/39 input-only, cocok untuk ECHO; GPIO4 tidak boleh ditarik eksternal
// saat boot. Gunakan ESP32-WROOM-32 seperti yang dipakai pada proyek ini.

#define BTN_NEXT 13
#define BTN_PREV 14
#define BTN_SELECT 27
// DHT22 memakai satu pin DATA, bukan I2C. GPIO16 sudah terpakai sonar.
// GPIO5 tersedia di wiring saat ini; termasuk pin strapping ESP32.
// Pastikan pull-up DATA hanya ke 3V3 dan uji boot normal.
#define DHT_PIN 5
#define DHT_TIPE DHT22

U8G2_SH1106_128X64_NONAME_F_HW_I2C oled(U8G2_R0, U8X8_PIN_NONE);
DHT dht(DHT_PIN, DHT_TIPE);
HX711 loadcell;
Preferences prefs;
Preferences prefsProfil; // namespace prof3_us: pola 4 HC-SR04, terpisah dari
                         // kalibrasi lama.
bool profilNvsSiap =
    false; // cek hasil begin() sebelum menyimpan/membaca LEARN.

const float G = 9.81f;
float rho = 1000.0f;
float jarakSonarRaw[4] = {NAN, NAN, NAN, NAN};
float jarakSonarHalus[4] = {NAN, NAN, NAN, NAN};
unsigned long waktuSonar[4] = {0, 0, 0, 0};
uint8_t sonarAktif = 0;
unsigned long pingSonarTerakhir = 0;

int pressureUnit = 0; // 0=kPa, 1=Pa, 2=bar
long zeroCair = 0, zeroGas = 0, zeroLoad = 0;
float scaleCair = 0, scaleGas = 0, scaleLoad = 0;
long rawCair = 0, rawGas = 0, rawLoad = 0;
bool cairOK = false, gasOK = false, loadOK = false;
unsigned long lastCairOK = 0, lastGasOK = 0, lastLoadOK = 0;
float airTempC =
    NAN; // Suhu DHT22 terfilter (Celsius), dikonversi ke Kelvin di output.
float suhuDhtSensorC = NAN; // Pembacaan DHT22 terakhir tanpa filter.

const float SUHU_ACUAN_C = 24.0f;
const float SUHU_DHT_ACUAN_C = 29.05f;

const float OFFSET_SUHU_C = SUHU_ACUAN_C - SUHU_DHT_ACUAN_C;

float kelembapanDht =
    NAN;             // RH (%), informasi tambahan, tidak masuk rumus P gas.
float molGas = 0.0f; // Tidak diisi asumsi; tentukan dari kondisi awal valid
float diameterBalonCm = 0.0f; // Diameter ukur manual (cm)
bool molFromBaseline = false; // true setelah n diambil dari P0 V0 T0
// Mol acuan diagnostik berasal dari GASBASE (diameter awal) atau N <mol>.
// Estimasi mol saat ini dihitung terpisah dari Pabs, kurva volume, dan suhu.
bool gasManualMolActive = false;
float gasP0KPa = NAN, gasT0K = NAN, gasV0L = NAN;
bool gasBaselineValid = false;
const float R_GAS = 8.314462618f;
// Tekanan atmosfer adalah parameter acuan (kPa), bukan hasil ukur DHT22.
// Default 101.325 kPa adalah contoh standar; ubah lewat PATM atau menu.
float tekananAtmosferKPa = 101.325f;
// Kurva tekanan gauge HX710B vs VOLUME BALON saja; 0 L = balon belum
// mengembang. Diisi lewat dua PREV atau BALONZERO, BALONCAL <Dcm>, BALONM3
// <m3>. Kurva dan NVS tetap dalam liter untuk kompatibilitas; keluaran dalam
// m3.
const uint8_t BALON_MAX_TITIK = 8;
uint8_t balonJumlahTitik = 0;
float balonPKPa[BALON_MAX_TITIK] = {0};
float balonVolumeL[BALON_MAX_TITIK] = {0};
const float BALON_BEDA_P_MIN_KPA =
    0.005f; // pisahkan titik 5 Pa agar tidak ganda
// DHT22 tidak punya alamat I2C; dht.begin() dipanggil pada setup().
bool dhtOK = false;
unsigned long waktuDhtValid = 0;
uint8_t dhtGagal = 0;
const unsigned long DHT_INTERVAL_MS =
    2500UL; // DHT22: interval minimum sekitar 2 detik
const unsigned long DHT_STALE_MS =
    7500UL; // pembacaan gagal sesaat tidak langsung mengganti hasil lama

// ===== FILTER DIGITAL: median 5 sampel -> EMA =====
// Terapkan pada RAW, bukan membuang digit belakang RAW.
// Alpha kecil membuat angka lebih halus, tetapi respons lebih lambat.
struct MedianEma5 {
  float buf[5] = {0, 0, 0, 0, 0};
  uint8_t count = 0, pos = 0;
  float value = NAN;
  void add(float sample, float alpha = 0.10f) {
    if (!isfinite(sample))
      return;
    buf[pos] = sample;
    pos = (pos + 1) % 5;
    if (count < 5)
      count++;
    float ordered[5];
    for (int i = 0; i < count; i++)
      ordered[i] = buf[i];
    for (int i = 1; i < count; i++) {
      float v = ordered[i];
      int j = i - 1;
      while (j >= 0 && ordered[j] > v) {
        ordered[j + 1] = ordered[j];
        j--;
      }
      ordered[j + 1] = v;
    }
    float med = ordered[count / 2];
    if (count % 2 == 0)
      med = (ordered[count / 2 - 1] + ordered[count / 2]) / 2.0f;
    value = isfinite(value) ? alpha * med + (1.0f - alpha) * value : med;
  }
  bool ready() const { return count == 5 && isfinite(value); }
};
MedianEma5 filterCair, filterGasHx, filterLoad;
MedianEma5 filterDhtT;
MedianEma5 filterSonar[4];
// Nilai kPa yang dilihat pada dashboard diperbarui hanya setiap 500 ms.
float tampilKPa[3] = {NAN, NAN, NAN};
unsigned long terakhirTampil[3] = {0, 0, 0};
const unsigned long INTERVAL_TAMPIL_MS = 500;

// ===== HALAMAN =====
// ===== HALAMAN & NAVIGASI =====
enum Page {
  WELCOME,
  HOME,
  MEASURE,
  DETAIL,
  MENU,
  SUBMENU,
  EDIT_VALUE,
  CONFIRM_RESET,
  MESSAGE,
  QUICK_CAL
};
// Boot selalu masuk landing animasi; SELECT untuk masuk pilihan mode.
Page page = WELCOME;
Page returnAfterSettings = HOME;
Page messageBack = MENU;
int mode = 0;        // 0=cair 1=gas 2=padat
int detailIndex = 0; // dua halaman detail gas/padat
int menuIndex = 0, submenuIndex = 0;
int editKind = 0; // 0 rho, 2 mol, 3 diameter, 4 satuan, 8 P atmosfer
float editValue = 0;
String info = "";
const char *menuItems[] = {
    "Parameter Cair", "Parameter Gas",   "Parameter Padat", "Kalibrasi Sensor",
    "Diagnostik",     "Satuan & Sistem", "Kembali"};
const int MENU_SIZE = sizeof(menuItems) / sizeof(menuItems[0]);
const char *names[3] = {"ZAT CAIR", "ZAT GAS", "ZAT PADAT"};
// Tampilan menu dibuat PADAT -> CAIR -> GAS, sementara indeks mode internal
// tetap 0=cair, 1=gas, 2=padat agar seluruh fungsi sensor tidak berubah.
const uint8_t HOME_ORDER[3] = {2, 0, 1};
uint8_t homeSelection = 0;

// Navigasi sederhana tanpa double-click:
// SELECT sekali = detail; NEXT sekali = kembali ke menu pilihan tekanan;
// SELECT ditahan 2 detik = menu pengaturan.

uint8_t selectedHomeFromMode(int m) {
  for (uint8_t i = 0; i < 3; i++)
    if (HOME_ORDER[i] == m)
      return i;
  return 0;
}
void goToModeSelection() {
  // Pilih item mode terakhir ketika kembali ke menu.
  homeSelection = selectedHomeFromMode(mode);
  page = HOME;
}

// ===== TOMBOL, DEBOUNCE =====
struct Button {
  uint8_t pin;
  bool lastRaw = HIGH;
  bool stable = HIGH;
  unsigned long changed = 0;
  unsigned long pressed = 0;
  bool longFired = false;
};
Button nextBtn{BTN_NEXT}, prevBtn{BTN_PREV}, selBtn{BTN_SELECT};
bool evNext = false, evPrev = false, evSel = false, evLong = false;

// ===== KALIBRASI PRESET DELTA RAW VIA PREV (3 MODE) =====
// PREV pertama: tanpa beban/tekanan tambahan. PREV kedua GAS: balon di ukuran
// acuan. PREV mulai hitung mundur 10 s. Pada akhir, ambil median RAW sebagai
// ZERO, lalu gunakan delta RAW dari kalibrasi acuan terdahulu sebagai faktor
// skala. Delta RAW adalah signed: RAW_ACUAN - RAW_KOSONG. PADAT 16 g: preset
// awal +16000 count, dapat diganti lewat RAW16 <nilai>. Preset CAIR/GAS di
// sketch ini memakai tekanan gauge KAL_TEKANAN_KPA. GAS mendahulukan skala
// terkalibrasi yang sudah tersimpan. Menekan NEXT selama hitungan membatalkan
// tanpa mengubah NVS.
const float KAL_MASSA_KG = 0.016f;
const float KAL_TEKANAN_KPA = 1.960f;
const unsigned long KAL_TUNGGU_PRESET_MS = 10000UL;
const unsigned long KAL_TUNGGU_ACUAN_GAS_MS = 3000UL;
const float KAL_ACUAN_GAS_STABIL_KPA = 0.025f;
const unsigned long KAL_USIA_ADC_MS = 1250UL;
const float KAL_MIN_BEDA_RAW = 30.0f;
const float KAL_MAKS_BEDA_RAW = 10000000.0f;
float kalDelta16Raw = 16000.0f;
float kalDeltaCairRaw = NAN; // RAWCAIR <delta> pada acuan KAL_TEKANAN_KPA
float kalDeltaGasRaw = NAN;  // RAWGAS <delta> pada acuan KAL_TEKANAN_KPA
int kalMode = -1;
long kalRawAwal = 0;
float kalDeltaSaatMulai = NAN;
float kalSkalaGasAwal = 0.0f;
float kalVolumeAcuanL = NAN; // valid selama perekaman PREV kedua
unsigned long kalMulaiTunggu = 0;

bool kalDeltaValid(float delta) {
  return isfinite(delta) && fabsf(delta) >= KAL_MIN_BEDA_RAW &&
         fabsf(delta) <= KAL_MAKS_BEDA_RAW;
}
float kalDeltaMode(int m) {
  return m == 0 ? kalDeltaCairRaw : m == 1 ? kalDeltaGasRaw : kalDelta16Raw;
}
float kalAcuanMode(int m) { return m == 2 ? KAL_MASSA_KG : KAL_TEKANAN_KPA; }

void updateButton(Button &b, bool &shortEvent, bool *longEvent = nullptr) {
  unsigned long now = millis();
  bool raw = digitalRead(b.pin);
  if (raw != b.lastRaw)
    b.changed = now;
  if (now - b.changed >= 40 && raw != b.stable) {
    b.stable = raw;
    if (raw == LOW) {
      b.pressed = now;
      b.longFired = false;
    } else if (!b.longFired) {
      shortEvent = true;
    }
  }
  if (longEvent && b.stable == LOW && !b.longFired && now - b.pressed >= 2000) {
    *longEvent = true;
    b.longFired = true;
  }
  b.lastRaw = raw;
}

// ===== SIMPAN PENGATURAN =====
void saveSettings() {
  prefs.putFloat("rho", rho);
  prefs.putFloat("molgas", molGas);
  prefs.putBool("nBase", molFromBaseline);
  prefs.putBool("nManual", gasManualMolActive);
  prefs.putFloat("dBalon", diameterBalonCm);
  prefs.putFloat("gasP0", gasP0KPa);
  prefs.putFloat("gasT0", gasT0K);
  prefs.putFloat("gasV0", gasV0L);
  prefs.putFloat("patmKPa", tekananAtmosferKPa);
  prefs.putUChar("balCt12", balonJumlahTitik);
  for (uint8_t i = 0; i < BALON_MAX_TITIK; ++i) {
    prefs.putFloat((String("bp12_") + i).c_str(), balonPKPa[i]);
    prefs.putFloat((String("bv12_") + i).c_str(), balonVolumeL[i]);
  }
  prefs.putBool("gasAbsV711",
                true); // migrasi: baseline lama dari P gauge tidak berlaku
  prefs.putBool("hxDirectV76", true); // kompatibilitas penanda firmware lama
  prefs.putBool("gasB0OK", gasBaselineValid);
  prefs.putInt("unit", pressureUnit);
  prefs.putLong("zc", zeroCair);
  prefs.putLong("zg", zeroGas);
  prefs.putLong("zl", zeroLoad);
  prefs.putFloat("sc", scaleCair);
  prefs.putFloat("sg", scaleGas);
  prefs.putFloat("sl", scaleLoad);
}
void loadSettings() {
  // Simpan status versi SEBELUM saveSettings() berpotensi dipanggil oleh
  // migrasi lama.
  const bool baselineVersiGauge = !prefs.getBool("gasAbsV711", false);
  rho = prefs.getFloat("rho", 1000);
  molGas = prefs.getFloat("molgas", 0);
  molFromBaseline = prefs.getBool("nBase", false);
  gasManualMolActive = prefs.getBool("nManual", false);
  diameterBalonCm = prefs.getFloat("dBalon", 0);
  gasP0KPa = prefs.getFloat("gasP0", NAN);
  gasT0K = prefs.getFloat("gasT0", NAN);
  gasV0L = prefs.getFloat("gasV0", NAN);
  tekananAtmosferKPa = prefs.getFloat("patmKPa", 101.325f);
  balonJumlahTitik = prefs.getUChar("balCt12", 0);
  if (balonJumlahTitik > BALON_MAX_TITIK)
    balonJumlahTitik = 0;
  for (uint8_t i = 0; i < BALON_MAX_TITIK; ++i) {
    balonPKPa[i] = prefs.getFloat((String("bp12_") + i).c_str(), 0.0f);
    balonVolumeL[i] = prefs.getFloat((String("bv12_") + i).c_str(), 0.0f);
  }
  bool balonKurvaValid =
      balonJumlahTitik == 0 ||
      (isfinite(balonPKPa[0]) && fabsf(balonVolumeL[0]) < 0.00001f);
  for (uint8_t i = 1; i < balonJumlahTitik; ++i) {
    if (!isfinite(balonPKPa[i]) || !isfinite(balonVolumeL[i]) ||
        balonPKPa[i] - balonPKPa[i - 1] < BALON_BEDA_P_MIN_KPA ||
        balonVolumeL[i] <= balonVolumeL[i - 1] || balonVolumeL[i] > 50.0f)
      balonKurvaValid = false;
  }
  if (!balonKurvaValid)
    balonJumlahTitik = 0;
  if (!isfinite(tekananAtmosferKPa) || tekananAtmosferKPa < 50.0f ||
      tekananAtmosferKPa > 120.0f)
    tekananAtmosferKPa = 101.325f;
  gasBaselineValid = prefs.getBool("gasB0OK", false);
  pressureUnit = prefs.getInt("unit", 0);
  zeroCair = prefs.getLong("zc", 0);
  zeroGas = prefs.getLong("zg", 0);
  zeroLoad = prefs.getLong("zl", 0);
  scaleCair = prefs.getFloat("sc", 0);
  scaleGas = prefs.getFloat("sg", 0);
  scaleLoad = prefs.getFloat("sl", 0);
  // Namespace pressure tetap; kunci baru mencegah delta dari acuan lama
  // 1.76 kPa dan 400 count dipakai tanpa sengaja pada V7.30.
  kalDelta16Raw = prefs.getFloat("d16r30", 16000.0f);
  if (!kalDeltaValid(kalDelta16Raw))
    kalDelta16Raw = 16000.0f;
  kalDeltaCairRaw = prefs.getFloat("dcair103", NAN);
  kalDeltaGasRaw = prefs.getFloat("dgas103", NAN);
  if (!kalDeltaValid(kalDeltaCairRaw))
    kalDeltaCairRaw = NAN;
  if (!kalDeltaValid(kalDeltaGasRaw))
    kalDeltaGasRaw = NAN;
  if (!isfinite(rho) || rho < 500 || rho > 2000)
    rho = 1000;
  if (pressureUnit < 0 || pressureUnit > 2)
    pressureUnit = 0;

  if (!isfinite(scaleCair))
    scaleCair = 0;
  if (!isfinite(scaleGas))
    scaleGas = 0;
  if (!isfinite(scaleLoad))
    scaleLoad = 0;
  if (!isfinite(molGas) || molGas <= 0 || molGas > 10) {
    molGas = 0;
    molFromBaseline = false;
    gasManualMolActive = false;
  }
  if (!isfinite(diameterBalonCm) || diameterBalonCm < 0 ||
      diameterBalonCm > 200)
    diameterBalonCm = 0;
  if (!isfinite(gasP0KPa) || gasP0KPa <= 0 || gasP0KPa > 200 ||
      !isfinite(gasT0K) || gasT0K <= 0 || gasT0K > 500 || !isfinite(gasV0L) ||
      gasV0L <= 0 || gasV0L > 1000 || !molFromBaseline || molGas <= 0)
    gasBaselineValid = false;
  // Batalkan baseline model sebelumnya satu kali. Kalibrasi HX710B tetap.
  // Mol manual yang valid dipertahankan; n baseline harus direkam ulang.
  if (!prefs.getBool("hxDirectV76", false)) {
    gasBaselineValid = false;
    molFromBaseline = false;
    gasP0KPa = gasT0K = gasV0L = NAN;
    if (!gasManualMolActive)
      molGas = 0.0f;
    saveSettings();
  }
  // Hapus n hasil GASBASE versi P_gauge; nilainya tidak dapat dipakai untuk
  // P_abs. n MANUAL tetap dipertahankan jika memang diketahui pengguna.
  if (baselineVersiGauge) {
    gasBaselineValid = false;
    molFromBaseline = false;
    gasP0KPa = gasT0K = gasV0L = NAN;
    if (!gasManualMolActive)
      molGas = 0.0f;
    saveSettings();
    Serial.println("MIGRASI GAS: baseline model gauge lama dibatalkan. Rekam "
                   "GASBASE kembali.");
  }
  if (gasBaselineValid)
    gasManualMolActive = false; // Satu sumber n aktif.
}

// ===== DIAGNOSIS I2C (OLED) & DHT22 =====
void scanI2C() {
  Serial.println("\n=== PEMERIKSAAN I2C OLED ===");
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf("I2C terdeteksi: 0x%02X\n", a);
    }
  }
  Serial.println(
      "OLED biasanya 0x3C. DHT22 TIDAK memakai I2C; tidak muncul di SCAN.");
}

void diagnostikDHT() {
  Serial.println("========== DHTDEBUG ==========");
  Serial.printf("DHT22 DATA=GPIO%d | VCC=3V3 | GND=GND | interval=%lu ms\n",
                DHT_PIN, DHT_INTERVAL_MS);
  Serial.print("SENSOR T(C): ");
  if (isfinite(suhuDhtSensorC))
    Serial.println(suhuDhtSensorC, 2);
  else
    Serial.println("--");
  Serial.print("SENSOR T(K): ");
  if (isfinite(suhuDhtSensorC))
    Serial.println(suhuDhtSensorC + 273.15f, 2);
  else
    Serial.println("--");
  Serial.print("FILTER T(K): ");
  if (isfinite(airTempC))
    Serial.println(airTempC + 273.15f, 2);
  else
    Serial.println("--");
  Serial.print("RH (%): ");
  if (isfinite(kelembapanDht))
    Serial.println(kelembapanDht, 2);
  else
    Serial.println("--");
  Serial.printf("Status=%s | gagal berturut=%u | usia data=%lu ms\n",
                dhtOK ? "OK" : "BELUM VALID", (unsigned)dhtGagal,
                waktuDhtValid ? millis() - waktuDhtValid : 0UL);
  Serial.println("Jika masih --, pilih ZAT GAS, cek DATA/pull-up dan beri "
                 "waktu >2,5 dtk.");
}

// ===== HX710B (FORMAT AWAL: 24 BIT + 1 PULSA) =====
// Pastikan jumlah pulsa / channel sesuai datasheet modul HX710B.
bool readHX710(uint8_t dout, uint8_t sck, long &output) {
  if (digitalRead(dout) != LOW)
    return false;
  uint32_t data = 0;
  // Jangan interupsi urutan bit, dan jangan tahan SCK HIGH terlalu lama.
  noInterrupts();
  for (int i = 0; i < 24; ++i) {
    digitalWrite(sck, HIGH);
    delayMicroseconds(1);
    data = (data << 1) | (digitalRead(dout) ? 1U : 0U);
    digitalWrite(sck, LOW);
    delayMicroseconds(1);
  }
  digitalWrite(sck, HIGH);
  delayMicroseconds(1);
  digitalWrite(sck, LOW);
  interrupts();
  if (data & 0x800000UL)
    data |= 0xFF000000UL;
  output = (int32_t)data;
  return true;
}

// Hapus hasil dari mode sebelumnya, supaya OLED tidak menampilkan nilai lama
// ketika pengguna beralih CAIR -> GAS -> PADAT (atau sebaliknya).
void resetModeReadings() {
  filterCair = MedianEma5();
  filterGasHx = MedianEma5();
  filterLoad = MedianEma5();
  filterDhtT = MedianEma5();
  cairOK = gasOK = loadOK = false;
  lastCairOK = lastGasOK = lastLoadOK = 0;
  rawCair = rawGas = rawLoad = 0;
  airTempC = NAN;
  suhuDhtSensorC = NAN;
  kelembapanDht = NAN;
  dhtOK = false;
  dhtGagal = 0;
  waktuDhtValid = 0;
  sonarAktif = 0;
  pingSonarTerakhir = millis();
  for (int i = 0; i < 4; ++i) {
    filterSonar[i] = MedianEma5();
    jarakSonarRaw[i] = NAN;
    jarakSonarHalus[i] = NAN;
    waktuSonar[i] = 0;
  }
  for (int i = 0; i < 3; ++i) {
    tampilKPa[i] = NAN;
    terakhirTampil[i] = 0;
  }
}

// MODE 0 = HX710 cair saja
// MODE 1 = HX710B gas (TEKANAN), DHT22 (SUHU & kelembapan)
// MODE 2 = HX711 load cell + empat HC-SR04 secara bergantian
// Pada HOME sensor tidak dibaca: pengguna memilih mode dulu.
// CATATAN: Sensor tetap tersambung listrik; ini BUKAN GPIO multiplexing.
void readSensorsByMode() {
  if (page == HOME || page == WELCOME)
    return;

  const unsigned long now = millis();
  static unsigned long dhtTick = 0;
  static unsigned long adcTick = 0;

  if (mode == 0) { // ----- ZAT CAIR -----
    if (now - adcTick >= 100UL) {
      adcTick = now;
      long val;
      if (readHX710(CAIR_OUT, CAIR_SCK, val)) {
        rawCair = val;
        filterCair.add((float)val);
        lastCairOK = now;
        cairOK = true;
      }
    }
    if (cairOK && now - lastCairOK > 3000UL)
      cairOK = false;
    return;
  }

  if (mode == 1) { // ----- ZAT GAS -----
    // DHT22 tidak memakai I2C. dht.begin() sudah dipanggil saat setup().
    // readTemperature() dan readHumidity() berbagi sampel internal yang sama.
    if (now - dhtTick >= DHT_INTERVAL_MS) {
      dhtTick = now;
      const float t = dht.readTemperature();
      const float rh = dht.readHumidity();
      if (isfinite(t) && t >= -40.0f && t <= 80.0f) {

        suhuDhtSensorC = t;

        // Koreksi suhu sebesar -5.05 C
        float suhuTerkalibrasi = t + OFFSET_SUHU_C;

        filterDhtT.add(suhuTerkalibrasi, 0.25f);
        airTempC = filterDhtT.value;

        kelembapanDht = (isfinite(rh) && rh >= 0.0f && rh <= 100.0f) ? rh : NAN;
        waktuDhtValid = now;
        dhtGagal = 0;
        dhtOK = true;
      } else {
        if (dhtGagal < 255)
          dhtGagal++;
        Serial.printf(
            "DHT22: pembacaan suhu gagal (%u). Periksa 3V3/DATA GPIO%d/GND.\n",
            (unsigned)dhtGagal, DHT_PIN);
        // Satu pembacaan gagal tidak membuat OLED langsung kembali ke --.
        // Jika tidak ada data segar selama 7,5 dtk, hasil menjadi tidak valid.
        if (waktuDhtValid == 0 || now - waktuDhtValid >= DHT_STALE_MS) {
          suhuDhtSensorC = NAN;
          airTempC = NAN;
          kelembapanDht = NAN;
          filterDhtT = MedianEma5();
          dhtOK = false;
        }
      }
    }
    if (now - adcTick >= 100UL) {
      adcTick = now;
      long val;
      if (readHX710(GAS_OUT, GAS_SCK, val)) {
        rawGas = val;
        filterGasHx.add((float)val);
        lastGasOK = now;
        gasOK = true;
      }
    }
    if (gasOK && now - lastGasOK > 3000UL)
      gasOK = false;
    return;
  }

  if (mode == 2) { // ----- ZAT PADAT -----
    if (now - adcTick >= 100UL) {
      adcTick = now;
      if (loadcell.is_ready()) {
        rawLoad = loadcell.read();
        filterLoad.add((float)rawLoad);
        lastLoadOK = now;
        loadOK = true;
      }
    }
    if (loadOK && now - lastLoadOK > 3000UL)
      loadOK = false;

    // Pembacaan satu sensor setiap >=70 ms, cukup waktu agar gema menghilang.
    // Sensor lain tidak dipicu pada giliran yang sama.
    // Tetap baca saat MANUAL supaya menu Diagnostik US1..US4 bisa digunakan.
    if (now - pingSonarTerakhir >= 70UL) {
      pingSonarTerakhir = now;
      uint8_t i = sonarAktif;
      sonarAktif = (sonarAktif + 1U) % 4U;
      digitalWrite(US_TRIG[i], LOW);
      delayMicroseconds(3);
      digitalWrite(US_TRIG[i], HIGH);
      delayMicroseconds(10);
      digitalWrite(US_TRIG[i], LOW);
      unsigned long durasi = pulseIn(US_ECHO[i], HIGH, 12000UL);
      float cm = durasi ? durasi * 0.0343f / 2.0f : NAN;
      jarakSonarRaw[i] = cm;
      waktuSonar[i] = now;
      if (isfinite(cm) && cm >= 2.0f && cm <= 100.0f) {
        // Perubahan besar: kosong -> ada benda atau sebaliknya.
        // Buang filter lama, jangan campur pantulan objek lama dan baru.
        if (filterSonar[i].ready() && fabsf(cm - filterSonar[i].value) > 1.0f)
          filterSonar[i] = MedianEma5();
        filterSonar[i].add(cm, 0.35f);
        jarakSonarHalus[i] =
            filterSonar[i].ready() ? filterSonar[i].value : NAN;
      } else {
        // Jangan menggunakan data lama kalau benda hilang / sensor timeout.
        filterSonar[i] = MedianEma5();
        jarakSonarHalus[i] = NAN;
      }
    }
  }
}

// ===== HITUNG HASIL =====
// Aturan tampilan hasil: angka yang valid tetapi negatif ditampilkan 0.
// NAN tetap NAN agar sensor yang belum siap tidak dianggap membaca nol.
// RAW sensor, offset, dan skala kalibrasi tetap menyimpan nilai asli.
// CATATAN: pembacaan negatif yang nyata (mis. tekanan gauge vakum)
// juga akan menjadi nol pada hasil; gunakan RAW untuk diagnosis.
float hasilMinimalNol(float nilai) {
  if (!isfinite(nilai))
    return NAN;
  return nilai > 0.0f ? nilai : 0.0f;
}

float liquidKPa() {
  if (!cairOK || !filterCair.ready() || scaleCair == 0.0f)
    return NAN;
  const float p = (filterCair.value - zeroCair) * scaleCair;
  return hasilMinimalNol(p);
}

float gasKPa() {
  if (!gasOK || !filterGasHx.ready() || scaleGas == 0.0f)
    return NAN;
  const float p = (filterGasHx.value - zeroGas) * scaleGas;
  return hasilMinimalNol(p); // hanya untuk tampilan nonnegatif (gauge)
}

// Tekanan signed hanya untuk pemetaan kalibrasi balon dan perhitungan P
// absolut. Tidak mengubah angka tekanan yang ditampilkan di OLED.
float gasGaugeSignedKPa() {
  if (!gasOK || !filterGasHx.ready() || scaleGas == 0.0f)
    return NAN;
  return (filterGasHx.value - zeroGas) * scaleGas;
}

// Tekanan untuk rumus gas ideal harus absolut. Jangan gunakan gasKPa()
// karena gasKPa() sengaja membuang nilai gauge negatif saat ditampilkan.
float gasPAbsKPa() {
  if (!gasOK || !filterGasHx.ready() || scaleGas == 0.0f)
    return NAN;
  const float pGaugeAsli = gasGaugeSignedKPa();
  const float pAbs = tekananAtmosferKPa + pGaugeAsli;
  return (isfinite(pAbs) && pAbs > 0.0f) ? pAbs : NAN;
}

float forceN() {
  if (!loadOK || !filterLoad.ready() || scaleLoad == 0.0f)
    return NAN;
  const float f = (filterLoad.value - zeroLoad) * scaleLoad * G;
  return hasilMinimalNol(f);
}

String pressureText(float pa) {
  if (!isfinite(pa))
    return "--";
  pa = hasilMinimalNol(pa);
  if (pressureUnit == 0)
    return String(pa / 1000.0f, 2) + " kPa";
  if (pressureUnit == 1)
    return String(pa, 0) + " Pa";
  return String(pa / 100000.0f, 4) + " bar";
}

// Diameter D0 adalah acuan yang diukur pengguna. Pendekatan balon hampir bulat.
float volumeBalonL() {
  if (!isfinite(diameterBalonCm) || diameterBalonCm <= 0)
    return NAN;
  float r = diameterBalonCm * 0.005f; // jari-jari dalam meter
  return (4.0f / 3.0f) * PI * r * r * r * 1000.0f;
}
// Validasi mol acuan diagnostik, terpisah dari hasil kurva saat ini.
bool gasMolesReady() {
  return (gasBaselineValid || gasManualMolActive) && isfinite(molGas) &&
         molGas > 0.0f && molGas <= 10.0f;
}

// Reset khusus kurva volume balon. Tidak menghapus n, HX710B, cair, padat.
void balonHapusKurva() {
  balonJumlahTitik = 0;
  for (uint8_t i = 0; i < BALON_MAX_TITIK; ++i) {
    balonPKPa[i] = 0;
    balonVolumeL[i] = 0;
  }
}

// Ambil titik nol saat balon belum mengembang. Harus dipanggil saat GAS aktif.
bool balonRekamNol() {
  float p = gasGaugeSignedKPa();
  if (!isfinite(p))
    return false;
  balonHapusKurva();
  balonPKPa[0] = p;
  balonVolumeL[0] = 0.0f;
  balonJumlahTitik = 1;
  saveSettings();
  return true;
}

// Menambahkan volume balon yang benar-benar DIUKUR pada tekanan saat itu.
// Kurva harus naik monoton terhadap P; jika tidak, P saja tidak dapat
// dipakai untuk menebak V secara tunggal pada balon tersebut.
bool balonRekamTitik(float volumeL) {
  const float p = gasGaugeSignedKPa();
  if (!isfinite(p) || !isfinite(volumeL) || volumeL <= 0.0f ||
      volumeL > 50.0f || balonJumlahTitik == 0 ||
      balonJumlahTitik >= BALON_MAX_TITIK)
    return false;
  int pos = 0;
  while (pos < balonJumlahTitik && balonPKPa[pos] < p)
    ++pos;
  if ((pos > 0 && p - balonPKPa[pos - 1] < BALON_BEDA_P_MIN_KPA) ||
      (pos < balonJumlahTitik && balonPKPa[pos] - p < BALON_BEDA_P_MIN_KPA))
    return false;
  // Volume harus meningkat bersama tekanan pada setiap segmen kalibrasi.
  if ((pos > 0 && volumeL <= balonVolumeL[pos - 1]) ||
      (pos < balonJumlahTitik && volumeL >= balonVolumeL[pos]))
    return false;
  for (int i = (int)balonJumlahTitik; i > pos; --i) {
    balonPKPa[i] = balonPKPa[i - 1];
    balonVolumeL[i] = balonVolumeL[i - 1];
  }
  balonPKPa[pos] = p;
  balonVolumeL[pos] = volumeL;
  ++balonJumlahTitik;
  saveSettings();
  return true;
}

// NILAI V UNTUK OLED: hasil interpolasi P-V volume BALON saja.
// Tidak mengubah satupun perintah gambar OLED.
// Nilai di luar rentang kalibrasi -> NAN (OLED '--'), bukan ekstrapolasi palsu.
float volumeGasDinamisL() {
  const float p = gasGaugeSignedKPa();
  if (!isfinite(p) || balonJumlahTitik == 0)
    return NAN;
  if (p <= balonPKPa[0] + BALON_BEDA_P_MIN_KPA)
    return 0.0f;
  if (balonJumlahTitik < 2)
    return NAN;
  const uint8_t last = balonJumlahTitik - 1;
  // Toleransi untuk variasi kecil tepat di titik kalibrasi maksimum.
  if (p > balonPKPa[last] + BALON_BEDA_P_MIN_KPA)
    return NAN;
  if (p >= balonPKPa[last])
    return balonVolumeL[last];
  for (uint8_t i = 1; i < balonJumlahTitik; ++i) {
    if (p <= balonPKPa[i]) {
      float t = (p - balonPKPa[i - 1]) / (balonPKPa[i] - balonPKPa[i - 1]);
      float v =
          balonVolumeL[i - 1] + t * (balonVolumeL[i] - balonVolumeL[i - 1]);
      return isfinite(v) && v >= 0.0f ? v : NAN;
    }
  }
  return NAN;
}
// n = Pabs * V / (R * T). Satuan internal kPa * L = Pa * m3 = J.
float gasMolDariPVT(float pAbsKPa, float volumeL, float suhuK) {
  if (!isfinite(pAbsKPa) || pAbsKPa <= 0.0f || !isfinite(volumeL) ||
      volumeL < 0.0f || !isfinite(suhuK) || suhuK <= 0.0f)
    return NAN;
  const float n = (pAbsKPa * volumeL) / (R_GAS * suhuK);
  return isfinite(n) ? n : NAN;
}

float gasMolDariKurva() {
  return gasMolDariPVT(gasPAbsKPa(), volumeGasDinamisL(), airTempC + 273.15f);
}

// Reset total termasuk mol manual, misalnya setelah balon dibuka/diisi lagi.
void clearGasBaseline() {
  gasBaselineValid = false;
  gasManualMolActive = false;
  gasP0KPa = gasT0K = gasV0L = NAN;
  molGas = 0;
  molFromBaseline = false;
}
// Memasang n yang telah DIKETAHUI untuk sampel gas tertutup.
bool setGasManualMoles(float n) {
  if (!isfinite(n) || n <= 0.0f || n > 10.0f)
    return false;
  clearGasBaseline();
  molGas = n;
  gasManualMolActive = true;
  saveSettings();
  return true;
}
// Estimasi n dari Pabs0, T0, V0 awal (balon tertutup; perkiraan bentuk bola).
// Jika balon diisi/dikempiskan sesudah baseline, n perlu diatur ulang.
bool captureInitialMoles() {
  float p0 = gasPAbsKPa();
  float t0 = airTempC + 273.15f;
  float v0 = volumeBalonL();
  const float n0 = gasMolDariPVT(p0, v0, t0);
  if (!isfinite(n0) || n0 <= 0 || n0 > 10)
    return false;
  gasP0KPa = p0;
  gasT0K = t0;
  gasV0L = v0;
  molGas = n0;
  molFromBaseline = true;
  gasManualMolActive = false;
  gasBaselineValid = true;
  saveSettings();
  return true;
}
// ===== PROFIL BENDA HYBRID: 4 HC-SR04 + MASSA HX711 =====
// Semua jarak harus dibaca pada POSISI dan ORIENTASI benda yang sama.
// Format NVS "prof3_us" kompatibel dengan sketch mandiri 3/10 profil
// sebelumnya. Tidak ada klaim bahwa jarak yang stabil adalah jarak fisik yang
// akurat.
const uint8_t PROF_JUMLAH = 10;
const float PROF_LUAS_MAKS = 78.54f; // platform kontak bundar diameter 10 cm
const float PROF_STABIL_MAX = 0.50f; // rentang 5 echo mentah (cm)
const float PROF_DETEKSI_BENDA =
    0.70f; // minimal SATU sensor berubah >=0.70 cm terhadap EMPTY
// Toleransi pengenalan jarak setiap sensor
const float PROF_TOLERANSI_CM = 0.9f;
const float HYB_REF_KIRI_KANAN_CM = 12.0f;
const float HYB_REF_ATAS_BAWAH_CM = 12.0f;
const float HYB_SELISIH_LUAS_MAX =
    0.10f; // relatif <=10%: geometri dapat dipakai
const float HYB_TOL_MASSA_PERSEN = 0.08f; // +/-8% massa referensi
const float HYB_TOL_MASSA_MIN_G = 1.5f;   // atau +/-1,5 g (mana lebih besar)
const float HYB_MASSA_MIN_G = 2.0f;
const float HYB_MASSA_MAX_G = 1000.0f; // load cell nominal 1 kg

// Minimum pemisahan dua profil
const float PROF_MIN_PISAH = 2.0f * PROF_TOLERANSI_CM + 0.05f;
// Jika profil lama saling tumpang tindih, keputusan AMBIGU dan luas tidak
// digunakan.
const unsigned long PROF_USIA_MS = 1300UL;

struct ProfilBenda {
  bool learned = false;
  String nama;
  float luas = NAN;
  float massaGram = NAN; // profil lama tanpa massa wajib LEARN ulang
  float jarak[4] = {NAN, NAN, NAN, NAN};
};
ProfilBenda profilBenda[PROF_JUMLAH];
float profilKosong[4] = {NAN, NAN, NAN, NAN};
bool profilKosongOK = false;
bool profilAktif = true; // selalu aktif; tidak memakai mode OFF/manual/geometri
int profilKandidat = -1;
int profilStreak = 0;
int profilDipilih = -1;
float profilAreaCache = NAN;
const char *profilStatus = "PROFIL BELUM AKTIF";
float hybridAreaGeometriCm2 = NAN;
float hybridPanjangCm = NAN;
float hybridLebarCm = NAN;
const char *hybridSumberLuas = "--";
unsigned long profilTerakhirEvaluasi = 0;

String profilKey(const char *awalan, uint8_t idx) {
  return String(awalan) + String((unsigned int)idx);
}
String profilKeyJarak(uint8_t idx, uint8_t sensor) {
  return String("d") + String((unsigned int)idx) + String((unsigned int)sensor);
}
void profilResetTracking() {
  profilKandidat = -1;
  profilStreak = 0;
  profilDipilih = -1;
  profilAreaCache = NAN;
  profilTerakhirEvaluasi = 0;
  hybridSumberLuas = "--";
}
void profilResetSlot(uint8_t idx) {
  profilBenda[idx].learned = false;
  profilBenda[idx].luas = NAN;
  profilBenda[idx].massaGram = NAN;
  for (uint8_t j = 0; j < 4; j++)
    profilBenda[idx].jarak[j] = NAN;
}
// Bentuk penyimpanan tunggal (blob) membuat satu profil tersimpan atomik.
// Nama tetap di key "nameN" agar kompatibel dengan profil versi sebelumnya.
// Semua key lama (okN/areaN/dNN) tidak dihapus dan dipakai sebagai fallback.
struct ProfilDiskV2 {
  uint32_t magic;
  float luas;
  float jarak[4];
  uint32_t cek;
};
static const uint32_t PROF_DISK_MAGIC = 0x50524632UL; // "PRF2"
// Record tambahan terikat checksum PRF2. Blob lama tetap kompatibel/tidak
// ditimpa.
struct ProfilMassaDisk {
  uint32_t magic;
  float massaGram;
  uint32_t signatureProfil;
  uint32_t cek;
};
static const uint32_t PROF_MASS_MAGIC = 0x48594D31UL; // HYM1
String profilKeyMass(uint8_t idx) {
  return String("hm") + String((unsigned)idx);
}

String profilKeyBlob(uint8_t idx) {
  return String("pf") + String((unsigned int)idx);
}
// Parameter bertipe dasar agar Arduino IDE tidak membuat prototipe otomatis
// yang merujuk struct ProfilDiskV2 sebelum deklarasinya.
uint32_t profilHitungCek(const void *data, size_t panjang) {
  // FNV-1a untuk mendeteksi data terpotong/rusak, bukan untuk keamanan.
  uint32_t h = 2166136261UL;
  const uint8_t *bytes = reinterpret_cast<const uint8_t *>(data);
  for (size_t i = 0; i < panjang; ++i) {
    h ^= bytes[i];
    h *= 16777619UL;
  }
  return h;
}
bool profilDiskValid(uint32_t magic, float luas, const float jarak[4],
                     uint32_t cek, const void *data, size_t panjang) {
  if (magic != PROF_DISK_MAGIC || cek != profilHitungCek(data, panjang))
    return false;
  if (!isfinite(luas) || luas <= 0.0f || luas > PROF_LUAS_MAKS)
    return false;
  for (uint8_t i = 0; i < 4; i++)
    if (!isfinite(jarak[i]) || jarak[i] < 2.0f || jarak[i] > 100.0f)
      return false;
  return true;
}
float hybridMassaSaatIniGram() {
  if (!loadOK || !filterLoad.ready() || millis() - lastLoadOK > 1250UL ||
      scaleLoad == 0.0f)
    return NAN;
  const float g = forceN() / G * 1000.0f;
  if (!isfinite(g) || g < HYB_MASSA_MIN_G || g > HYB_MASSA_MAX_G)
    return NAN;
  float minimum = filterLoad.buf[0], maksimum = minimum;
  for (uint8_t i = 1; i < 5; i++) {
    minimum = min(minimum, filterLoad.buf[i]);
    maksimum = max(maksimum, filterLoad.buf[i]);
  }
  const float sebaranGram = (maksimum - minimum) * fabsf(scaleLoad) * 1000.0f;
  // Tolak penimbangan bergerak sebelum identifikasi/LEARN.
  if (sebaranGram > max(1.0f, g * 0.03f))
    return NAN;
  return g;
}
bool profilMassaValid(uint32_t magic, float massaGram, uint32_t signatureProfil,
                      uint32_t cek, const void *isi, size_t panjang,
                      uint32_t signatureSeharusnya) {
  return magic == PROF_MASS_MAGIC && signatureProfil == signatureSeharusnya &&
         isfinite(massaGram) && massaGram >= HYB_MASSA_MIN_G &&
         massaGram <= HYB_MASSA_MAX_G && cek == profilHitungCek(isi, panjang);
}
bool profilBacaMassa(uint8_t idx, uint32_t signature, float &massa) {
  massa = NAN;
  if (!profilNvsSiap)
    return false;
  const String key = profilKeyMass(idx);
  if (prefsProfil.getBytesLength(key.c_str()) != sizeof(ProfilMassaDisk))
    return false;
  ProfilMassaDisk d = {};
  if (prefsProfil.getBytes(key.c_str(), &d, sizeof(d)) != sizeof(d) ||
      !profilMassaValid(d.magic, d.massaGram, d.signatureProfil, d.cek, &d,
                        sizeof(d) - sizeof(d.cek), signature))
    return false;
  massa = d.massaGram;
  return true;
}
bool profilSimpanMassa(uint8_t idx, uint32_t signature, float massa) {
  ProfilMassaDisk d = {};
  d.magic = PROF_MASS_MAGIC;
  d.massaGram = massa;
  d.signatureProfil = signature;
  d.cek = profilHitungCek(&d, sizeof(d) - sizeof(d.cek));
  if (!profilMassaValid(d.magic, d.massaGram, d.signatureProfil, d.cek, &d,
                        sizeof(d) - sizeof(d.cek), signature))
    return false;
  const String key = profilKeyMass(idx);
  if (prefsProfil.putBytes(key.c_str(), &d, sizeof(d)) != sizeof(d))
    return false;
  float uji = NAN;
  return profilBacaMassa(idx, signature, uji) && fabsf(uji - massa) < 0.001f;
}
bool profilBacaBlob(uint8_t idx, void *buffer, size_t ukuran) {
  if (!profilNvsSiap)
    return false;
  const String key = profilKeyBlob(idx);
  if (prefsProfil.getBytesLength(key.c_str()) != ukuran)
    return false;
  return prefsProfil.getBytes(key.c_str(), buffer, ukuran) == ukuran;
}
bool profilSaveSlot(uint8_t idx) {
  if (!profilNvsSiap || idx >= PROF_JUMLAH) {
    Serial.println("NVS GAGAL: namespace prof3_us tidak dapat dibuka.");
    return false;
  }
  const ProfilBenda &p = profilBenda[idx];
  const String blob = profilKeyBlob(idx);
  if (!p.learned) {
    // CLEAR/EMPTY harus menghapus blob dan mematikan key format lama.
    const String massKey = profilKeyMass(idx);
    if (prefsProfil.getBytesLength(massKey.c_str()) > 0 &&
        !prefsProfil.remove(massKey.c_str()))
      return false;
    if (prefsProfil.getBytesLength(blob.c_str()) > 0 &&
        !prefsProfil.remove(blob.c_str())) {
      Serial.printf("NVS GAGAL: tidak dapat menghapus profil %u.\n",
                    (unsigned)(idx + 1));
      return false;
    }
    const String key = profilKey("ok", idx);
    if (prefsProfil.putBool(key.c_str(), false) != sizeof(bool) ||
        prefsProfil.getBool(key.c_str(), true)) {
      Serial.printf("NVS GAGAL: CLEAR profil %u tidak tersimpan.\n",
                    (unsigned)(idx + 1));
      return false;
    }
    return true;
  }
  ProfilDiskV2 data = {};
  data.magic = PROF_DISK_MAGIC;
  data.luas = p.luas;
  for (uint8_t i = 0; i < 4; i++)
    data.jarak[i] = p.jarak[i];
  data.cek = profilHitungCek(&data, sizeof(data) - sizeof(data.cek));
  if (!profilDiskValid(data.magic, data.luas, data.jarak, data.cek, &data,
                       sizeof(data) - sizeof(data.cek))) {
    Serial.printf("NVS GAGAL: isi profil %u tidak valid.\n",
                  (unsigned)(idx + 1));
    return false;
  }
  // Tulis langsung melalui API NVS agar kode error asli dapat diketahui.
  // Ini tetap memakai namespace prof3_us dan struktur record V7.19 yang sama.
  // Tidak ada operasi hapus otomatis atau migrasi destruktif.
  nvs_handle_t handleNVS;
  esp_err_t errorNVS = nvs_open("prof3_us", NVS_READWRITE, &handleNVS);
  if (errorNVS == ESP_OK) {
    errorNVS = nvs_set_blob(handleNVS, blob.c_str(), &data, sizeof(data));
    if (errorNVS == ESP_OK)
      errorNVS = nvs_commit(handleNVS);
    nvs_close(handleNVS);
  }
  const size_t tertulis = (errorNVS == ESP_OK) ? sizeof(data) : 0U;
  ProfilDiskV2 baca = {};
  const bool valid =
      tertulis == sizeof(data) && profilBacaBlob(idx, &baca, sizeof(baca)) &&
      profilDiskValid(baca.magic, baca.luas, baca.jarak, baca.cek, &baca,
                      sizeof(baca) - sizeof(baca.cek)) &&
      fabsf(baca.luas - data.luas) < 0.0001f && baca.cek == data.cek;
  if (!valid) {
    Serial.printf("NVS GAGAL: profil %u, Tertulis=%u/%u byte, "
                  "kode=%s (0x%X)\n",
                  (unsigned)(idx + 1), (unsigned)tertulis,
                  (unsigned)sizeof(data), esp_err_to_name(errorNVS),
                  (unsigned)errorNVS);
    if (errorNVS == ESP_ERR_NVS_NOT_ENOUGH_SPACE) {
      Serial.println("PENYEBAB: NVS tidak punya ruang untuk record baru. "
                     "Simpan LIST/NVSDEBUG sebelum hapus data.");
    } else if (errorNVS == ESP_ERR_NVS_TYPE_MISMATCH) {
      Serial.println("PENYEBAB: tipe key NVS berbenturan. Jangan CLEAR ALL "
                     "sebelum backup.");
    } else if (errorNVS == ESP_OK) {
      Serial.println("PENYEBAB: penulisan OK tetapi verifikasi baca tidak "
                     "cocok. Cek data/NVSDEBUG.");
    }
  }
  if (!valid)
    return false;
  if (!profilSimpanMassa(idx, data.cek, p.massaGram)) {
    Serial.printf("NVS GAGAL: massa profil %u tidak tersimpan; profil tidak "
                  "bisa aktif hybrid.\n",
                  (unsigned)(idx + 1));
    return false;
  }
  return true;
}
void profilLoad() {
  if (!profilNvsSiap) {
    Serial.println("PROFIL: NVS tidak siap; data LEARN tidak bisa diakses.");
    profilKosongOK = false;
    for (uint8_t p = 0; p < PROF_JUMLAH; p++) {
      profilBenda[p].nama = String("BENDA_") + String((unsigned)(p + 1));
      profilResetSlot(p);
    }
    profilAktif = true;
    profilResetTracking();
    return;
  }
  profilKosongOK = prefsProfil.getBool("emptyOK", false);
  for (uint8_t i = 0; i < 4; i++) {
    const String key = profilKey("empty", i);
    profilKosong[i] = prefsProfil.getFloat(key.c_str(), NAN);
    if (!isfinite(profilKosong[i]) || profilKosong[i] < 2 ||
        profilKosong[i] > 100)
      profilKosongOK = false;
  }
  for (uint8_t i = 0; i < PROF_JUMLAH; i++) {
    ProfilBenda &p = profilBenda[i];
    const String namaKey = profilKey("name", i);
    p.nama = prefsProfil.getString(
        namaKey.c_str(), String("BENDA_") + String((unsigned)(i + 1)));
    p.learned = false;
    p.luas = NAN;
    p.massaGram = NAN;
    for (uint8_t j = 0; j < 4; j++)
      p.jarak[j] = NAN;
    ProfilDiskV2 disk = {};
    if (profilBacaBlob(i, &disk, sizeof(disk)) &&
        profilDiskValid(disk.magic, disk.luas, disk.jarak, disk.cek, &disk,
                        sizeof(disk) - sizeof(disk.cek))) {
      p.learned = true;
      p.luas = disk.luas;
      for (uint8_t j = 0; j < 4; j++)
        p.jarak[j] = disk.jarak[j];
      profilBacaMassa(i, disk.cek, p.massaGram);
      continue;
    }
    // Mencoba format lama tanpa menghapus/memodifikasi data lama.
    const String okKey = profilKey("ok", i);
    const bool oldOK = prefsProfil.getBool(okKey.c_str(), false);
    if (!oldOK)
      continue;
    const String areaKey = profilKey("area", i);
    float a = prefsProfil.getFloat(areaKey.c_str(), NAN);
    bool valid = isfinite(a) && a > 0.0f && a <= PROF_LUAS_MAKS;
    float d[4];
    for (uint8_t j = 0; j < 4; j++) {
      const String key = profilKeyJarak(i, j);
      d[j] = prefsProfil.getFloat(key.c_str(), NAN);
      if (!isfinite(d[j]) || d[j] < 2.0f || d[j] > 100.0f)
        valid = false;
    }
    if (valid) {
      p.learned = true;
      p.luas = a;
      for (uint8_t j = 0; j < 4; j++)
        p.jarak[j] = d[j];
      Serial.printf("NVS: PROFIL %u pulih dari format lama.\n",
                    (unsigned)(i + 1));
    } else {
      Serial.printf(
          "NVS: PROFIL %u format lama tidak lengkap/valid. Gunakan NVSDEBUG.\n",
          (unsigned)(i + 1));
    }
  }
  profilAktif = true;
  profilResetTracking();
  if (!profilKosongOK)
    Serial.println("NVS: baseline EMPTY tidak valid/belum tersimpan.");
}
void profilNvsDebug() {
  Serial.println("========== NVSDEBUG ========== ");
  nvs_stats_t statistikNVS = {};
  const esp_err_t kodeStat = nvs_get_stats(NULL, &statistikNVS);
  if (kodeStat == ESP_OK) {
    Serial.printf("NVS STATS: total=%u | terpakai=%u | bebas=%u | "
                  "tersedia=%u | namespace=%u (entries)\n",
                  (unsigned)statistikNVS.total_entries,
                  (unsigned)statistikNVS.used_entries,
                  (unsigned)statistikNVS.free_entries,
                  (unsigned)statistikNVS.available_entries,
                  (unsigned)statistikNVS.namespace_count);
  } else {
    Serial.printf("NVS STATS GAGAL: %s (0x%X)\n", esp_err_to_name(kodeStat),
                  (unsigned)kodeStat);
  }
  Serial.printf("Namespace prof3_us=%s | EMPTY=%s\n",
                profilNvsSiap ? "OK" : "GAGAL",
                profilKosongOK ? "ADA" : "BELUM / TIDAK VALID");
  if (!profilNvsSiap)
    return;
  Serial.printf("NVS emptyOK=%d\n",
                prefsProfil.getBool("emptyOK", false) ? 1 : 0);
  for (uint8_t j = 0; j < 4; j++) {
    const String k = profilKey("empty", j);
    Serial.printf("EMPTY US%u=%.3f cm\n", (unsigned)(j + 1),
                  prefsProfil.getFloat(k.c_str(), NAN));
  }
  for (uint8_t i = 0; i < PROF_JUMLAH; i++) {
    const String bk = profilKeyBlob(i);
    const String ok = profilKey("ok", i);
    const String ar = profilKey("area", i);
    ProfilDiskV2 data = {};
    const size_t len = prefsProfil.getBytesLength(bk.c_str());
    const bool blobOK =
        profilBacaBlob(i, &data, sizeof(data)) &&
        profilDiskValid(data.magic, data.luas, data.jarak, data.cek, &data,
                        sizeof(data) - sizeof(data.cek));
    Serial.printf(
        "PROFIL %u | RAM=%s | BLOB=%u byte (%s) | LAMA ok=%d area=%.3f | "
        "NAMA=%s\n",
        (unsigned)(i + 1), profilBenda[i].learned ? "LEARN" : "BELUM LEARN",
        (unsigned)len, blobOK ? "VALID" : "BELUM/INVALID",
        prefsProfil.getBool(ok.c_str(), false) ? 1 : 0,
        prefsProfil.getFloat(ar.c_str(), NAN), profilBenda[i].nama.c_str());
    if (i == 0 || profilBenda[i].learned ||
        prefsProfil.getBool(ok.c_str(), false)) {
      Serial.print("  LEGACY JARAK: ");
      for (uint8_t j = 0; j < 4; j++) {
        const String k = profilKeyJarak(i, j);
        if (j)
          Serial.print(" / ");
        Serial.print(prefsProfil.getFloat(k.c_str(), NAN), 2);
      }
      Serial.println();
    }
  }
  Serial.println("Jangan EMPTY/CLEAR sebelum menyimpan hasil diagnostik.");
}

// Ambil empat JARAK TERFILTER, bukan REF/dimensi/geometri.
// Rentang raw memastikan EMA tidak menyembunyikan pantulan tidak stabil.
bool profilSnapshot(float hasil[4], String &sebab) {
  if (mode != 2 || page == WELCOME || page == HOME) {
    sebab = "PILIH MODE ZAT PADAT";
    return false;
  }
  for (uint8_t i = 0; i < 4; i++) {
    if (millis() - waktuSonar[i] > PROF_USIA_MS ||
        !isfinite(jarakSonarRaw[i]) || !filterSonar[i].ready() ||
        !isfinite(jarakSonarHalus[i])) {
      sebab = String("US") + String((unsigned int)(i + 1)) +
              " TIDAK SIAP / ECHO HILANG";
      return false;
    }
    float lo = filterSonar[i].buf[0], hi = lo;
    for (uint8_t j = 1; j < 5; j++) {
      lo = min(lo, filterSonar[i].buf[j]);
      hi = max(hi, filterSonar[i].buf[j]);
    }
    if (hi - lo > PROF_STABIL_MAX) {
      sebab = String("US") + String((unsigned int)(i + 1)) + " TIDAK STABIL";
      return false;
    }
    hasil[i] = jarakSonarHalus[i];
    if (hasil[i] < 2 || hasil[i] > 100) {
      sebab = "JARAK DI LUAR 2..100 CM";
      return false;
    }
  }
  sebab = "OK";
  return true;
}
uint8_t profilEvidence(const float d[4]) {
  uint8_t n = 0;
  if (!profilKosongOK)
    return 0;
  for (uint8_t i = 0; i < 4; i++)
    if (profilKosong[i] - d[i] >= PROF_DETEKSI_BENDA)
      n++;
  return n;
}
// Periksa toleransi +/-1.00 cm pada SETIAP sensor, tidak memakai rata-rata
// untuk kelulusan. Semua sensor harus punya echo valid dari profilSnapshot()
// sebelum fungsi ini dipanggil.
bool profilSesuaiToleransi(const float d[4], uint8_t idx, float &rataBeda) {
  rataBeda = NAN;
  if (idx >= PROF_JUMLAH || !profilBenda[idx].learned)
    return false;
  // Kedua identitas wajib cocok: HX711 DAN semua empat pembacaan sonar.
  const float massa = hybridMassaSaatIniGram();
  const float ref = profilBenda[idx].massaGram;
  if (!isfinite(massa) || !isfinite(ref) ||
      fabsf(massa - ref) > max(HYB_TOL_MASSA_MIN_G, ref * HYB_TOL_MASSA_PERSEN))
    return false;
  float jumlah = 0.0f;
  for (uint8_t i = 0; i < 4; i++) {
    const float selisih = fabsf(d[i] - profilBenda[idx].jarak[i]);
    if (!isfinite(selisih) || selisih > PROF_TOLERANSI_CM)
      return false;
    jumlah += selisih;
  }
  rataBeda = jumlah / 4.0f;
  return true;
}
// -1 tidak dikenal / di luar toleransi, -2 ambigu, -3 kosong, -4 belum EMPTY.
int profilKenali(const float d[4], float &bedaRata) {
  bedaRata = NAN;
  if (!profilKosongOK)
    return -4;
  // Tetap wajib berbeda terhadap kondisi EMPTY (minimal 1 sensor 0.70cm).
  // Benda kecil dengan hanya SATU sensor merespons kini tetap bisa dipelajari.
  if (profilEvidence(d) < 1)
    return -3;
  int cocok = 0, terbaik = -1;
  float best = INFINITY;
  for (uint8_t p = 0; p < PROF_JUMLAH; p++) {
    float mean = NAN;
    if (profilSesuaiToleransi(d, p, mean)) {
      cocok++;
      if (mean < best) {
        best = mean;
        terbaik = p;
      }
    }
  }
  // Jangan memilih profil acak jika dua kotak toleransi saling tumpang tindih.
  if (cocok > 1)
    return -2;
  if (cocok == 1) {
    bedaRata = best;
    return terbaik;
  }
  return -1;
}
void profilEvaluasi() {
  if (!profilAktif) {
    profilResetTracking();
    profilStatus = "PROFIL OFF";
    return;
  }
  unsigned long now = millis();
  if (profilTerakhirEvaluasi && now - profilTerakhirEvaluasi < 450UL)
    return;
  profilTerakhirEvaluasi = now;
  float d[4];
  String sebab;
  if (!profilSnapshot(d, sebab)) {
    profilResetTracking();
    profilStatus = "SENSOR TIDAK STABIL/SIAP";
    return;
  }
  float e = NAN;
  int id = profilKenali(d, e);
  if (id < 0) {
    profilResetTracking();
    profilStatus = id == -4   ? "BELUM EMPTY"
                   : id == -3 ? "KOSONG/TIDAK TERDETEKSI"
                   : id == -2 ? "AMBIGU (DUA PROFIL)"
                              : "TIDAK DIKENAL";
    return;
  }
  if (profilKandidat != id) {
    profilKandidat = id;
    profilStreak = 1;
  } else if (profilStreak < 3)
    profilStreak++;
  if (profilStreak < 3) {
    profilDipilih = -1;
    profilAreaCache = NAN;
    profilStatus = "MENUNGGU 3 PEMERIKSAAN COCOK";
  } else {
    profilDipilih = id;
    profilAreaCache = profilBenda[id].luas;
    profilStatus = "PROFIL DIKENALI";
  }
}
float profilLuasAktif() {
  profilEvaluasi();
  if (profilDipilih < 0 || !isfinite(profilAreaCache))
    return NAN;
  // Pemeriksaan ULANG setiap permintaan luas: jangan pertahankan hasil terakhir
  // selama jeda evaluasi 450 ms jika salah satu sensor keluar dari +/-1.00 cm.
  float sekarang[4];
  String sebab;
  if (!profilSnapshot(sekarang, sebab)) {
    profilResetTracking();
    profilStatus = "ECHO HILANG / TIDAK STABIL";
    return NAN;
  }
  float beda = NAN;
  if (profilKenali(sekarang, beda) != profilDipilih) {
    profilResetTracking();
    profilStatus = "DI LUAR TOLERANSI / KOSONG / AMBIGU";
    return NAN;
  }
  // Metode geometri dipertahankan. Bila menyimpang dari luas profil,
  // jangan memalsukan offset HC-SR04: gunakan luas benda yang telah dikenal.
  const float p = HYB_REF_KIRI_KANAN_CM - (sekarang[0] + sekarang[1]);
  const float l = HYB_REF_ATAS_BAWAH_CM - (sekarang[2] + sekarang[3]);
  hybridPanjangCm = p;
  hybridLebarCm = l;
  hybridAreaGeometriCm2 =
      (isfinite(p) && isfinite(l) && p > 0 && l > 0 &&
       p <= HYB_REF_KIRI_KANAN_CM && l <= HYB_REF_ATAS_BAWAH_CM &&
       p * l <= PROF_LUAS_MAKS)
          ? p * l
          : NAN;
  const float luasProfil = profilAreaCache;
  if (isfinite(hybridAreaGeometriCm2) &&
      fabsf(hybridAreaGeometriCm2 - luasProfil) / luasProfil <=
          HYB_SELISIH_LUAS_MAX) {
    hybridSumberLuas = "US OK";
    profilStatus = "HYBRID: GEOMETRI OK";
    return hybridAreaGeometriCm2;
  }
  hybridSumberLuas = "PROFIL";
  profilStatus = "HYBRID: KOREKSI PROFIL";
  return luasProfil;
}
void profilList() {
  Serial.printf(
      "PROFIL: %s | EMPTY: %s | NVS: %s\n", profilAktif ? "ON" : "OFF",
      profilKosongOK ? "ADA" : "BELUM ADA", profilNvsSiap ? "OK" : "ERROR");
  if (profilKosongOK) {
    Serial.print("EMPTY US1..4 (cm): ");
    for (uint8_t i = 0; i < 4; i++) {
      if (i)
        Serial.print(" / ");
      Serial.print(profilKosong[i], 2);
    }
    Serial.println();
  }
  for (uint8_t p = 0; p < PROF_JUMLAH; p++) {
    Serial.printf("%u. %s | ", (unsigned int)(p + 1),
                  profilBenda[p].nama.c_str());
    if (!profilBenda[p].learned) {
      Serial.println("BELUM LEARN");
      continue;
    }
    Serial.printf("LUAS=%.3f cm2 | MASSA=%.2f g | POLA=", profilBenda[p].luas,
                  profilBenda[p].massaGram);
    for (uint8_t i = 0; i < 4; i++) {
      if (i)
        Serial.print(" / ");
      Serial.print(profilBenda[p].jarak[i], 2);
    }
    Serial.println(" cm");
  }
}
void profilShow() {
  float d[4];
  String sebab;
  bool siap = profilSnapshot(d, sebab);
  Serial.println("===== US1..US4: RAW / FILTER (cm) =====");
  for (uint8_t i = 0; i < 4; i++) {
    Serial.printf("US%u RAW %.2f | FILTER %.2f\n", (unsigned int)(i + 1),
                  jarakSonarRaw[i], jarakSonarHalus[i]);
  }
  if (!siap) {
    Serial.println(String("BELUM BISA KENALI: ") + sebab);
    return;
  }
  float err = NAN;
  int id = profilKenali(d, err);
  if (id >= 0)
    Serial.printf("COCOK (+/-%.2fcm/US + massa): PROFIL %d [%s], A=%.3f cm2, "
                  "massa ref=%.2f g, MAE JARAK=%.3f cm\n",
                  PROF_TOLERANSI_CM, id + 1, profilBenda[id].nama.c_str(),
                  profilBenda[id].luas, profilBenda[id].massaGram, err);
  else
    Serial.printf("TIDAK BOLEH PAKAI LUAS: %s\n", id == -4 ? "BELUM EMPTY"
                                                  : id == -3
                                                      ? "KOSONG/OBJEK LEMAH"
                                                  : id == -2 ? "AMBIGU"
                                                             : "TIDAK DIKENAL");
  Serial.printf("Toleransi: US1..US4 masing-masing +/-%.2f cm dari rekaman.\n",
                PROF_TOLERANSI_CM);
  Serial.printf("HX711 sekarang=%.2f g | HYBRID: REF=%.1f/%.1f cm | ambang "
                "beda luas=%.0f%%\n",
                hybridMassaSaatIniGram(), HYB_REF_KIRI_KANAN_CM,
                HYB_REF_ATAS_BAWAH_CM, HYB_SELISIH_LUAS_MAX * 100.0f);
  Serial.println("Pola stabil != jarak akurat. PROFIL memperbaiki LUAS, bukan "
                 "mengubah RAW US.");
}
void profilHelp() {
  Serial.println("=== PROFIL LUAS KONTAK / 4 HC-SR04 ===");
  Serial.println("Pilih dashboard PADAT dahulu. 115200 baud + Newline.");
  Serial.println("PROFIL HELP         : bantuan");
  Serial.println("NVSDEBUG            : cek isi NVS + jumlah entri tersedia; "
                 "jangan EMPTY dulu");
  Serial.println(
      "Jika NVS gagal: simpan hasil LIST dan NVSDEBUG sebelum tindakan hapus.");
  Serial.println("SHOW                : jarak US1..4 + pengenalan");
  Serial.println("LIST                : seluruh profil 1..10");
  Serial.println(
      "EMPTY               : simpan kondisi KOSONG; HAPUS SEMUA PROFIL LAMA");
  Serial.println("NAME 1 KUBUS        : simpan nama (opsional)");
  Serial.println(
      "LEARN 1 6.25        : rekam 4 jarak + MASSA HX711 + luas alas 6.25 cm2");
  Serial.println("LEARN 2 12.50       : rekam pola benda ke-2 dan luas acuan");
  Serial.printf(
      "TOLERANSI TETAP     : setiap US1..4 +/-%.2f cm dari nilai saat LEARN\n",
      PROF_TOLERANSI_CM);
  Serial.println(
      "Satu sensor di luar batas: TIDAK DIKENALI, luas=--, tekanan padat=--");
  Serial.println("LEARN membutuhkan >=1 sensor bergeser >=0.70 cm dari EMPTY.");
  Serial.printf("Profil dengan pola sonar mirip dapat dibedakan oleh MASSA, "
                "jika toleransinya tidak overlap (batas sonar %.2f cm).\n",
                PROF_MIN_PISAH);
  Serial.println(
      "CHECK 1             : lihat selisih semua sensor dari profil nomor 1");
  Serial.println(
      "MODE OTOMATIS: area profil aktif sejak boot, tanpa PROFIL ON.");
  Serial.println("WAJIB kalibrasi HX711 dan ZL dahulu; profil lama tanpa massa "
                 "perlu LEARN ulang.");
  Serial.println(
      "Hybrid pakai 12-(US1+US2), 12-(US3+US4), selisih >10% -> luas profil.");
  Serial.println(
      "CLEAR 1             : hapus satu profil; CLEAR ALL hapus semua profil");
  Serial.println(
      "WAJIB: setiap benda di posisi/orientasi sama, semua jarak stabil.");
}
void profilPerintah(const String &cmd) {
  if (cmd == "NVSDEBUG") {
    profilNvsDebug();
    return;
  }
  if (cmd == "PROFIL HELP" || cmd == "HELP") {
    profilHelp();
    return;
  }
  if (cmd == "LIST" || cmd == "PROFIL LIST") {
    profilList();
    return;
  }
  if (cmd == "SHOW" || cmd == "PROFIL SHOW") {
    profilShow();
    return;
  }
  if (cmd == "PROFIL ON" || cmd == "PROFIL OFF") {
    Serial.println("Mode PROFIL sudah OTOMATIS. Gunakan EMPTY (awal) dan LEARN "
                   "untuk merekam benda.");
    return;
  }
  if (cmd == "EMPTY") {
    float d[4];
    String why;
    if (!profilSnapshot(d, why)) {
      Serial.println(String("EMPTY GAGAL: ") + why);
      return;
    }
    if (!profilNvsSiap) {
      Serial.println(
          "EMPTY GAGAL: NVS tidak tersedia. Profil lama tidak dihapus.");
      return;
    }
    // Simpan baseline dan cek penulisan sebelum mengubah status RAM/profil.
    // Snapshot lama dipertahankan untuk diagnosis bila proses gagal.
    bool baselineTersimpan = true;
    for (uint8_t i = 0; i < 4; i++) {
      const String k = profilKey("empty", i);
      size_t n = prefsProfil.putFloat(k.c_str(), d[i]);
      float baca = prefsProfil.getFloat(k.c_str(), NAN);
      if (n != sizeof(float) || !isfinite(baca) || fabsf(baca - d[i]) > 0.001f)
        baselineTersimpan = false;
    }
    if (baselineTersimpan) {
      const size_t n = prefsProfil.putBool("emptyOK", true);
      baselineTersimpan =
          n == sizeof(bool) && prefsProfil.getBool("emptyOK", false);
    }
    if (!baselineTersimpan) {
      Serial.println("EMPTY GAGAL: NVS baseline tidak berhasil diverifikasi.");
      Serial.println("Profil belum dihapus; cek NVSDEBUG. Jangan RESET dulu.");
      return;
    }
    for (uint8_t i = 0; i < 4; i++)
      profilKosong[i] = d[i];
    profilKosongOK = true;
    bool semuaBerhasil = true;
    for (uint8_t p = 0; p < PROF_JUMLAH; p++) {
      ProfilBenda lama = profilBenda[p];
      profilResetSlot(p);
      if (!profilSaveSlot(p)) {
        semuaBerhasil = false;
        profilBenda[p] = lama;
      }
    }
    profilAktif = true;
    profilResetTracking();
    Serial.println(
        semuaBerhasil
            ? "EMPTY TERSIMPAN. PERHATIAN: seluruh profil sebelumnya dihapus."
            : "EMPTY: GAGAL menghapus beberapa profil di NVS. Ketik NVSDEBUG.");
    return;
  }
  if (cmd == "CLEAR ALL") {
    if (!profilNvsSiap || !prefsProfil.clear()) {
      Serial.println("CLEAR ALL GAGAL: NVS tidak dapat dihapus.");
      return;
    }
    profilKosongOK = false;
    profilAktif = true;
    for (uint8_t j = 0; j < 4; j++)
      profilKosong[j] = NAN;
    for (uint8_t p = 0; p < PROF_JUMLAH; p++) {
      profilBenda[p].nama = String("BENDA_") + String((unsigned int)(p + 1));
      profilResetSlot(p);
    }
    profilResetTracking();
    Serial.println("PROFIL DIHAPUS (kalibrasi tekanan/load cell tetap).");
    return;
  }
  if (cmd.startsWith("NAME ")) {
    String arg = cmd.substring(5);
    arg.trim();
    int pos = arg.indexOf(' ');
    if (pos < 1) {
      Serial.println("Format NAME <1..10> <NAMA>");
      return;
    }
    int id = arg.substring(0, pos).toInt();
    String nama = arg.substring(pos + 1);
    nama.trim();
    if (id < 1 || id > PROF_JUMLAH || nama.length() == 0) {
      Serial.println("Format NAME <1..10> <NAMA>");
      return;
    }
    if (nama.length() > 20)
      nama = nama.substring(0, 20);
    if (!profilNvsSiap) {
      Serial.println("NAME GAGAL: NVS tidak siap.");
      return;
    }
    const String k = profilKey("name", (uint8_t)(id - 1));
    const size_t n = prefsProfil.putString(k.c_str(), nama);
    if (n == 0 || prefsProfil.getString(k.c_str(), String("")) != nama) {
      Serial.println("NAME GAGAL: penulisan/validasi NVS gagal.");
      return;
    }
    profilBenda[id - 1].nama =
        nama; // Tidak mengubah status LEARN, area, atau jarak.
    Serial.println(String("NAMA TERSIMPAN NVS: ") + nama);
    return;
  }
  int id = 0;
  float luas = NAN;
  char extra;
  if (cmd.startsWith("LEARN ")) {
    if (sscanf(cmd.c_str(), "LEARN %d %f %c", &id, &luas, &extra) != 2 ||
        id < 1 || id > PROF_JUMLAH || !isfinite(luas) || luas <= 0 ||
        luas > PROF_LUAS_MAKS) {
      Serial.println(
          "Format LEARN <1..10> <LUAS_CM2>; luas harus >0 dan <=78.54");
      return;
    }
    if (!profilKosongOK) {
      Serial.println("LEARN GAGAL: EMPTY dahulu.");
      return;
    }
    float d[4];
    String why;
    if (!profilSnapshot(d, why)) {
      Serial.println(String("LEARN GAGAL: ") + why);
      return;
    }
    const float massa = hybridMassaSaatIniGram();
    if (!isfinite(massa)) {
      Serial.println("LEARN GAGAL: HX711 belum terkalibrasi/stabil atau massa "
                     "di luar 2..1000 g.");
      Serial.println("Tare ZL tanpa benda, kalibrasi L <kg>, lalu letakkan "
                     "benda sebelum LEARN.");
      return;
    }
    if (profilEvidence(d) < 1) {
      Serial.println("LEARN GAGAL: tidak ada sensor berubah >=0.70cm dari "
                     "EMPTY. Cek posisi benda/EMPTY.");
      return;
    }
    for (uint8_t p = 0; p < PROF_JUMLAH; p++) {
      if (p == (uint8_t)(id - 1) || !profilBenda[p].learned)
        continue;
      float maxdiff = 0;
      for (uint8_t i = 0; i < 4; i++)
        maxdiff = max(maxdiff, fabsf(d[i] - profilBenda[p].jarak[i]));
      const float massaLain = profilBenda[p].massaGram;
      const bool massaOverlap =
          isfinite(massaLain) &&
          fabsf(massa - massaLain) <=
              max(HYB_TOL_MASSA_MIN_G, massa * HYB_TOL_MASSA_PERSEN) +
                  max(HYB_TOL_MASSA_MIN_G, massaLain * HYB_TOL_MASSA_PERSEN);
      if (maxdiff < PROF_MIN_PISAH && massaOverlap) {
        Serial.printf(
            "LEARN DITOLAK: SONAR dan MASSA overlap dengan PROFIL %u.\n",
            (unsigned)(p + 1));
        return;
      }
    }
    ProfilBenda &p = profilBenda[id - 1];
    const ProfilBenda cadangan = p;
    p.learned = true;
    p.luas = luas;
    p.massaGram = massa;
    for (uint8_t i = 0; i < 4; i++)
      p.jarak[i] = d[i];
    if (!profilSaveSlot((uint8_t)(id - 1))) {
      p = cadangan;
      Serial.println(
          "LEARN GAGAL: tidak bisa disimpan permanen. Ketik NVSDEBUG.");
      return;
    }
    profilResetTracking();
    Serial.printf(
        "LEARN %d OK + VERIFIED NVS. %s: LUAS KONTAK=%.3f cm2 | MASSA=%.2f g\n",
        id, p.nama.c_str(), luas, massa);
    profilShow();
    return;
  }
  if (cmd.startsWith("CHECK ")) {
    if (sscanf(cmd.c_str(), "CHECK %d %c", &id, &extra) != 1 || id < 1 ||
        id > PROF_JUMLAH || !profilBenda[id - 1].learned) {
      Serial.println("Format CHECK <nomor profil yang sudah LEARN>");
      return;
    }
    float d[4];
    String why;
    if (!profilSnapshot(d, why)) {
      Serial.println(String("CHECK GAGAL: ") + why);
      return;
    }
    float sum = 0, maximum = 0;
    bool semuaDalam = true;
    Serial.printf("PERIKSA PROFIL %d, TOLERANSI SETIAP SENSOR +/-%.2f cm\n", id,
                  PROF_TOLERANSI_CM);
    Serial.printf("MASSA SEKARANG=%.2f g | PROFIL=%.2f g\n",
                  hybridMassaSaatIniGram(), profilBenda[id - 1].massaGram);
    for (uint8_t i = 0; i < 4; i++) {
      const float tersimpan = profilBenda[id - 1].jarak[i];
      float delta = fabsf(d[i] - tersimpan);
      sum += delta;
      maximum = max(maximum, delta);
      bool dalam = delta <= PROF_TOLERANSI_CM;
      if (!dalam)
        semuaDalam = false;
      Serial.printf(
          "US%u SEKARANG=%.2f | REKAM=%.2f | BATAS=%.2f..%.2f | SELISIH=%.2f | "
          "%s\n",
          (unsigned int)(i + 1), d[i], tersimpan, tersimpan - PROF_TOLERANSI_CM,
          tersimpan + PROF_TOLERANSI_CM, delta, dalam ? "OK" : "DI LUAR");
    }
    const bool bedaEmpty = profilEvidence(d) >= 1;
    float beda = NAN;
    const int match = profilKenali(d, beda);
    Serial.printf("MAE=%.3f | MAX=%.3f | BEDA EMPTY=%s | STATUS=%s\n",
                  sum / 4.0f, maximum, bedaEmpty ? "YA" : "TIDAK",
                  (semuaDalam && bedaEmpty && match == id - 1)
                      ? "COCOK: LUAS DAPAT DIPAKAI"
                      : "TIDAK COCOK: LUAS=--");
    return;
  }
  if (cmd.startsWith("CLEAR ")) {
    if (sscanf(cmd.c_str(), "CLEAR %d %c", &id, &extra) != 1 || id < 1 ||
        id > PROF_JUMLAH) {
      Serial.println("Format CLEAR <1..10>");
      return;
    }
    const ProfilBenda cadangan = profilBenda[id - 1];
    profilResetSlot((uint8_t)(id - 1));
    if (!profilSaveSlot((uint8_t)(id - 1))) {
      profilBenda[id - 1] = cadangan;
      Serial.println("CLEAR GAGAL: NVS gagal ditulis.");
      return;
    }
    profilResetTracking();
    Serial.printf("PROFIL %d DIHAPUS DAN DIVERIFIKASI.\n", id);
    return;
  }
}

float areaDigunakanCm2() {
  // Tidak ada fallback manual / rumus jarak lama; gagal pengenalan -> NAN.
  return profilLuasAktif();
}

float solidKPa() {
  const float f = forceN();
  const float a = areaDigunakanCm2();
  if (!isfinite(f) || !isfinite(a) || a <= 0.0f)
    return NAN;
  return hasilMinimalNol((f / (a / 10000.0f)) / 1000.0f);
}
float modeKPa() {
  if (mode == 0)
    return liquidKPa();
  if (mode == 1)
    return gasKPa(); // angka besar = TEKANAN GAUGE dari HX710B gas
  return solidKPa();
}

// Konversi hanya untuk OUTPUT Serial/Blynk (bukan variabel internal sensor).
// P internal = kPa, T sensor DHT22 = degC.
float keluaranPa(float kPa) { return isfinite(kPa) ? kPa * 1000.0f : NAN; }
float keluaranM3(float volumeL) { return volumeL / 1000.0f; }
float keluaranKelvin(float celsius) {
  return isfinite(celsius) ? celsius + 273.15f : NAN;
}
void cetakNilaiSerial(float nilai, unsigned int desimal = 2U) {
  if (isfinite(nilai))
    Serial.print(nilai, desimal);
  else
    Serial.print("--");
}
void resetCalibration(const String &target);
// ===== OLED SH1106: WELCOME + 3 DASHBOARD + DETAIL + SETTINGS =====
void header(const char *title) {
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(0, 9, title);
  oled.drawHLine(0, 12, 128);
}
void footer(const char *title) {
  oled.drawHLine(0, 53, 128);
  oled.setFont(u8g2_font_5x7_tf);
  oled.drawStr(0, 62, title);
}
void lineAt(int y, const String &str) {
  oled.setFont(u8g2_font_6x10_tf);
  oled.setCursor(0, y);
  oled.print(str);
}
void msg(const String &str, Page back = MENU) {
  info = str;
  messageBack = back;
  page = MESSAGE;
}

// ===== IMPLEMENTASI KALIBRASI PREV/SELECT =====
// Mengambil median 5 sampel RAW terbaru, bukan EMA yang lambat ketika
// beban atau tekanan baru saja berubah. Rentang RAW untuk pemeriksaan stabil.
bool kalAmbilMedianRaw(const MedianEma5 &filter, bool sensorOK,
                       unsigned long terakhirOK, float &median,
                       float &rentang) {
  if (!sensorOK || !filter.ready() || millis() - terakhirOK > KAL_USIA_ADC_MS)
    return false;
  float v[5];
  for (int i = 0; i < 5; i++) {
    if (!isfinite(filter.buf[i]))
      return false;
    v[i] = filter.buf[i];
  }
  for (int i = 1; i < 5; i++) {
    float x = v[i];
    int j = i - 1;
    while (j >= 0 && v[j] > x) {
      v[j + 1] = v[j];
      j--;
    }
    v[j + 1] = x;
  }
  median = v[2];
  rentang = v[4] - v[0];
  return isfinite(median) && isfinite(rentang);
}

bool kalBacaMode(int m, float &median, float &rentang) {
  if (m == 0)
    return kalAmbilMedianRaw(filterCair, cairOK, lastCairOK, median, rentang);
  if (m == 1)
    return kalAmbilMedianRaw(filterGasHx, gasOK, lastGasOK, median, rentang);
  return kalAmbilMedianRaw(filterLoad, loadOK, lastLoadOK, median, rentang);
}

// Kurva 2-PREV ditambah berurutan; jumlah titik menjadi penanda commit.
bool kalSimpanTitikBalon(float pKPa, float volumeL) {
  const uint8_t pos = balonJumlahTitik;
  if (pos >= 2)
    return false;
  const String keyP = String("bp12_") + pos;
  const String keyV = String("bv12_") + pos;
  if (prefs.putFloat(keyP.c_str(), pKPa) != sizeof(float) ||
      prefs.putFloat(keyV.c_str(), volumeL) != sizeof(float) ||
      prefs.putUChar("balCt12", pos + 1) != sizeof(uint8_t))
    return false;
  balonPKPa[pos] = pKPa;
  balonVolumeL[pos] = volumeL;
  ++balonJumlahTitik;
  return true;
}

unsigned long kalDurasiMs() {
  return isfinite(kalVolumeAcuanL) ? KAL_TUNGGU_ACUAN_GAS_MS
                                   : KAL_TUNGGU_PRESET_MS;
}

float kalBatasRaw(float delta, float skalaGas, bool rekamAcuanGas) {
  return rekamAcuanGas ? KAL_ACUAN_GAS_STABIL_KPA / fabsf(skalaGas)
                       : fmaxf(50.0f, fabsf(delta) * 0.20f);
}

// NVS pressure diperiksa sebelum nilai RAM diganti. Mempertahankan nilai lama
// apabila penulisan/validasi gagal; bukan memanggil saveSettings() yang menulis
// seluruh puluhan key dan berpotensi memenuhi NVS.
bool kalSimpanPasangan(int m, long nol, float skala) {
  const char *keyNol = m == 0 ? "zc" : m == 1 ? "zg" : "zl";
  const char *keySkala = m == 0 ? "sc" : m == 1 ? "sg" : "sl";
  long nolLama = m == 0 ? zeroCair : m == 1 ? zeroGas : zeroLoad;
  float skalaLama = m == 0 ? scaleCair : m == 1 ? scaleGas : scaleLoad;

  // Setelah referensi tekanan berganti, data P-V lama tidak boleh dipakai.
  if (m == 1 && prefs.putUChar("balCt12", 0) != sizeof(uint8_t))
    return false;
  const size_t n1 = prefs.putLong(keyNol, nol);
  const size_t n2 = m == 1 && skala == skalaLama
                        ? sizeof(float)
                        : prefs.putFloat(keySkala, skala);
  const bool berhasil = (n1 == sizeof(int32_t) && n2 == sizeof(float) &&
                         prefs.getLong(keyNol, 0x7FFFFFFF) == nol &&
                         fabsf(prefs.getFloat(keySkala, NAN) - skala) <=
                             fmaxf(1e-10f, fabsf(skala) * 0.0001f));
  if (!berhasil) {
    // Usaha pemulihan nilai kalibrasi lama apabila salah satu key sempat
    // ditulis.
    const bool pulihNol = prefs.putLong(keyNol, nolLama) == sizeof(int32_t);
    const bool pulihSkala =
        prefs.putFloat(keySkala, skalaLama) == sizeof(float);
    if (m == 1 &&
        (!pulihNol || !pulihSkala ||
         prefs.putUChar("balCt12", balonJumlahTitik) != sizeof(uint8_t))) {
      balonHapusKurva();
    }
    Serial.printf("KAL GAGAL SIMPAN NVS: %s / %s, tulis=%u/%u. "
                  "Cek NVSDEBUG dan kapasitas flash.\n",
                  keyNol, keySkala, (unsigned)n1, (unsigned)n2);
    return false;
  }
  if (m == 0) {
    zeroCair = nol;
    scaleCair = skala;
  } else if (m == 1) {
    zeroGas = nol;
    scaleGas = skala;
    balonHapusKurva();
    if (gasBaselineValid) {
      clearGasBaseline();
      prefs.putBool("gasB0OK", false);
    }
  } else {
    zeroLoad = nol;
    scaleLoad = skala;
  }
  return true;
}

void kalMulaiCepat() {
  const float skalaGasLama = mode == 1 && isfinite(scaleGas) ? scaleGas : 0.0f;
  const bool rekamAcuanGas =
      mode == 1 && skalaGasLama != 0.0f && balonJumlahTitik == 1;
  if (rekamAcuanGas && (!isfinite(diameterBalonCm) || diameterBalonCm < 1.0f ||
                        diameterBalonCm > 45.0f)) {
    Serial.println("GAS: ukur diameter balon acuan (hampir bulat), lalu simpan "
                   "D0 <cm>, rentang 1-45 cm.");
    msg("Isi diameter acuan D0", MEASURE);
    return;
  }
  // Untuk GAS dengan skala tersimpan, delta ekuivalen hanya dipakai untuk
  // toleransi nol.
  const float delta = skalaGasLama != 0.0f ? kalAcuanMode(mode) / skalaGasLama
                                           : kalDeltaMode(mode);
  if (skalaGasLama == 0.0f && !kalDeltaValid(delta)) {
    Serial.printf(
        "KAL %s: skala belum ada. %s\n", names[mode],
        mode == 0 ? "Isi RAWCAIR <delta_count>."
        : mode == 1
            ? "Kalibrasi Z2/C2 atau isi RAWGAS pada tekanan acuan terukur."
            : "Isi RAW16 <delta_count>.");
    msg(mode == 0   ? "Isi RAWCAIR di Serial"
        : mode == 1 ? "Skala GAS belum ada"
                    : "Isi RAW16 di Serial",
        MEASURE);
    return;
  }

  float rawAwal = NAN, rentang = NAN;
  if (!kalBacaMode(mode, rawAwal, rentang)) {
    msg("Sensor belum siap", MEASURE);
    return;
  }
  if (rentang > kalBatasRaw(delta, skalaGasLama, rekamAcuanGas)) {
    msg(rekamAcuanGas ? "Tutup katup, tunggu stabil" : "RAW nol tidak stabil",
        MEASURE);
    return;
  }
  kalMode = mode;
  kalRawAwal = lroundf(rawAwal);
  kalDeltaSaatMulai = delta;
  kalSkalaGasAwal = skalaGasLama;
  kalVolumeAcuanL = rekamAcuanGas ? volumeBalonL() : NAN;
  kalMulaiTunggu = millis();
  page = QUICK_CAL;
  if (mode == 1) {
    if (rekamAcuanGas)
      Serial.printf("PREV 2 GAS: tahan balon %.2f cm (%.7f m3), katup tutup, "
                    "tunggu 3 detik.\n",
                    diameterBalonCm, keluaranM3(kalVolumeAcuanL));
    else
      Serial.println(
          "PREV 1 GAS: balon kempis, buka katup ke udara, tunggu 10 detik.");
  } else {
    Serial.printf("KAL PRESET %s: 10 detik, TANPA beban/tekanan. RAW_AWAL=%ld; "
                  "DELTA_ACUAN=%+.1f count. NEXT untuk batal.\n",
                  names[mode], kalRawAwal, delta);
  }
}

void kalSelesaikanPreset() {
  const int m = kalMode;
  kalMode = -1;
  const float delta = kalDeltaSaatMulai;
  const bool rekamAcuanGas = isfinite(kalVolumeAcuanL);
  const bool pakaiSkalaGasLama = m == 1 && kalSkalaGasAwal != 0.0f;
  if (m == 1 && (isfinite(scaleGas) ? scaleGas : 0.0f) != kalSkalaGasAwal) {
    msg("Skala GAS berubah", MEASURE);
    return;
  }
  float rawKini = NAN, rentang = NAN;
  if ((!pakaiSkalaGasLama && !kalDeltaValid(delta)) ||
      !kalBacaMode(m, rawKini, rentang)) {
    msg("KAL GAGAL: sensor/RAW", MEASURE);
    return;
  }
  const float batas = kalBatasRaw(delta, kalSkalaGasAwal, rekamAcuanGas);
  if (fabsf(rawKini - (float)kalRawAwal) > batas || rentang > batas) {
    Serial.printf("KAL DITOLAK [%s]: RAW_AWAL=%ld RAW_AKHIR=%.1f RENTANG=%.1f "
                  "BATAS=%.1f.\n",
                  names[m], kalRawAwal, rawKini, rentang, batas);
    msg(rekamAcuanGas ? "Tekanan belum stabil" : "RAW berubah, kal batal",
        MEASURE);
    return;
  }

  if (rekamAcuanGas) {
    if (balonJumlahTitik != 1) {
      msg("Titik nol berubah", MEASURE);
      return;
    }
    const float pAcuan = (rawKini - zeroGas) * scaleGas;
    if (!isfinite(pAcuan) ||
        pAcuan - balonPKPa[0] <= KAL_ACUAN_GAS_STABIL_KPA) {
      msg("P acuan terlalu kecil", MEASURE);
      return;
    }
    if (!kalSimpanTitikBalon(pAcuan, kalVolumeAcuanL)) {
      msg("NVS gagal simpan acuan", MEASURE);
      return;
    }
    Serial.printf("PREV 2 GAS OK: P1=%.1f Pa, V1=%.7f m3. ZERO=%ld.\n",
                  pAcuan * 1000.0f, keluaranM3(kalVolumeAcuanL), zeroGas);
  } else {
    const long nol = lroundf(rawKini);
    const float skala =
        pakaiSkalaGasLama ? kalSkalaGasAwal : kalAcuanMode(m) / delta;
    if (!pakaiSkalaGasLama &&
        (!isfinite(skala) || fabsf(skala) < 1.0e-15f || fabsf(skala) > 1.0f)) {
      msg("KAL GAGAL: skala", MEASURE);
      return;
    }
    if (!kalSimpanPasangan(m, nol, skala)) {
      msg("NVS gagal simpan kal", MEASURE);
      return;
    }
    if (m != 1) {
      Serial.printf("KAL PRESET %s OK: ZERO=%ld, SKALA=%.10g.\n", names[m], nol,
                    skala);
      msg(m == 2 ? "Kalibrasi Berhasil" : "Kalibrasi Berhasil", MEASURE);
      return;
    }
    if (!kalSimpanTitikBalon(0.0f, 0.0f)) {
      msg("Nol P OK, simpan V gagal", MEASURE);
      return;
    }
    Serial.printf("PREV 1 GAS OK: ZERO=%ld, P0=0 Pa, V0=0 m3. Isi ke %.2f cm "
                  "lalu PREV 2.\n",
                  nol, diameterBalonCm);
  }
  filterGasHx.value = rawKini;
  tampilKPa[1] = NAN;
  page = MEASURE;
}

void kalLayananCepat() {
  if (page == QUICK_CAL && kalMode >= 0 &&
      millis() - kalMulaiTunggu >= kalDurasiMs())
    kalSelesaikanPreset();
}

void drawKalCepat() {
  if (kalMode < 0)
    return;
  const bool padat = kalMode == 2;
  const bool gas = kalMode == 1;
  const bool rekamAcuanGas = isfinite(kalVolumeAcuanL);
  header(padat           ? "KALIBRASI TIMBANGAN"
         : !gas          ? "KALIBRASI TEKANAN"
         : rekamAcuanGas ? "GAS 2/2 Diameter Balon"
                         : "GAS 1/2 NOL P DAN V");
  const unsigned long durasi = kalDurasiMs();
  const unsigned long lewat = millis() - kalMulaiTunggu;
  const unsigned int sisa =
      lewat >= durasi ? 0U : (unsigned int)((durasi - lewat + 999UL) / 1000UL);
  oled.setFont(u8g2_font_5x7_tf);
  if (gas) {
    oled.drawStr(0, 23,
                 rekamAcuanGas ? "Katup tutup, tahan balon"
                               : "Balon kempis, buka katup");
    oled.drawStr(0, 33,
                 rekamAcuanGas
                     ? (String("V acuan: ") +
                        String(keluaranM3(kalVolumeAcuanL), 6) + " m3")
                           .c_str()
                     : "P = 0 Pa, V = 0 m3");
  } else {
    oled.drawStr(0, 23,
                 padat ? "Kosongkan Timbangan" : "Tekanan: NOL / TANPA BEBAN");
    oled.drawStr(
        0, 33,
        (String("Preset delta: ") + String(kalDeltaSaatMulai, 0)).c_str());
  }
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(4, 47, (String("Sisa: ") + String(sisa) + " detik").c_str());
  footer("              NEXT: BATAL");
}

// Landing SH1106 128x64: animasi gauge + gelombang + tombol MULAI pulsing.
// Seluruh animasi memakai millis(), tanpa delay blocking.
void drawWelcome() {
  const unsigned long t = millis();
  const bool bright = ((t / 600UL) % 2UL) == 0;
  const uint8_t pulse = (t / 220UL) % 4UL;

  // Frame minimalis dan tulisan terpusat.
  oled.drawRFrame(1, 1, 126, 62, 4);
  oled.setFont(u8g2_font_6x10_tf);
  const char *title = "ALAT UKUR TEKANAN";
  oled.drawStr((128 - oled.getStrWidth(title)) / 2, 12, title);
  oled.setFont(u8g2_font_5x7_tf);
  const char *caption = "SIAP DIMULAI";
  oled.drawStr((128 - oled.getStrWidth(caption)) / 2, 21, caption);

  // Indikator gauge analog di tengah: jarum bergerak pelan ke kiri-kanan.
  const int cx = 64, cy = 35;
  oled.drawCircle(cx, cy, 11, U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
  oled.drawHLine(cx - 13, cy + 1, 26);
  const float phase = sinf((float)t * 0.0035f);
  const float angle = -1.5707963f + phase * 0.85f;
  const int nx = cx + (int)(7.0f * cosf(angle));
  const int ny = cy + (int)(7.0f * sinf(angle));
  oled.drawLine(cx, cy, nx, ny);
  oled.drawDisc(cx, cy, 2);

  // Tiga titik animasi seperti sinyal pemindaian sensor.
  for (uint8_t i = 0; i < 3; i++) {
    const uint8_t radius = (i == pulse % 3) ? 2 : 1;
    oled.drawDisc(33 + i * 7, 35, radius);
    oled.drawDisc(80 + i * 7, 35, radius);
  }

  // Tombol CTA berkedip kontras, tetap terbaca di kedua fase.
  if (bright) {
    oled.drawRBox(35, 45, 58, 12, 3);
    oled.setDrawColor(0);
  } else {
    oled.drawRFrame(35, 45, 58, 12, 3);
    oled.setDrawColor(1);
  }
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(48, 54, "MULAI");
  oled.setDrawColor(1);
  oled.setFont(u8g2_font_5x7_tf);
}
void drawHome() {
  header(" PILIH JENIS TEKANAN");
  for (int i = 0; i < 3; ++i) {
    const int y = 17 + i * 12;
    if (homeSelection == i) {
      oled.drawBox(0, y, 126, 12);
      oled.setDrawColor(0);
    }
    oled.setFont(u8g2_font_6x10_tf);
    oled.setCursor(5, y + 9);
    oled.print(String(i + 1) + ". " + names[HOME_ORDER[i]]);
    oled.setDrawColor(1);
  }
  footer(" PREV     SELECT    NEXT ");
}
// Tidak mengubah data sensor; hanya menahan laju perubahan angka di OLED.
float oledPressureKPa(int activeMode) {
  float latest = modeKPa();
  if (!isfinite(latest)) {
    tampilKPa[activeMode] = NAN;
    return NAN;
  }
  unsigned long now = millis();
  if (!isfinite(tampilKPa[activeMode]) ||
      now - terakhirTampil[activeMode] >= INTERVAL_TAMPIL_MS) {
    tampilKPa[activeMode] = latest;
    terakhirTampil[activeMode] = now;
  }
  return tampilKPa[activeMode];
}
// Satuan hanyalah format tampilan: semua perhitungan tetap memakai kPa.
// pressureUnit: 0=kPa, 1=Pa, 2=bar.
const char *labelSatuanTekanan() {
  if (pressureUnit == 1)
    return "Pa";
  if (pressureUnit == 2)
    return "bar";
  return "kPa";
}

String angkaTekananTampil(float nilaiKPa) {
  if (!isfinite(nilaiKPa))
    return "--";
  nilaiKPa = hasilMinimalNol(nilaiKPa);
  if (pressureUnit == 1)
    return String(nilaiKPa * 1000.0f, 0); // 1 kPa = 1000 Pa
  if (pressureUnit == 2)
    return String(nilaiKPa / 100.0f, 4); // 1 bar = 100 kPa
  return String(nilaiKPa, 2);
}

void bigPressure(float nilaiKPa) {
  const String val = angkaTekananTampil(nilaiKPa);
  const char *unit = labelSatuanTekanan();
  // Unit diberi ruang sendiri: nilai besar dalam Pa tidak menimpa tulisan unit.
  oled.setFont(u8g2_font_6x10_tf);
  const int unitWidth = oled.getStrWidth(unit);
  const int unitX = 126 - unitWidth;
  const int ruangAngka = unitX - 3;
  oled.setFont(u8g2_font_logisoso24_tn);
  if ((int)oled.getStrWidth(val.c_str()) > ruangAngka)
    oled.setFont(u8g2_font_logisoso18_tn);
  if ((int)oled.getStrWidth(val.c_str()) > ruangAngka)
    oled.setFont(u8g2_font_6x10_tf); // cadangan agar tidak terpotong
  int x = (ruangAngka - (int)oled.getStrWidth(val.c_str())) / 2;
  if (x < 0)
    x = 0;
  oled.drawStr(x, 39, val.c_str());
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(unitX, 37, unit);
}
void drawMeasure() {
  const char *titles[] = {"  TEKANAN ZAT CAIR", "  TEKANAN ZAT GAS",
                          "  TEKANAN ZAT PADAT"};
  header(titles[mode]);
  bigPressure(oledPressureKPa(mode));
  oled.drawHLine(0, 42, 128);
  oled.setFont(u8g2_font_5x7_tf);
  if (mode == 0) {
    float h = liquidKPa() * 100000.0f / (rho * G);
    oled.drawStr(
        1, 50,
        (String("h:") + (isfinite(h) ? String(h, 1) : "--") + "cm").c_str());
    oled.drawStr(70, 50, (String("Rho:") + String(rho, 0)).c_str());
  } else if (mode == 1) {
    oled.drawStr(1, 50,
                 (String("T:") +
                  (isfinite(airTempC) ? String(airTempC + 273.15f, 1) : "--") +
                  "K")
                     .c_str());
    const float vEstM3 = keluaranM3(volumeGasDinamisL());
    oled.drawStr(
        60, 50,
        (String("V~:") + (isfinite(vEstM3) ? String(vEstM3, 6) : "--") + "m3")
            .c_str());
  } else {
    float f = forceN();
    oled.drawStr(
        1, 50,
        (String("m:") + (isfinite(f) ? String(f / G * 1000.0f, 0) : "--") + "g")
            .c_str());
    float a = areaDigunakanCm2();
    oled.drawStr(
        70, 50,
        (String("A*:") + (isfinite(a) ? String(a, 1) : String("--"))).c_str());
  }
  if (mode == 1 && scaleGas != 0.0f && balonJumlahTitik == 1) {
    if (diameterBalonCm >= 1.0f && diameterBalonCm <= 45.0f)
      footer(
          (String("D") + String(diameterBalonCm, 1) + "cm     INFO     NEXT ")
              .c_str());
    else
      footer("SET D0     INFO     NEXT");
  } else {
    footer(" KAL      INFO      NEXT ");
  }
}
void drawDetail() {
  header(mode == 0 ? "DETAIL CAIR" : mode == 1 ? "DETAIL GAS" : "DETAIL PADAT");
  if (mode == 0) {
    lineAt(21, String("HX710: ") + (cairOK ? String(rawCair) : "OFF"));
    lineAt(31, "P: " + pressureText(liquidKPa() * 1000.0f));
    lineAt(41, "Rho: " + String(rho, 0) + " kg/m3");
    lineAt(51, scaleCair != 0 ? "Kalibrasi: OK" : "Belum kalibrasi");
  } else if (mode == 1) {
    if (detailIndex == 0) {
      const float vEstM3 = keluaranM3(volumeGasDinamisL());
      lineAt(21, "P: " + pressureText(gasKPa() * 1000.0f));
      lineAt(31, "Pabs: " +
                     (isfinite(gasPAbsKPa()) ? String(gasPAbsKPa(), 2)
                                             : String("--")) +
                     " kPa");
      lineAt(41, "T: " +
                     (isfinite(airTempC) ? String(airTempC + 273.15f, 1)
                                         : String("--")) +
                     " K");
      lineAt(51, "Vbalon: " +
                     (isfinite(vEstM3) ? String(vEstM3, 6) : String("--")) +
                     " m3");
    } else {
      const float nEstim = gasMolDariKurva();
      lineAt(21,
             "n~: " + (isfinite(nEstim) ? String(nEstim, 6) : String("--")) +
                 " mol");
      const char *labelAcuan = gasManualMolActive ? "n manual: " : "n awal: ";
      lineAt(31, String(labelAcuan) +
                     (gasMolesReady() ? String(molGas, 4) : String("--")) +
                     " mol");
      lineAt(41, "P0: " +
                     pressureText(gasBaselineValid ? gasP0KPa * 1000.0f : NAN));
      lineAt(51, "n~ = Pabs V / RT");
    }
  } else {
    float f = forceN();
    float a = areaDigunakanCm2();
    if (detailIndex == 0) {
      lineAt(21, "Massa: " +
                     (isfinite(f) ? String(f / G * 1000, 0) : String("--")) +
                     " g");
      lineAt(31,
             "Gaya : " + (isfinite(f) ? String(f, 2) : String("--")) + " N");
      lineAt(41,
             "Luas : " + (isfinite(a) ? String(a, 2) : String("--")) + " cm2");
      lineAt(51, String("Area: ") + hybridSumberLuas);
    } else {
      lineAt(21,
             "US1: " +
                 (isfinite(jarakSonarHalus[0]) ? String(jarakSonarHalus[0], 1)
                                               : String("--")) +
                 " cm");
      lineAt(31,
             "US2: " +
                 (isfinite(jarakSonarHalus[1]) ? String(jarakSonarHalus[1], 1)
                                               : String("--")) +
                 " cm");
      lineAt(41,
             "US3: " +
                 (isfinite(jarakSonarHalus[2]) ? String(jarakSonarHalus[2], 1)
                                               : String("--")) +
                 " cm");
      lineAt(51,
             "US4: " +
                 (isfinite(jarakSonarHalus[3]) ? String(jarakSonarHalus[3], 1)
                                               : String("--")) +
                 " cm");
    }
  }
  footer(mode == 1 || mode == 2 ? "HAL    KEMBALI      "
                                : "       KEMBALI      ");
}
void drawList(const String &heading, const String items[], int count, int sel) {
  header(heading.c_str());
  int first = (sel / 3) * 3;
  for (int i = 0; i < 3; i++) {
    int j = first + i;
    if (j >= count)
      break;
    int y = 16 + i * 12;
    if (j == sel) {
      oled.drawBox(0, y, 128, 12);
      oled.setDrawColor(0);
    }
    oled.setFont(u8g2_font_6x10_tf);
    oled.setCursor(3, y + 9);
    oled.print(items[j]);
    oled.setDrawColor(1);
  }
  footer(" PREV       OK       NEXT ");
}
int subCount() {
  switch (menuIndex) {
  case 0:
    return 2; // rho, kembali
  case 1:
    return 6; // baseline mol, n manual, diameter, Patm, reset, kembali
  case 2:
    return 3; // status profil, data profil, kembali
  case 3:
    return 5; // tare, nol cair, nol gas, reset, kembali
  case 4:
    return 6; // raw, US 1-2, US 3-4, kembali
  case 5:
    return 3; // unit, about, back
  }
  return 1;
}
String subName(int i) {
  const char *cair[] = {"Massa Jenis", "Kembali"};
  const char *gas[] = {"n Dari Awal", "Mol Gas Manual", "Diameter Acuan",
                       "P Atmosfer",  "Reset Data Gas", "Kembali"};
  const char *padat[] = {"Status Profil", "Data Profil", "Kembali"};
  const char *kal[] = {"Tare Load Cell", "Nol HX710 Cair", "Nol HX710 Gas",
                       "Reset Kalibrasi", "Kembali"};
  const char *diag[] = {"RAW HX710 Cair", "RAW HX710 Gas", "RAW Load Cell",
                        "US1 & US2",      "US3 & US4",     "Kembali"};
  const char *sys[] = {"Satuan Tekanan", "Informasi", "Kembali"};
  if (menuIndex == 0)
    return cair[i];
  if (menuIndex == 1)
    return gas[i];
  if (menuIndex == 2)
    return padat[i];
  if (menuIndex == 3)
    return kal[i];
  if (menuIndex == 4)
    return diag[i];
  return sys[i];
}
void drawScreen() {
  oled.clearBuffer();
  oled.setDrawColor(1);
  switch (page) {
  case WELCOME:
    drawWelcome();
    break;
  case HOME:
    drawHome();
    break;
  case MEASURE:
    drawMeasure();
    break;
  case DETAIL:
    drawDetail();
    break;
  case QUICK_CAL:
    drawKalCepat();
    break;
  case MENU: {
    String items[MENU_SIZE];
    for (int i = 0; i < MENU_SIZE; i++)
      items[i] = menuItems[i];
    drawList("PENGATURAN ALAT", items, MENU_SIZE, menuIndex);
    break;
  }
  case SUBMENU: {
    String items[6];
    for (int i = 0; i < subCount(); i++)
      items[i] = subName(i);
    drawList(menuItems[menuIndex], items, subCount(), submenuIndex);
    break;
  }
  case EDIT_VALUE: {
    const char *labs[] = {"MASSA JENIS", "", "JUMLAH MOL", "DIAMETER ACUAN",
                          "SATUAN",      "", "",           "",
                          "P ATMOSFER"};
    header(labs[editKind]);
    String v;
    if (editKind == 0)
      v = String(editValue, 0) + " kg/m3";
    else if (editKind == 2)
      v = String(editValue, 4) + " mol";
    else if (editKind == 3)
      v = String(editValue, 1) + " cm";
    else if (editKind == 4)
      v = ((int)editValue == 0 ? "kPa" : (int)editValue == 1 ? "Pa" : "bar");
    else if (editKind == 8)
      v = String(editValue, 1) + " kPa";
    else
      v = "--";
    lineAt(30, v);
    lineAt(44, "NEXT+ PREV-");
    footer("SELECT: SIMPAN");
    break;
  }
  case CONFIRM_RESET:
    header("RESET KALIBRASI?");
    lineAt(28, "SELECT: HAPUS");
    lineAt(42, "PREV: BATAL");
    footer("RESET SEMUA SENSOR");
    break;
  case MESSAGE:
    header("INFORMASI");
    oled.setFont(u8g2_font_5x7_tf);
    oled.drawStr(0, 29, info.substring(0, 25).c_str());
    oled.drawStr(0, 40,
                 info.length() > 25 ? info.substring(25, 50).c_str() : "");
    footer("SELECT: KEMBALI");
    break;
  }
  oled.sendBuffer();
}
void enterEdit(int kind, float val) {
  editKind = kind;
  editValue = val;
  page = EDIT_VALUE;
}
void navigate() {
  // NEXT membatalkan hitung mundur. PREV di dashboard memulai langkah yang
  // sesuai.
  if (page == QUICK_CAL) {
    if (evNext) {
      kalMode = -1;
      page = MEASURE;
      Serial.println("KAL PRESET DIBATALKAN. Kalibrasi lama tidak berubah.");
    }
    // SELECT/PREV tidak mengubah atau mempercepat countdown.
    return;
  }
  // LANDING: SELECT membuka pilihan jenis tekanan.
  if (page == WELCOME) {
    if (evSel) {
      homeSelection = 0;
      page = HOME;
    }
    return;
  }

  // PILIH MODE: NEXT/PREV memilih, SELECT membuka dashboard.
  if (page == HOME) {
    if (evNext)
      homeSelection = (homeSelection + 1) % 3;
    if (evPrev)
      homeSelection = (homeSelection + 2) % 3;
    if (evSel) {
      mode = HOME_ORDER[homeSelection];
      detailIndex = 0;
      page = MEASURE;
    }
    if (evLong) {
      returnAfterSettings = HOME;
      menuIndex = 0;
      page = MENU;
    }
    return;
  }

  // DASHBOARD:
  // NEXT sekali   -> kembali ke pilihan tiga jenis tekanan.
  // SELECT sekali -> detail parameter (langsung, tanpa menunggu klik kedua).
  // PREV sekali   -> kalibrasi nol, atau rekam acuan GAS jika titik nol sudah
  // ada. SELECT 2 dtk  -> menu pengaturan.
  if (page == MEASURE) {
    if (evPrev) {
      kalMulaiCepat();
      return;
    }
    if (evLong) {
      returnAfterSettings = MEASURE;
      menuIndex = 0;
      page = MENU;
      return;
    }
    if (evNext) {
      goToModeSelection();
      return;
    }
    if (evSel) {
      detailIndex = 0;
      page = DETAIL;
      return;
    }
    return;
  }

  // DETAIL:
  // NEXT -> menu pemilihan mode; PREV -> ganti subhalaman (gas/padat).
  // SELECT -> dashboard; tahan SELECT 2 dtk -> pengaturan.
  if (page == DETAIL) {
    if (evLong) {
      returnAfterSettings = DETAIL;
      menuIndex = 0;
      page = MENU;
      return;
    }
    if (evNext) {
      goToModeSelection();
      return;
    }
    if (evPrev && (mode == 1 || mode == 2)) {
      detailIndex = 1 - detailIndex;
    }
    if (evSel)
      page = MEASURE;
  } else if (page == MENU) {
    if (evNext)
      menuIndex = (menuIndex + 1) % MENU_SIZE;
    if (evPrev)
      menuIndex = (menuIndex + MENU_SIZE - 1) % MENU_SIZE;
    if (evSel) {
      if (menuIndex == MENU_SIZE - 1)
        page = returnAfterSettings;
      else {
        submenuIndex = 0;
        page = SUBMENU;
      }
    }
  } else if (page == SUBMENU) {
    int n = subCount();
    if (evNext)
      submenuIndex = (submenuIndex + 1) % n;
    if (evPrev)
      submenuIndex = (submenuIndex + n - 1) % n;
    if (evSel) {
      if (submenuIndex == n - 1) {
        page = MENU;
        return;
      }
      if (menuIndex == 0)
        enterEdit(0, rho);
      else if (menuIndex == 1) {
        if (submenuIndex == 0) {
          if (captureInitialMoles())
            msg("n dari Pabs T V0 OK", SUBMENU);
          else
            msg("Cek Z2 C2, DHT, D0", SUBMENU);
        } else if (submenuIndex == 1)
          enterEdit(2, molGas);
        else if (submenuIndex == 2)
          enterEdit(3, diameterBalonCm);
        else if (submenuIndex == 3)
          enterEdit(8, tekananAtmosferKPa);
        else if (submenuIndex == 4) {
          clearGasBaseline();
          saveSettings();
          msg("Acuan gas direset", SUBMENU);
        }
      } else if (menuIndex == 2) {
        if (submenuIndex == 0)
          msg(String("PROFIL: ") +
                  (profilKosongOK ? "AUTO SIAP" : "PERLU EMPTY"),
              SUBMENU);
        else if (submenuIndex == 1) {
          uint8_t total = 0;
          for (uint8_t i = 0; i < PROF_JUMLAH; i++)
            if (profilBenda[i].learned)
              total++;
          msg(String("TEREKAM: ") + String((unsigned int)total) + "/10 profil",
              SUBMENU);
        }
      } else if (menuIndex == 3) {
        if (submenuIndex == 0) {
          if (loadOK && filterLoad.ready()) {
            zeroLoad = lroundf(filterLoad.value);
            saveSettings();
            msg("Tare berhasil", SUBMENU);
          } else
            msg("HX711 belum siap", SUBMENU);
        } else if (submenuIndex == 1) {
          if (cairOK && filterCair.ready()) {
            zeroCair = lroundf(filterCair.value);
            scaleCair = 0;
            saveSettings();
            msg("Nol cair OK", SUBMENU);
          } else
            msg("HX710 cair OFF", SUBMENU);
        } else if (submenuIndex == 2) {
          if (gasOK && filterGasHx.ready()) {
            zeroGas = lroundf(filterGasHx.value);
            scaleGas = 0;
            balonHapusKurva();
            if (gasBaselineValid)
              clearGasBaseline();
            saveSettings();
            msg("Nol gas OK", SUBMENU);
          } else
            msg("HX710 gas OFF", SUBMENU);
        } else if (submenuIndex == 3)
          page = CONFIRM_RESET;
      } else if (menuIndex == 4) {
        if (submenuIndex == 0)
          msg("RAW Cair: " + (cairOK ? String(rawCair) : String("OFF")),
              SUBMENU);
        if (submenuIndex == 1)
          msg("RAW Gas: " + (gasOK ? String(rawGas) : String("OFF")), SUBMENU);
        if (submenuIndex == 2)
          msg("RAW Load: " + (loadOK ? String(rawLoad) : String("OFF")),
              SUBMENU);
        if (submenuIndex == 3)
          msg("US1:" +
                  (isfinite(jarakSonarHalus[0]) ? String(jarakSonarHalus[0], 1)
                                                : String("--")) +
                  " US2:" +
                  (isfinite(jarakSonarHalus[1]) ? String(jarakSonarHalus[1], 1)
                                                : String("--")),
              SUBMENU);
        if (submenuIndex == 4)
          msg("US3:" +
                  (isfinite(jarakSonarHalus[2]) ? String(jarakSonarHalus[2], 1)
                                                : String("--")) +
                  " US4:" +
                  (isfinite(jarakSonarHalus[3]) ? String(jarakSonarHalus[3], 1)
                                                : String("--")),
              SUBMENU);
      } else if (menuIndex == 5) {
        if (submenuIndex == 0)
          enterEdit(4, (float)pressureUnit);
        else
          msg("FMMIPA PIPA 24 v7.7", SUBMENU);
      }
    }
  } else if (page == EDIT_VALUE) {
    float step = 1.0f, vmin = 0.0f, vmax = 2.0f;
    switch (editKind) {
    case 0:
      step = 10;
      vmin = 500;
      vmax = 2000;
      break;
    case 2:
      step = 0.0001f;
      vmin = 0;
      vmax = 10;
      break;
    case 3:
      step = 0.5f;
      vmin = 0;
      vmax = 200;
      break;
    case 4:
      step = 1;
      vmin = 0;
      vmax = 2;
      break;
    case 8:
      step = 0.1f;
      vmin = 50.0f;
      vmax = 120.0f;
      break;
    }
    if (evNext)
      editValue = min(vmax, editValue + step);
    if (evPrev)
      editValue = max(vmin, editValue - step);
    if (evSel) {
      if (editKind == 0)
        rho = editValue;
      if (editKind == 2) {
        if (editValue > 0.0f)
          setGasManualMoles(editValue);
        else
          clearGasBaseline();
      }
      if (editKind == 3) {
        if (fabsf(diameterBalonCm - editValue) > 0.01f && gasBaselineValid)
          clearGasBaseline();
        diameterBalonCm = editValue;
      }
      if (editKind == 4)
        pressureUnit = (int)editValue;
      if (editKind == 8) {
        if (fabsf(tekananAtmosferKPa - editValue) > 0.0001f && gasBaselineValid)
          clearGasBaseline(); // n dari V0 harus diambil ulang jika P atmosfer
                              // berubah
        tekananAtmosferKPa = editValue;
      }
      saveSettings();
      page = SUBMENU;
    }
  } else if (page == CONFIRM_RESET) {
    if (evPrev)
      page = SUBMENU;
    if (evSel) {
      resetCalibration("ALL");
      msg("Kalibrasi dihapus", SUBMENU);
    }
  } else if (page == MESSAGE && evSel)
    page = messageBack;
}

// ===== RESET KALIBRASI (PREFERENCES) =====
void resetCalibration(const String &target) {
  if (target == "ALL" || target == "CAIR") {
    zeroCair = 0;
    scaleCair = 0;
  }
  if (target == "ALL" || target == "GAS") {
    zeroGas = 0;
    scaleGas = 0;
    balonHapusKurva(); // referensi pressure-volume perlu dikalibrasi ulang
    if (gasBaselineValid)
      clearGasBaseline();
  }
  if (target == "ALL" || target == "LOAD") {
    zeroLoad = 0;
    scaleLoad = 0;
  }
  // Massa jenis, luas penampang, dan satuan tidak direset.
  saveSettings();
  Serial.print("RESET KALIBRASI: ");
  Serial.println(target);
  Serial.println("Sensor terkait harus dikalibrasi ulang.");
}

// ===== KALIBRASI SERIAL =====
// Z1 = nol HX710 cair, Z2 = nol HX710 gas, ZL = tare load cell
// C1 5.0 = cair pada referensi 5 kPa, C2 5.0 = gas 5 kPa
// L 0.5 = load cell dengan massa referensi 0.5 kg
// Jangan mengirim nilai referensi sebelum ada pengukuran referensi nyata.
void serialCommands() {
  if (!Serial.available())
    return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  cmd.toUpperCase();
  cmd.replace(',', '.'); // desimal Indonesia juga diterima
  if (cmd == "NVSDEBUG" || cmd == "PROFIL HELP" || cmd == "HELP" ||
      cmd == "SHOW" || cmd == "PROFIL SHOW" || cmd == "LIST" ||
      cmd == "PROFIL LIST" || cmd == "EMPTY" || cmd == "PROFIL ON" ||
      cmd == "PROFIL OFF" || cmd == "CLEAR ALL" || cmd.startsWith("NAME ") ||
      cmd.startsWith("LEARN ") || cmd.startsWith("CHECK ") ||
      cmd.startsWith("CLEAR ")) {
    profilPerintah(cmd);
    return;
  }
  // RAWGAS (mode GAS), RAWCAIR (mode CAIR), RAW16 (mode PADAT).
  // Delta RAW = RAW dengan acuan dikurangi RAW tanpa beban/tekanan.
  // Baca tanpa parameter untuk melihat preset; isi parameter untuk menyimpan.
  // Preset GAS/CAIR memakai tekanan gauge KAL_TEKANAN_KPA.
  int modePreset = -1;
  String namaPreset;
  if (cmd == "RAWGAS" || cmd.startsWith("RAWGAS ")) {
    modePreset = 1;
    namaPreset = "RAWGAS";
  } else if (cmd == "RAWCAIR" || cmd.startsWith("RAWCAIR ")) {
    modePreset = 0;
    namaPreset = "RAWCAIR";
  } else if (cmd == "RAW16" || cmd.startsWith("RAW16 ")) {
    modePreset = 2;
    namaPreset = "RAW16";
  }
  if (modePreset >= 0) {
    const int m = modePreset;
    const bool ubah = cmd.length() > namaPreset.length();
    if (!ubah) {
      const float delta = kalDeltaMode(m);
      if (!kalDeltaValid(delta)) {
        Serial.printf("%s BELUM DIISI. Ukur delta RAW dengan acuan %.2f %s.\n",
                      namaPreset.c_str(), kalAcuanMode(m),
                      m == 2 ? "kg" : "kPa gauge");
      } else {
        Serial.printf(
            "%s: acuan=%.4f %s, delta=%+.1f count, skala=%+.10g %s/count.\n",
            namaPreset.c_str(), kalAcuanMode(m), m == 2 ? "kg" : "kPa gauge",
            delta, kalAcuanMode(m) / delta, m == 2 ? "kg" : "kPa");
      }
      Serial.printf("Untuk menyimpan: %s <delta_signed>\n", namaPreset.c_str());
      return;
    }
    const String teks = cmd.substring(namaPreset.length() + 1);
    const float baru = teks.toFloat();
    if (!kalDeltaValid(baru)) {
      Serial.printf(
          "PRESET GAGAL: nilai harus signed, |delta| %.0f..%.0f count.\n",
          KAL_MIN_BEDA_RAW, KAL_MAKS_BEDA_RAW);
      return;
    }
    // Gunakan key baru agar data V7.29 (referensi 1.76 kPa) tidak ikut
    // terpakai.
    const char *key = m == 0 ? "dcair103" : m == 1 ? "dgas103" : "d16r30";
    const size_t tulis = prefs.putFloat(key, baru);
    const float baca = prefs.getFloat(key, NAN);
    if (tulis == sizeof(float) && isfinite(baca) &&
        fabsf(baca - baru) <= fmaxf(0.01f, fabsf(baru) * 0.000001f)) {
      if (m == 0)
        kalDeltaCairRaw = baru;
      else if (m == 1)
        kalDeltaGasRaw = baru;
      else
        kalDelta16Raw = baru;
      Serial.printf("PRESET TERSIMPAN [%s]: delta=%+.1f count, acuan=%.4f %s. "
                    "PREV saat sensor tanpa beban/tekanan.\n",
                    names[m], baru, kalAcuanMode(m),
                    m == 2 ? "kg" : "kPa gauge");
    } else {
      Serial.println(
          "GAGAL SIMPAN PRESET KE NVS; preset sebelumnya tidak diubah.");
    }
    return;
  }
  if (cmd == "RAW1" || cmd == "RAW2" || cmd.startsWith("RAW1 ") ||
      cmd.startsWith("RAW2 ")) {
    Serial.println("PERINTAH LAMA: gunakan RAWGAS atau RAWCAIR sesuai sensor, "
                   "bukan RAW1/RAW2.");
    return;
  }
  // Kurva BALON: volume pada OLED hanya memakai kalibrasi P-V HX710B.
  // BALONZERO dibuat saat balon KOSONG, titik awal volume = 0 L.
  if (cmd == "BALONZERO") {
    if (mode != 1 || page == WELCOME || page == HOME) {
      Serial.println("Pilih dashboard ZAT GAS terlebih dahulu.");
    } else if (balonRekamNol()) {
      Serial.printf("BALONZERO: P0 gauge = %.2f Pa, V balon = 0.00000 m3. "
                    "Lanjut BALONCAL <diameter_cm>.\n",
                    keluaranPa(balonPKPa[0]));
    } else
      Serial.println("GAGAL: HX710B belum siap/terkalibrasi. Cek Z2 dan C2 "
                     "dengan referensi tekanan nyata.");
    return;
  }
  if (cmd.startsWith("BALONCAL ")) {
    float d = cmd.substring(9).toFloat();
    if (mode != 1 || page == WELCOME || page == HOME) {
      Serial.println("Pilih dashboard GAS terlebih dahulu.");
    } else if (!isfinite(d) || d < 1.0f || d > 45.0f) {
      Serial.println("Format BALONCAL <diameter_cm>; ukur diameter balon saat "
                     "itu. Contoh BALONCAL 5.35");
    } else {
      float r = d * 0.005f;
      float v = (4.0f / 3.0f) * PI * r * r * r * 1000.0f;
      if (balonRekamTitik(v)) {
        Serial.printf(
            "BALONCAL: D=%.2f cm, V=%.7f m3, P=%.2f Pa, titik=%u/%u.\n", d,
            keluaranM3(v), keluaranPa(gasGaugeSignedKPa()), balonJumlahTitik,
            BALON_MAX_TITIK);
      } else
        Serial.println(
            "BALONCAL gagal: jalankan BALONZERO dulu, pastikan tekanan berbeda "
            "dan volume bertambah searah tekanan; cek BALONSTATE.");
    }
    return;
  }
  if (cmd.startsWith("BALONM3 ") || cmd.startsWith("BALONV ")) {
    const bool dalamM3 = cmd.startsWith("BALONM3 ");
    const float v = cmd.substring(dalamM3 ? 8 : 7).toFloat();
    const float volumeL =
        dalamM3 ? v * 1000.0f : v; // BALONV lama tetap menerima liter.
    if (mode != 1 || page == WELCOME || page == HOME)
      Serial.println("Pilih dashboard GAS terlebih dahulu.");
    else if (balonRekamTitik(volumeL)) {
      Serial.printf("Volume acuan %.7f m3 tersimpan saat P gauge %.2f Pa.\n",
                    keluaranM3(volumeL), keluaranPa(gasGaugeSignedKPa()));
    } else {
      Serial.println(
          "Volume acuan gagal. BALONM3 <m3> atau BALONV <liter>; lakukan "
          "BALONZERO, lalu tambah titik P-V yang meningkat.");
    }
    return;
  }
  if (cmd == "BALONRESET") {
    balonHapusKurva();
    saveSettings();
    Serial.println("Kurva P-V balon dihapus. HX710B, DHT, pengaturan "
                   "gas/cair/padat tidak dihapus.");
    return;
  }
  if (cmd == "BALONSTATE") {
    Serial.printf(
        "V BALON kurva P-V | Titik=%u/%u | P gauge=%.2f Pa | V balon=%.7f m3\n",
        balonJumlahTitik, BALON_MAX_TITIK, keluaranPa(gasGaugeSignedKPa()),
        keluaranM3(volumeGasDinamisL()));
    for (uint8_t i = 0; i < balonJumlahTitik; ++i)
      Serial.printf("  TITIK %u: P gauge=%.2f Pa -> V balon=%.7f m3\n", i,
                    keluaranPa(balonPKPa[i]), keluaranM3(balonVolumeL[i]));
    if (!balonJumlahTitik)
      Serial.println("Belum ada data. Pilih GAS, kalibrasikan HX710B, lalu "
                     "BALONZERO dan BALONCAL <diameter_cm>.");
    if (balonJumlahTitik == 1)
      Serial.println("Nol OK: isi ke D0, tutup katup, tekan PREV 2. "
                     "Alternatif: BALONCAL atau BALONM3.");
    Serial.println("P di luar kurva -> V=--. Model berlaku hanya untuk "
                   "balon/suhu/proses kalibrasi yang serupa.");
    return;
  }
  // Mode GAS: n masih tersedia untuk PERHITUNGAN IDEAL DIAGNOSTIK,
  // tetapi TIDAK menentukan volume balon yang tampak di OLED.
  if (cmd.startsWith("N ")) {
    float n = cmd.substring(2).toFloat();
    if (setGasManualMoles(n))
      Serial.printf("n manual=%.6f mol tersimpan. Model V=nRT/Pabs "
                    "(HX710B+PATM, DHT22 suhu).\n",
                    molGas);
    else
      Serial.println("Format N <mol>, 0 < n <= 10. Contoh: N 0.081 (HANYA jika "
                     "n diketahui).");
    return;
  }
  // Tekanan atmosfer acuan dapat diatur tanpa memengaruhi kalibrasi sensor
  // lain.
  if (cmd.startsWith("PATM ")) {
    const float nilaiBaru = cmd.substring(5).toFloat();
    if (isfinite(nilaiBaru) && nilaiBaru >= 50.0f && nilaiBaru <= 120.0f) {
      if (fabsf(tekananAtmosferKPa - nilaiBaru) > 0.0001f && gasBaselineValid)
        clearGasBaseline(); // baseline mol dari Pabs lama harus diulang
      tekananAtmosferKPa = nilaiBaru;
      saveSettings();
      Serial.printf(
          "P atmosfer acuan = %.2f Pa (PATM tetap diinput dalam kPa).\n",
          keluaranPa(tekananAtmosferKPa));
    } else
      Serial.println("Format: PATM <kPa>, rentang 50..120. Contoh PATM 101.325 "
                     "jika terukur.");
    return;
  }
  if (cmd.startsWith("D0 ")) {
    float d = cmd.substring(3).toFloat();
    if (isfinite(d) && d > 0 && d <= 200) {
      diameterBalonCm = d;
      if (gasBaselineValid)
        clearGasBaseline(); // Hanya acuan otomatis yang bergantung D0.
      saveSettings();
      Serial.printf("Diameter acuan %.2f cm; V acuan %.7f m3. Dipakai PREV 2 "
                    "atau GASBASE.\n",
                    d, keluaranM3(volumeBalonL()));
    } else
      Serial.println("Format D0 <diameter_awal_cm>, nilai 0..200 cm.");
    return;
  }
  if (cmd == "GASBASE") {
    if (mode != 1 || page == WELCOME || page == HOME)
      Serial.println("Pilih mode ZAT GAS dahulu.");
    else if (captureInitialMoles())
      Serial.println("Baseline baru disimpan: Pabs0, T0, V0, dan estimasi n "
                     "(asumsi balon bola).");
    else
      Serial.println(
          "Gagal: cek Z2/C2 HX710B, suhu DHT22, D0, dan tekanan absolut.");
    return;
  }
  if (cmd == "GASRESET") {
    clearGasBaseline();
    saveSettings();
    Serial.println("Acuan gas dihapus. Isi D0 dan GASBASE untuk mulai lagi.");
    return;
  }
  if (cmd == "GASSTATE") {
    Serial.print("HX710B P_gauge=");
    cetakNilaiSerial(keluaranPa(gasKPa()));
    Serial.print(" Pa | PATM=");
    cetakNilaiSerial(keluaranPa(tekananAtmosferKPa));
    Serial.print(" Pa | P_abs=");
    cetakNilaiSerial(keluaranPa(gasPAbsKPa()));
    Serial.println(" Pa");
    Serial.print("DHT22 T=");
    cetakNilaiSerial(keluaranKelvin(airTempC));
    Serial.print(" K | RH=");
    cetakNilaiSerial(kelembapanDht);
    Serial.printf(" %% | HX710B kalibrasi=%s | D0=%.2f cm\n",
                  (scaleGas != 0 && gasOK) ? "YA" : "BELUM", diameterBalonCm);
    Serial.print("n ESTIMASI KURVA=");
    cetakNilaiSerial(gasMolDariKurva(), 6U);
    Serial.println(" mol");
    if (gasBaselineValid)
      Serial.printf(
          "n BASELINE=%.6f mol | Pabs0=%.2f Pa, T0=%.2f K, V0=%.7f m3\n",
          molGas, keluaranPa(gasP0KPa), gasT0K, keluaranM3(gasV0L));
    else if (gasManualMolActive)
      Serial.printf("n MANUAL=%.6f mol\n", molGas);
    else
      Serial.println("n ACUAN belum disetel; D0 + GASBASE atau N <mol> "
                     "tersedia untuk diagnostik.");
    Serial.printf("V BALON untuk OLED (kurva P-V): %.7f m3 (NAN: belum "
                  "kalibrasi/di luar rentang)\n",
                  keluaranM3(volumeGasDinamisL()));
    return;
  }
  // Pemeriksaan empat jarak tanpa kalibrasi geometri lama.
  if (cmd == "USCHECK" || cmd == "US") {
    profilShow();
    return;
  }
  if (cmd == "USHELP") {
    profilHelp();
    return;
  }
  if (cmd == "USSTART" || cmd == "USEMPTY" || cmd == "USCALRESET" ||
      cmd == "US2RESET" || cmd.startsWith("REF ") || cmd.startsWith("USCAL ") ||
      cmd.startsWith("USVERIFY ") || cmd.startsWith("USPOINT") ||
      cmd.startsWith("AUTO ") || cmd.startsWith("AREA ")) {
    Serial.println("Kalibrasi ultrasonik lama DIHAPUS. Gunakan EMPTY, NAME, "
                   "LEARN, LIST, CHECK, SHOW.");
    return;
  }
  if (cmd == "RESETCAL") {
    resetCalibration("ALL");
    return;
  }
  if (cmd == "RESETCAIR") {
    resetCalibration("CAIR");
    return;
  }
  if (cmd == "RESETGAS") {
    resetCalibration("GAS");
    return;
  }
  if (cmd == "RESETLOAD") {
    resetCalibration("LOAD");
    return;
  }
  if (cmd == "SCAN") {
    scanI2C();
    return;
  }
  if (cmd == "DHT" || cmd == "DHTDEBUG") {
    diagnostikDHT();
    return;
  }
  if (cmd == "BMP" || cmd == "BMPDEBUG") {
    Serial.println("BMP280 sudah diganti DHT22. Gunakan DHTDEBUG.");
    return;
  }
  if (cmd == "Z1" && cairOK && filterCair.ready()) {
    zeroCair = lroundf(filterCair.value);
    scaleCair = 0;
    saveSettings();
    Serial.println("Nol cair OK");
  } else if (cmd == "Z2" && gasOK && filterGasHx.ready()) {
    zeroGas = lroundf(filterGasHx.value);
    scaleGas = 0;
    balonHapusKurva();
    if (gasBaselineValid)
      clearGasBaseline();
    saveSettings();
    Serial.println(
        "Nol gas OK; kalibrasi C2 diperlukan lagi, kurva balon direset");
  } else if (cmd == "ZL" && loadOK && filterLoad.ready()) {
    zeroLoad = lroundf(filterLoad.value);
    saveSettings();
    Serial.println("Tare OK");
  } else if (cmd.startsWith("C1 ") && cairOK && filterCair.ready()) {
    float ref = cmd.substring(3).toFloat();
    float delta = filterCair.value - zeroCair;
    if (ref > 0 && delta != 0) {
      scaleCair = ref / (float)delta;
      saveSettings();
      Serial.println("Skala cair OK");
    } else
      Serial.println("C1 gagal: referensi / delta tidak valid");
  } else if (cmd.startsWith("C2 ") && gasOK && filterGasHx.ready()) {
    float ref = cmd.substring(3).toFloat();
    float delta = filterGasHx.value - zeroGas;
    if (ref > 0 && delta != 0) {
      scaleGas = ref / (float)delta;
      balonHapusKurva();
      if (gasBaselineValid)
        clearGasBaseline();
      saveSettings();
      Serial.println("Skala gas OK; kurva balon direset");
    } else
      Serial.println("C2 gagal: referensi / delta tidak valid");
  } else if (cmd.startsWith("L ") && loadOK && filterLoad.ready()) {
    float ref = cmd.substring(2).toFloat();
    float delta = filterLoad.value - zeroLoad;
    if (ref > 0 && delta != 0) {
      scaleLoad = ref / (float)delta;
      saveSettings();
      Serial.println("Skala load cell OK");
    } else
      Serial.println("L gagal: referensi / delta tidak valid");
  } else
    Serial.println("Perintah tidak dikenal/sensor belum siap. Pilih mode "
                   "sensor dahulu (CAIR/GAS/PADAT).");
}

// ===== MONITORING MQTT (TANPA MENGUBAH OLED) =====
// Satu pesan JSON dikirim berkala ke topik: tekanan/<ID_ALAT>/data
// Satuan: tekanan Pa, suhu K, volume m3, massa g, luas cm2, tinggi cm, gaya N,
// n mol. Hanya field milik mode aktif yang dikirim. Nilai tidak valid dikirim
// null. Status alat: tekanan/<ID_ALAT>/status = "online" / "offline" (retained,
// LWT).
static const unsigned long MQTT_KIRIM_INTERVAL_MS = 2000UL;
static const unsigned long MQTT_COBA_KONEKSI_MS = 5000UL;
static const unsigned long WIFI_COBA_ULANG_MS = 10000UL;
static WiFiClient mqttWifi;
static PubSubClient mqtt(mqttWifi);
static char topikData[48];
static char topikStatus[48];
static char topikPerintah[48];
static unsigned long mqttTerakhirKirim = 0;
static unsigned long mqttTerakhirCoba = 0;
static unsigned long wifiTerakhirCoba = 0;
static bool mqttStatusOnlineTerkirim = false;

void kirimMqtt();

void terimaPerintahMqtt(char *topic, byte *payload, unsigned int length) {
  if (length == 0 || length > 32)
    return;
  char buf[36];
  memcpy(buf, payload, length);
  buf[length] = '\0';
  String cmd = String(buf);
  cmd.trim();
  cmd.toUpperCase();

  int modeBaru = -1;
  if (cmd == "MODE:0" || cmd == "CAIR")
    modeBaru = 0;
  else if (cmd == "MODE:1" || cmd == "GAS")
    modeBaru = 1;
  else if (cmd == "MODE:2" || cmd == "PADAT")
    modeBaru = 2;

  if (modeBaru >= 0 && modeBaru <= 2) {
    const bool ganti = (mode != modeBaru) || (page == WELCOME || page == HOME);
    mode = modeBaru;
    homeSelection = selectedHomeFromMode(mode);
    detailIndex = 0;
    if (page == WELCOME || page == HOME)
      page = MEASURE;
    if (ganti) {
      resetModeReadings();
      profilResetTracking();
    }
    Serial.printf("MQTT PERINTAH: pindah ke mode %s\n", names[mode]);
    kirimMqtt();
  } else if (cmd == "MENU" || cmd == "HOME") {
    goToModeSelection();
    resetModeReadings();
    kirimMqtt();
  }
}

static void jsonAngka(String &s, const char *kunci, float nilai,
                      unsigned int desimal) {
  s += ",\"";
  s += kunci;
  s += "\":";
  if (isfinite(nilai))
    s += String(nilai, desimal);
  else
    s += "null";
}

void mulaiMqtt() {
  snprintf(topikData, sizeof(topikData), "tekanan/%s/data", ID_ALAT);
  snprintf(topikStatus, sizeof(topikStatus), "tekanan/%s/status", ID_ALAT);
  snprintf(topikPerintah, sizeof(topikPerintah), "tekanan/%s/perintah",
           ID_ALAT);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS); // Tidak menunggu jaringan (non-blocking).
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(terimaPerintahMqtt);
  mqtt.setBufferSize(640);
  mqtt.setSocketTimeout(2);
  Serial.printf("MQTT: broker %s:%u | topik data: %s\n", MQTT_HOST,
                (unsigned)MQTT_PORT, topikData);
}

void kirimMqtt() {
  String j = "{";
  if (page == HOME || page == WELCOME) {
    j += "\"mode\":-1,\"mode_nama\":\"MENU\"";
  } else {
    j += "\"mode\":" + String(mode);
    j += ",\"mode_nama\":\"" + String(names[mode]) + "\"";
    jsonAngka(j, "p_pa", keluaranPa(modeKPa()), 1);
    if (mode == 0) {
      const float pPa = keluaranPa(liquidKPa());
      jsonAngka(j, "p_cair_pa", pPa, 1);
      float hCm = NAN;
      if (isfinite(pPa) && isfinite(rho) && rho > 0.0f)
        hCm = pPa / (rho * G) * 100.0f;
      jsonAngka(j, "tinggi_cm", hCm, 2);
      jsonAngka(j, "rho", rho, 0);
    } else if (mode == 1) {
      jsonAngka(j, "p_gauge_pa", keluaranPa(gasKPa()), 1);
      jsonAngka(j, "p_abs_pa", keluaranPa(gasPAbsKPa()), 1);
      jsonAngka(j, "suhu_k", keluaranKelvin(airTempC), 2);
      jsonAngka(j, "rh", kelembapanDht, 1);
      jsonAngka(j, "volume_m3", keluaranM3(volumeGasDinamisL()), 7);
      jsonAngka(j, "n_mol", gasMolDariKurva(), 6);
    } else {
      const float gayaN = forceN();
      jsonAngka(j, "p_padat_pa", keluaranPa(solidKPa()), 1);
      jsonAngka(j, "gaya_n", gayaN, 3);
      jsonAngka(j, "massa_g", isfinite(gayaN) ? gayaN / G * 1000.0f : NAN, 1);
      jsonAngka(j, "luas_cm2", areaDigunakanCm2(), 2);
    }
  }
  j += "}";
  mqtt.publish(topikData, j.c_str());
}

void layananMqtt() {
  const unsigned long now = millis();
  if (WiFi.status() != WL_CONNECTED) {
    mqttStatusOnlineTerkirim = false;
    if (now - wifiTerakhirCoba >= WIFI_COBA_ULANG_MS) {
      wifiTerakhirCoba = now;
      WiFi.reconnect();
      Serial.println("WIFI: mencoba ulang koneksi (OLED tetap berjalan).");
    }
    return;
  }

  if (!mqtt.connected()) {
    mqttStatusOnlineTerkirim = false;
    if (mqttTerakhirCoba == 0 ||
        now - mqttTerakhirCoba >= MQTT_COBA_KONEKSI_MS) {
      mqttTerakhirCoba = now;
      String idKlien = String("tekanan-") + ID_ALAT + "-" +
                       String((uint32_t)(ESP.getEfuseMac() >> 24), HEX);
      if (mqtt.connect(idKlien.c_str(), NULL, NULL, topikStatus, 0, true,
                       "offline")) {
        mqtt.publish(topikStatus, "online", true);
        mqtt.subscribe(topikPerintah);
        mqttStatusOnlineTerkirim = true;
        mqttTerakhirKirim = 0;
        Serial.println("MQTT: ONLINE, data sensor siap dikirim.");
      } else {
        Serial.printf("MQTT: gagal tersambung (kode %d), coba lagi.\n",
                      mqtt.state());
      }
    }
    return;
  }

  mqtt.loop();
  if (mqttTerakhirKirim == 0 ||
      now - mqttTerakhirKirim >= MQTT_KIRIM_INTERVAL_MS) {
    mqttTerakhirKirim = now;
    kirimMqtt();
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(150);
  pinMode(BTN_NEXT, INPUT_PULLUP);
  pinMode(BTN_PREV, INPUT_PULLUP);
  pinMode(BTN_SELECT, INPUT_PULLUP);
  pinMode(CAIR_OUT, INPUT);
  pinMode(GAS_OUT, INPUT);
  pinMode(CAIR_SCK, OUTPUT);
  pinMode(GAS_SCK, OUTPUT);
  digitalWrite(CAIR_SCK, LOW);
  digitalWrite(GAS_SCK, LOW);
  for (int i = 0; i < 4; i++) {
    pinMode(US_TRIG[i], OUTPUT);
    digitalWrite(US_TRIG[i], LOW);
    pinMode(US_ECHO[i], INPUT);
  }
  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(100000);
  oled.setBusClock(100000);
  oled.setI2CAddress(0x3C * 2);
  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(8, 18, "ALAT UKUR TEKANAN");
  oled.drawStr(12, 36, "SIAP UNTUK MULAI");
  oled.sendBuffer();
  prefs.begin("pressure", false);
  loadSettings();
  profilNvsSiap = prefsProfil.begin("prof3_us", false);
  if (!profilNvsSiap)
    Serial.println(
        "PERINGATAN: NVS profil gagal dibuka. Jangan LEARN sebelum normal.");
  profilLoad();
  // Sensor lain belum diukur. Scan I2C manual melalui perintah SCAN.
  // DHT22 diinisialisasi satu kali, bahkan sebelum WiFi dimulai.
  // Pembacaan periodik hanya berlangsung saat mode GAS aktif.
  dht.begin();
  Serial.printf("DHT22: DATA GPIO%d | VCC 3V3 | pembacaan tiap %lu ms\n",
                DHT_PIN, DHT_INTERVAL_MS);
  loadcell.begin(HX711_DT, HX711_SCK);
  Serial.println("EDUKIT V7.31 GAS DUA PREV | P Pa, T K");
  Serial.printf(
      "4 sonar + HX711: hybrid adaptif; toleransi +/-%.2f cm per sensor.\n",
      PROF_TOLERANSI_CM);
  Serial.println("Perintah profil: HELP, NVSDEBUG, EMPTY, NAME, LEARN, CHECK, "
                 "SHOW, LIST, CLEAR.");
  Serial.println("Geometri pakai REF=12cm; profil lama tanpa massa wajib LEARN "
                 "ulang. Kalibrasi cair/gas/load tetap.");
  Serial.println("Kalibrasi tekanan: C1/C2/PATM masuk kPa, L masuk kg.");
  Serial.println("GAS: set D0 <cm> sekali. PREV 1 nol P/V (10 s); PREV 2 rekam "
                 "di D0, katup tutup (3 s).");
  Serial.printf("Preset RAW16 16000 untuk 16g; RAWCAIR/RAWGAS bila perlu "
                "memakai %.3f kPa gauge.\n",
                KAL_TEKANAN_KPA);
  Serial.println(
      "PREV CAIR/PADAT: tunggu 10 detik tanpa beban atau tekanan tambahan.");
  Serial.println(
      "MQTT: data JSON dikirim ke tekanan/<ID_ALAT>/data (Pa, K, m3).");
  Serial.println(
      "Perintah suhu: DHTDEBUG (atau DHT). DHT22 tidak muncul di SCAN I2C.");
  // LANDING tampil langsung setelah setup, tanpa delay tambahan.
  mulaiMqtt(); // WiFi non-blocking, tidak mengubah menu/OLED.
}

void loop() {
  evNext = evPrev = evSel = evLong = false;
  updateButton(nextBtn, evNext);
  updateButton(prevBtn, evPrev);
  updateButton(selBtn, evSel, &evLong);
  const int oldMode = mode;
  const Page oldPage = page;
  navigate();
  if (oldMode != mode || (oldPage == HOME && page == MEASURE)) {
    resetModeReadings();
    profilResetTracking();
    Serial.printf("Mode aktif: %s. Memulai pembacaan sensor mode ini.\n",
                  names[mode]);
  } else if (oldPage != HOME && page == HOME) {
    // Jangan menggunakan data lama setelah kembali ke pemilihan jenis tekanan.
    resetModeReadings();
  }
  readSensorsByMode();
  kalLayananCepat();
  serialCommands();
  layananMqtt();
  static unsigned long drawTick = 0, serialTick = 0;
  unsigned long now = millis();
  if (now - drawTick >= 150) {
    drawTick = now;
    drawScreen();
  }
  if (now - serialTick >= 1000UL) {
    serialTick = now;
    if (page == HOME || page == WELCOME)
      return;

    if (mode == 0) {
      Serial.print("CAIR | HX710_RAW=");
      if (cairOK)
        Serial.print(rawCair);
      else
        Serial.print("--");
      Serial.print(" count | HX710_FILTER=");
      if (cairOK && filterCair.ready())
        cetakNilaiSerial(filterCair.value, 0U);
      else
        Serial.print("--");
      Serial.print(" count | P=");
      cetakNilaiSerial(keluaranPa(liquidKPa()));
      Serial.println(" Pa");
    } else if (mode == 1) {
      Serial.print("GAS | HX710_RAW=");
      if (gasOK)
        Serial.print(rawGas);
      else
        Serial.print("--");
      Serial.print(" count | HX710_FILTER=");
      if (gasOK && filterGasHx.ready())
        cetakNilaiSerial(filterGasHx.value, 0U);
      else
        Serial.print("--");
      Serial.print(" count | P_gauge=");
      cetakNilaiSerial(keluaranPa(gasKPa()));
      Serial.print(" Pa | P_abs=");
      cetakNilaiSerial(keluaranPa(gasPAbsKPa()));
      Serial.print(" Pa | DHT_T_SENSOR=");
      cetakNilaiSerial(keluaranKelvin(suhuDhtSensorC));
      Serial.print(" K | T_FILTER=");
      cetakNilaiSerial(keluaranKelvin(airTempC));
      Serial.print(" K | RH=");
      cetakNilaiSerial(kelembapanDht);
      Serial.print(" % | V_balon=");
      cetakNilaiSerial(keluaranM3(volumeGasDinamisL()), 7U);
      Serial.print(" m3 | n_estimasi=");
      cetakNilaiSerial(gasMolDariKurva(), 6U);
      Serial.println(" mol");
    } else {
      Serial.print("PADAT | HX711_RAW=");
      if (loadOK)
        Serial.print(rawLoad);
      else
        Serial.print("--");
      Serial.print(" count | HX711_FILTER=");
      if (loadOK && filterLoad.ready())
        cetakNilaiSerial(filterLoad.value, 0U);
      else
        Serial.print("--");
      const float gaya = forceN();
      Serial.print(" count | Massa=");
      cetakNilaiSerial(isfinite(gaya) ? gaya / G * 1000.0f : NAN);
      Serial.print(" g | Gaya=");
      cetakNilaiSerial(gaya);
      Serial.println(" N");
      for (int i = 0; i < 4; i++) {
        const bool segar = (now - waktuSonar[i] <= PROF_USIA_MS);
        Serial.printf("  US%d | RAW=", i + 1);
        cetakNilaiSerial(segar ? jarakSonarRaw[i] : NAN);
        Serial.print(" cm | FILTER=");
        cetakNilaiSerial(segar ? jarakSonarHalus[i] : NAN);
        Serial.println(" cm");
      }
      // Luas hybrid: geometri bila dekat profil, koreksi luas profil jika
      // menyimpang.
      const float luas = areaDigunakanCm2();
      const float pPa = keluaranPa(solidKPa());
      const float d1 = jarakSonarHalus[0], d2 = jarakSonarHalus[1];
      const float d3 = jarakSonarHalus[2], d4 = jarakSonarHalus[3];
      float pUS = 12.0f - (d1 + d2), lUS = 12.0f - (d3 + d4);
      float aUS = (isfinite(pUS) && isfinite(lUS) && pUS > 0 && lUS > 0)
                      ? pUS * lUS
                      : NAN;
      Serial.print("  GEOMETRI US | P=");
      cetakNilaiSerial(pUS);
      Serial.print(" cm | L=");
      cetakNilaiSerial(lUS);
      Serial.print(" cm | A_US=");
      cetakNilaiSerial(aUS);
      Serial.println(" cm2");
      Serial.print("  HYBRID | A_PAKAI=");
      cetakNilaiSerial(luas);
      Serial.print(" cm2 | P=");
      cetakNilaiSerial(pPa);
      Serial.print(" Pa | SUMBER=");
      Serial.print(hybridSumberLuas);
      Serial.print(" | MASSA_G=");
      cetakNilaiSerial(hybridMassaSaatIniGram());
      Serial.print(" | STATUS=");
      Serial.print(profilStatus);
      if (profilDipilih >= 0) {
        Serial.print(" [");
        Serial.print(profilBenda[profilDipilih].nama);
        Serial.print("]");
      }
      Serial.println();
    }
  }
}
