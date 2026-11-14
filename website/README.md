# Website Monitoring Tekanan — The 4 Sense Burden

Versi web dari `aplikasi_tekanan` untuk memantau data sensor ESP32 secara real-time melalui **MQTT over WebSocket**.

## Cara Menjalankan Lokal
Anda bisa langsung membuka `index.html` di browser, atau menjalankan server lokal dari folder `website/`:

```powershell
npx serve .
```
atau dengan Python:
```powershell
python -m http.server 8080
```
Lalu buka `http://localhost:8080` (atau port yang ditampilkan).

## Fitur Utama
- **Dashboard Live:** Kartu metrik & rumus fisika untuk mode **Zat Padat**, **Zat Cair**, dan **Zat Gas**, lengkap dengan statistik Min/Avg/Max dan grafik real-time (`1m`, `5m`, `10m`).
- **Kontrol Mode ESP32:** Mengirim perintah `MODE:0` / `MODE:1` / `MODE:2` ke topik `tekanan/<idAlat>/perintah`.
- **Mode Simulasi:** Klik tombol **Simulasi: OFF** di sidebar untuk menguji tampilan, grafik, dan ekspor CSV tanpa perangkat ESP32 terhubung.
- **Praktikum & Riwayat:** Rekam sesi praktikum dan unduh data sebagai file `.csv`.
- **Pengaturan:** Konfigurasi broker MQTT WebSocket (`wss://broker.hivemq.com:8884/mqtt`), ID alat, satuan tekanan (`kPa`, `Pa`, `bar`), satuan suhu (`°C`, `K`), dan mode terang/gelap.

