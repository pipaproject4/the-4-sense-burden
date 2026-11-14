(() => {
  'use strict';

  const STORAGE_KEY_CFG = '4sb_web_config_v1';
  const STORAGE_KEY_SESI = '4sb_web_sesi_v1';
  const MAX_RIWAYAT = 300;

  const DEFAULT_CONFIG = {
    host: 'broker.hivemq.com',
    protocol: 'wss',
    port: 8884,
    path: '/mqtt',
    idAlat: 'alat01',
    satuanTekanan: 'kPa',
    satuanSuhu: '°C',
    tema: 'light',
  };

  const MODE_INFO = {
    2: { nama: 'Zat Padat', keyTekanan: ['p_padat_pa', 'p_pa'] },
    0: { nama: 'Zat Cair', keyTekanan: ['p_cair_pa', 'p_pa'] },
    1: { nama: 'Zat Gas', keyTekanan: ['p_gauge_pa', 'p_pa'] },
  };

  const state = {
    config: loadConfig(),
    mode: 1, // 2=Padat, 0=Cair, 1=Gas
    rangeMenit: 1,
    mqttStatus: 'offline', // offline | connecting | online
    espOnline: false,
    simulasiAktif: false,
    simulasiTimer: null,
    client: null,
    riwayat: [], // { waktu: Date, data: {...} }
    terakhirPerMode: { 0: null, 1: null, 2: null },
    terakhir: null,
    merekam: false,
    sampelRekam: [],
    sesiTersimpan: loadSesi(),
    chart: null,
  };

  // --- DOM Helpers ---
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  function loadConfig() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_CFG);
      return raw ? { ...DEFAULT_CONFIG, ...JSON.parse(raw) } : { ...DEFAULT_CONFIG };
    } catch {
      return { ...DEFAULT_CONFIG };
    }
  }

  function saveConfig() {
    localStorage.setItem(STORAGE_KEY_CFG, JSON.stringify(state.config));
  }

  function loadSesi() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_SESI);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  }

  function saveSesi() {
    localStorage.setItem(STORAGE_KEY_SESI, JSON.stringify(state.sesiTersimpan));
  }

  // --- Konversi Satuan (selaras dengan mqtt_service.dart) ---
  function konversiTekanan(pa) {
    if (pa == null || Number.isNaN(pa)) return null;
    if (state.config.satuanTekanan === 'Pa') return pa;
    if (state.config.satuanTekanan === 'bar') return pa / 100000;
    return pa / 1000;
  }

  function formatTekanan(pa) {
    const val = konversiTekanan(pa);
    if (val == null) return '--';
    const dec = state.config.satuanTekanan === 'Pa' ? 1 : state.config.satuanTekanan === 'bar' ? 4 : 2;
    return val.toFixed(dec);
  }

  function konversiSuhu(kelvin) {
    if (kelvin == null || Number.isNaN(kelvin)) return null;
    if (state.config.satuanSuhu === 'K') return kelvin;
    return kelvin - 273.15;
  }

  function formatSuhu(kelvin) {
    const val = konversiSuhu(kelvin);
    return val == null ? '--' : val.toFixed(1);
  }

  function ambilAngka(pembacaan, keys) {
    if (!pembacaan || !pembacaan.data) return null;
    const list = Array.isArray(keys) ? keys : [keys];
    for (const k of list) {
      const v = Number(pembacaan.data[k]);
      if (pembacaan.data[k] !== undefined && !Number.isNaN(v)) return v;
    }
    return null;
  }

  function hitungStatistik(mode, keys, transform = (v) => v, desimal = 2) {
    const vals = [];
    for (const item of state.riwayat) {
      if (Number(item.data.mode) === mode) {
        const raw = ambilAngka(item, keys);
        if (raw != null) vals.push(transform(raw));
      }
    }
    if (vals.length === 0) return null;
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const avg = vals.reduce((a, b) => a + b, 0) / vals.length;
    return {
      min: min.toFixed(desimal),
      max: max.toFixed(desimal),
      avg: avg.toFixed(desimal),
    };
  }

  // --- Spesifikasi Kartu Per Mode ---
  function getKartuSpecs(mode) {
    const pUnit = state.config.satuanTekanan;
    const pDec = pUnit === 'Pa' ? 1 : pUnit === 'bar' ? 4 : 2;
    const sumber = state.terakhirPerMode[mode] || (state.terakhir?.data?.mode === mode ? state.terakhir : null);

    if (mode === 2) {
      const pPa = ambilAngka(sumber, ['p_padat_pa', 'p_pa']);
      const gaya = ambilAngka(sumber, 'gaya_n');
      const luas = ambilAngka(sumber, 'luas_cm2');
      const massa = ambilAngka(sumber, 'massa_g');
      return [
        {
          judul: 'Tekanan Zat Padat',
          nilai: formatTekanan(pPa),
          satuan: pUnit,
          rumus: 'P = F / A',
          stat: hitungStatistik(2, ['p_padat_pa', 'p_pa'], konversiTekanan, pDec),
        },
        {
          judul: 'Gaya Tekan (F)',
          nilai: gaya != null ? gaya.toFixed(2) : '--',
          satuan: 'N',
          rumus: 'F = m · g',
          stat: hitungStatistik(2, 'gaya_n', (v) => v, 2),
        },
        {
          judul: 'Luas Bidang (A)',
          nilai: luas != null ? luas.toFixed(2) : '--',
          satuan: 'cm²',
          rumus: 'A = luas kontak',
          stat: hitungStatistik(2, 'luas_cm2', (v) => v, 2),
        },
        {
          judul: 'Massa Beban (m)',
          nilai: massa != null ? massa.toFixed(1) : '--',
          satuan: 'g',
          rumus: 'Load Cell',
          stat: hitungStatistik(2, 'massa_g', (v) => v, 1),
        },
      ];
    }

    if (mode === 0) {
      const pPa = ambilAngka(sumber, ['p_cair_pa', 'p_pa']);
      const tinggi = ambilAngka(sumber, 'tinggi_cm');
      const rho = ambilAngka(sumber, 'rho') ?? (sumber ? 1000 : null);
      return [
        {
          judul: 'Tekanan Hidrostatis',
          nilai: formatTekanan(pPa),
          satuan: pUnit,
          rumus: 'P = ρ · g · h',
          stat: hitungStatistik(0, ['p_cair_pa', 'p_pa'], konversiTekanan, pDec),
        },
        {
          judul: 'Kedalaman (h)',
          nilai: tinggi != null ? tinggi.toFixed(1) : '--',
          satuan: 'cm',
          rumus: 'Sensor kedalaman',
          stat: hitungStatistik(0, 'tinggi_cm', (v) => v, 1),
        },
        {
          judul: 'Massa Jenis (ρ)',
          nilai: rho != null ? rho.toFixed(0) : '--',
          satuan: 'kg/m³',
          rumus: 'Fluida uji',
          stat: hitungStatistik(0, 'rho', (v) => v, 0),
        },
      ];
    }

    // Default Mode 1: Zat Gas
    const pPa = ambilAngka(sumber, ['p_gauge_pa', 'p_pa']);
    const suhuK = ambilAngka(sumber, 'suhu_k');
    const vol = ambilAngka(sumber, 'volume_m3');
    const mol = ambilAngka(sumber, 'n_mol');
    return [
      {
        judul: 'Tekanan Gas (Gauge)',
        nilai: formatTekanan(pPa),
        satuan: pUnit,
        rumus: 'P·V = n·R·T',
        stat: hitungStatistik(1, ['p_gauge_pa', 'p_pa'], konversiTekanan, pDec),
      },
      {
        judul: 'Suhu Gas (T)',
        nilai: formatSuhu(suhuK),
        satuan: state.config.satuanSuhu,
        rumus: 'T (K / °C)',
        stat: hitungStatistik(1, 'suhu_k', konversiSuhu, 1),
      },
      {
        judul: 'Volume Ruang (V)',
        nilai: vol != null ? vol.toFixed(4) : '--',
        satuan: 'm³',
        rumus: 'V wadah',
        stat: hitungStatistik(1, 'volume_m3', (v) => v, 4),
      },
      {
        judul: 'Jumlah Mol (n)',
        nilai: mol != null ? mol.toFixed(4) : '--',
        satuan: 'mol',
        rumus: 'n = PV / RT',
        stat: hitungStatistik(1, 'n_mol', (v) => v, 4),
      },
    ];
  }

  // --- Render UI ---
  function renderMetrics() {
    const grid = $('#metric-grid');
    const specs = getKartuSpecs(state.mode);
    grid.innerHTML = specs
      .map(
        (s) => `
      <div class="metric-card">
        <div class="metric-top">
          <span class="metric-title">${s.judul}</span>
          <span class="metric-formula">${s.rumus}</span>
        </div>
        <div class="metric-value">${s.nilai}<span class="metric-unit">${s.satuan}</span></div>
        <div class="metric-stats">
          <span>Min: ${s.stat ? s.stat.min : '--'}</span>
          <span>Avg: ${s.stat ? s.stat.avg : '--'}</span>
          <span>Max: ${s.stat ? s.stat.max : '--'}</span>
        </div>
      </div>`
      )
      .join('');
  }

  function initChart() {
    const ctx = $('#pressure-chart').getContext('2d');
    state.chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: [],
        datasets: [
          {
            label: `Tekanan (${state.config.satuanTekanan})`,
            data: [],
            borderColor: '#2563eb',
            backgroundColor: 'rgba(37, 99, 235, 0.12)',
            borderWidth: 2.5,
            tension: 0.28,
            fill: true,
            pointRadius: 2,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        plugins: {
          legend: { display: true },
        },
        scales: {
          x: {
            ticks: { maxTicksLimit: 8 },
            grid: { display: false },
          },
          y: {
            beginAtZero: false,
          },
        },
      },
    });
  }

  function renderChart() {
    if (!state.chart) return;
    const cutoff = Date.now() - state.rangeMenit * 60 * 1000;
    const keys = MODE_INFO[state.mode].keyTekanan;
    const filtered = state.riwayat.filter(
      (item) => Number(item.data.mode) === state.mode && item.waktu.getTime() >= cutoff
    );

    const labels = filtered.map((item) =>
      item.waktu.toLocaleTimeString('id-ID', { hour12: false })
    );
    const values = filtered.map((item) => {
      const pa = ambilAngka(item, keys);
      return konversiTekanan(pa);
    });

    state.chart.data.labels = labels;
    state.chart.data.datasets[0].label = `Tekanan ${MODE_INFO[state.mode].nama} (${state.config.satuanTekanan})`;
    state.chart.data.datasets[0].data = values;
    state.chart.update();

    $('#chart-title').textContent = `Grafik Tekanan ${MODE_INFO[state.mode].nama}`;
  }

  function renderStatus() {
    const badgeMqtt = $('#badge-mqtt');
    const badgeEsp = $('#badge-esp');
    const btnConn = $('#btn-connect');

    if (state.mqttStatus === 'online') {
      badgeMqtt.textContent = 'Tersambung';
      badgeMqtt.className = 'badge badge-online';
      btnConn.textContent = 'Putuskan';
    } else if (state.mqttStatus === 'connecting') {
      badgeMqtt.textContent = 'Menyambung...';
      badgeMqtt.className = 'badge badge-connecting';
      btnConn.textContent = 'Batal';
    } else {
      badgeMqtt.textContent = 'Terputus';
      badgeMqtt.className = 'badge badge-offline';
      btnConn.textContent = 'Hubungkan';
    }

    if (state.simulasiAktif) {
      badgeEsp.textContent = 'Simulasi';
      badgeEsp.className = 'badge badge-connecting';
    } else if (state.espOnline) {
      badgeEsp.textContent = 'Online';
      badgeEsp.className = 'badge badge-online';
    } else {
      badgeEsp.textContent = 'Offline';
      badgeEsp.className = 'badge badge-muted';
    }

    $('#meta-broker').textContent = `${state.config.host} • ${state.config.idAlat}`;
    $('#info-topik-data').textContent = `tekanan/${state.config.idAlat}/data`;
    $('#info-topik-status').textContent = `tekanan/${state.config.idAlat}/status`;
    $('#info-topik-perintah').textContent = `tekanan/${state.config.idAlat}/perintah`;
  }

  function renderRiwayatSesi() {
    const listEl = $('#riwayat-list');
    if (state.sesiTersimpan.length === 0) {
      listEl.innerHTML = '<p class="card-sub">Belum ada sesi praktikum tersimpan. Mulai rekam dari panel di atas.</p>';
      return;
    }
    listEl.innerHTML = state.sesiTersimpan
      .map(
        (sesi) => `
      <div class="sesi-item">
        <div>
          <div class="sesi-title">${escapeHtml(sesi.judul)}</div>
          <div class="sesi-meta">${MODE_INFO[sesi.mode]?.nama || 'Mode'} • ${sesi.sampel.length} sampel • ${new Date(sesi.waktu).toLocaleString('id-ID')}</div>
        </div>
        <div class="sesi-actions">
          <button class="btn btn-outline btn-sm" data-export="${sesi.id}">Export CSV</button>
          <button class="btn btn-danger btn-sm" data-hapus="${sesi.id}">Hapus</button>
        </div>
      </div>`
      )
      .join('');
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // --- Data Ingestion ---
  function terimaPembacaan(payloadObj) {
    const waktu = new Date();
    const item = { waktu, data: payloadObj };
    const mode = Number(payloadObj.mode);

    state.terakhir = item;
    if (mode === 0 || mode === 1 || mode === 2) {
      state.terakhirPerMode[mode] = item;
    }

    state.riwayat.push(item);
    if (state.riwayat.length > MAX_RIWAYAT) {
      state.riwayat.shift();
    }

    if (state.merekam && mode === state.mode) {
      state.sampelRekam.push({
        waktu: waktu.toISOString(),
        data: payloadObj,
      });
      $('#rekam-jumlah').textContent = state.sampelRekam.length;
    }

    $('#last-update').textContent = `Update: ${waktu.toLocaleTimeString('id-ID', { hour12: false })}`;
    renderMetrics();
    renderChart();
  }

  // --- MQTT WebSocket ---
  function hubungkanMqtt() {
    if (state.client) {
      state.client.end(true);
      state.client = null;
    }

    const { protocol, host, port, path, idAlat } = state.config;
    const cleanPath = path.startsWith('/') ? path : `/${path}`;
    const url = `${protocol}://${host}:${port}${cleanPath}`;

    state.mqttStatus = 'connecting';
    renderStatus();

    const clientId = `web_4sb_${Math.random().toString(16).slice(2, 10)}`;
    const client = mqtt.connect(url, {
      clientId,
      clean: true,
      reconnectPeriod: 4000,
      connectTimeout: 10000,
    });

    state.client = client;

    client.on('connect', () => {
      state.mqttStatus = 'online';
      client.subscribe(`tekanan/${idAlat}/data`);
      client.subscribe(`tekanan/${idAlat}/status`);
      renderStatus();
    });

    client.on('reconnect', () => {
      state.mqttStatus = 'connecting';
      renderStatus();
    });

    client.on('close', () => {
      state.mqttStatus = 'offline';
      state.espOnline = false;
      renderStatus();
    });

    client.on('error', () => {
      state.mqttStatus = 'offline';
      renderStatus();
    });

    client.on('message', (topic, message) => {
      const text = message.toString();
      if (topic === `tekanan/${idAlat}/status`) {
        state.espOnline = text.trim().toLowerCase() === 'online';
        renderStatus();
        return;
      }
      if (topic === `tekanan/${idAlat}/data`) {
        try {
          const parsed = JSON.parse(text);
          state.espOnline = true;
          renderStatus();
          terimaPembacaan(parsed);
        } catch {
          // Abaikan payload non-JSON
        }
      }
    });
  }

  function putuskanMqtt() {
    if (state.client) {
      state.client.end(true);
      state.client = null;
    }
    state.mqttStatus = 'offline';
    state.espOnline = false;
    renderStatus();
  }

  function kirimPerintahMode(mode) {
    if (state.client && state.mqttStatus === 'online') {
      state.client.publish(`tekanan/${state.config.idAlat}/perintah`, `MODE:${mode}`, { qos: 1 });
    }
  }

  // --- Mode Simulasi ---
  function toggleSimulasi() {
    state.simulasiAktif = !state.simulasiAktif;
    const btn = $('#btn-simulasi');
    btn.textContent = state.simulasiAktif ? 'Simulasi: ON' : 'Simulasi: OFF';

    if (state.simulasiAktif) {
      kirimDataSimulasi();
      state.simulasiTimer = setInterval(kirimDataSimulasi, 1500);
    } else {
      clearInterval(state.simulasiTimer);
      state.simulasiTimer = null;
    }
    renderStatus();
  }

  function kirimDataSimulasi() {
    const jitter = () => (Math.random() - 0.5) * 0.04;
    let payload;
    if (state.mode === 2) {
      const massa = 500 + Math.round((Math.random() - 0.5) * 40);
      const gaya = (massa / 1000) * 9.81;
      const luas = 4.0; // cm2
      const pa = gaya / (luas / 10000);
      payload = { mode: 2, mode_nama: 'Zat Padat', p_padat_pa: pa, p_pa: pa, gaya_n: gaya, luas_cm2: luas, massa_g: massa };
    } else if (state.mode === 0) {
      const tinggi = 18 + Math.random() * 4;
      const rho = 1000;
      const pa = rho * 9.81 * (tinggi / 100);
      payload = { mode: 0, mode_nama: 'Zat Cair', p_cair_pa: pa, p_pa: pa, tinggi_cm: tinggi, rho };
    } else {
      const suhuK = 301.15 + (Math.random() - 0.5) * 2;
      const vol = 0.0025;
      const pa = 105000 * (1 + jitter());
      const mol = (pa * vol) / (8.314 * suhuK);
      payload = { mode: 1, mode_nama: 'Zat Gas', p_gauge_pa: pa, p_pa: pa, suhu_k: suhuK, volume_m3: vol, n_mol: mol };
    }
    terimaPembacaan(payload);
  }

  // --- Export CSV ---
  function exportCsv(sesiId) {
    const sesi = state.sesiTersimpan.find((s) => s.id === sesiId);
    if (!sesi || sesi.sampel.length === 0) return;

    const allKeys = new Set();
    sesi.sampel.forEach((s) => Object.keys(s.data || {}).forEach((k) => allKeys.add(k)));
    const headers = ['waktu', ...Array.from(allKeys)];

    const rows = [headers.join(',')];
    for (const s of sesi.sampel) {
      const row = [s.waktu, ...Array.from(allKeys).map((k) => s.data?.[k] ?? '')];
      rows.push(row.join(','));
    }

    const blob = new Blob([rows.join('\n')], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${sesi.judul.replace(/[^a-z0-9_-]/gi, '_')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  // --- Event Listeners ---
  function bindEvents() {
    // Tab navigation
    $$('.nav-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        $$('.nav-btn').forEach((b) => b.classList.remove('active'));
        $$('.tab-panel').forEach((p) => p.classList.remove('active'));
        btn.classList.add('active');
        const tab = btn.dataset.tab;
        $(`#tab-${tab}`).classList.add('active');
      });
    });

    // Mode selector
    $$('.seg-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        $$('.seg-btn').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        state.mode = Number(btn.dataset.mode);
        kirimPerintahMode(state.mode);
        renderMetrics();
        renderChart();
      });
    });

    // Range selector
    $$('.range-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        $$('.range-btn').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        state.rangeMenit = Number(btn.dataset.range);
        renderChart();
      });
    });

    $('#btn-clear-chart').addEventListener('click', () => {
      state.riwayat = [];
      renderMetrics();
      renderChart();
    });

    $('#btn-connect').addEventListener('click', () => {
      if (state.mqttStatus === 'online' || state.mqttStatus === 'connecting') {
        putuskanMqtt();
      } else {
        hubungkanMqtt();
      }
    });

    $('#btn-simulasi').addEventListener('click', toggleSimulasi);

    // Theme toggle
    $('#btn-theme').addEventListener('click', () => {
      state.config.tema = state.config.tema === 'light' ? 'dark' : 'light';
      applyTheme();
      saveConfig();
    });

    // Praktikum record
    $('#btn-toggle-rekam').addEventListener('click', () => {
      if (!state.merekam) {
        state.merekam = true;
        state.sampelRekam = [];
        $('#btn-toggle-rekam').textContent = 'Simpan & Selesai';
        $('#btn-toggle-rekam').classList.replace('btn-primary', 'btn-danger');
        $('#rekam-mode-nama').textContent = MODE_INFO[state.mode].nama;
        $('#rekam-jumlah').textContent = '0';
        $('#record-status').classList.remove('hidden');
      } else {
        state.merekam = false;
        $('#btn-toggle-rekam').textContent = 'Mulai Rekam';
        $('#btn-toggle-rekam').classList.replace('btn-danger', 'btn-primary');
        $('#record-status').classList.add('hidden');

        if (state.sampelRekam.length > 0) {
          const judulInput = $('#input-judul-sesi').value.trim();
          const sesiBaru = {
            id: Date.now().toString(),
            mode: state.mode,
            judul: judulInput || `Praktikum ${MODE_INFO[state.mode].nama}`,
            waktu: new Date().toISOString(),
            sampel: state.sampelRekam,
          };
          state.sesiTersimpan.unshift(sesiBaru);
          saveSesi();
          renderRiwayatSesi();
          $('#input-judul-sesi').value = '';
        }
      }
    });

    $('#riwayat-list').addEventListener('click', (e) => {
      const exportId = e.target.dataset.export;
      const hapusId = e.target.dataset.hapus;
      if (exportId) exportCsv(exportId);
      if (hapusId) {
        state.sesiTersimpan = state.sesiTersimpan.filter((s) => s.id !== hapusId);
        saveSesi();
        renderRiwayatSesi();
      }
    });

    $('#btn-hapus-semua-sesi').addEventListener('click', () => {
      state.sesiTersimpan = [];
      saveSesi();
      renderRiwayatSesi();
    });

    // Settings form
    $('#form-pengaturan').addEventListener('submit', (e) => {
      e.preventDefault();
      state.config.host = $('#cfg-host').value.trim() || DEFAULT_CONFIG.host;
      state.config.protocol = $('#cfg-protocol').value;
      state.config.port = Number($('#cfg-port').value) || DEFAULT_CONFIG.port;
      state.config.path = $('#cfg-path').value.trim() || '/mqtt';
      state.config.idAlat = $('#cfg-id').value.trim() || DEFAULT_CONFIG.idAlat;
      state.config.satuanTekanan = $('#cfg-satuan-tekanan').value;
      state.config.satuanSuhu = $('#cfg-satuan-suhu').value;
      saveConfig();
      renderStatus();
      renderMetrics();
      renderChart();
      if (state.mqttStatus === 'online') hubungkanMqtt();
      alert('Pengaturan berhasil disimpan!');
    });

    $('#btn-reset-pengaturan').addEventListener('click', () => {
      state.config = { ...DEFAULT_CONFIG };
      saveConfig();
      isiFormPengaturan();
      applyTheme();
      renderStatus();
      renderMetrics();
      renderChart();
    });
  }

  function isiFormPengaturan() {
    $('#cfg-host').value = state.config.host;
    $('#cfg-protocol').value = state.config.protocol;
    $('#cfg-port').value = state.config.port;
    $('#cfg-path').value = state.config.path;
    $('#cfg-id').value = state.config.idAlat;
    $('#cfg-satuan-tekanan').value = state.config.satuanTekanan;
    $('#cfg-satuan-suhu').value = state.config.satuanSuhu;
  }

  function applyTheme() {
    document.documentElement.setAttribute('data-theme', state.config.tema);
    $('#btn-theme').textContent = state.config.tema === 'light' ? 'Mode Gelap' : 'Mode Terang';
  }

  // --- Init ---
  applyTheme();
  isiFormPengaturan();
  initChart();
  bindEvents();
  renderStatus();
  renderMetrics();
  renderRiwayatSesi();
})();

