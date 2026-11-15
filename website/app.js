(() => {
  'use strict';

  const STORAGE_KEY_CFG = '4sb_web_config_v1';
  const STORAGE_KEY_SESI = '4sb_web_sesi_v1';
  const STORAGE_KEY_CAPTURES = '4sb_web_captures_v1';
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

  // SVG Ikon menyesuaikan zona diorama alat fisik
  const MODE_SVGS = {
    2: `<svg viewBox="0 0 64 64" width="48" height="48" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 24L32 10L52 24H12Z" fill="#d97706"/>
      <path d="M16 36L32 24L48 36H16Z" fill="#f59e0b"/>
      <rect x="20" y="36" width="24" height="16" rx="2" fill="#92400e"/>
      <rect x="27" y="42" width="10" height="10" rx="1" fill="#fde68a"/>
      <rect x="10" y="52" width="44" height="5" rx="2.5" fill="#78350f"/>
    </svg>`,
    0: `<svg viewBox="0 0 64 64" width="48" height="48" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M24 54L28 28H36L40 54H24Z" fill="#0284c7"/>
      <rect x="29" y="42" width="6" height="12" rx="1" fill="#e0f2fe"/>
      <circle cx="32" cy="26" r="4" fill="#0369a1"/>
      <path d="M32 26L14 14L18 10L32 26Z" fill="#38bdf8"/>
      <path d="M32 26L50 38L46 42L32 26Z" fill="#38bdf8"/>
      <path d="M32 26L44 8L48 12L32 26Z" fill="#7dd3fc"/>
      <path d="M32 26L20 44L16 40L32 26Z" fill="#7dd3fc"/>
    </svg>`,
    1: `<svg viewBox="0 0 64 64" width="48" height="48" fill="none" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="32" cy="24" rx="16" ry="18" fill="#e11d48"/>
      <path d="M32 6C25 12 25 36 32 42C39 36 39 12 32 6Z" fill="#ffe4e6"/>
      <path d="M24 41L27 47H37L40 41" stroke="#9f1239" stroke-width="2"/>
      <rect x="26" y="47" width="12" height="8" rx="2" fill="#b45309"/>
      <circle cx="24" cy="18" r="2.2" fill="#fda4af"/>
      <circle cx="40" cy="20" r="2.2" fill="#fda4af"/>
    </svg>`,
  };

  const MODE_INFO = {
    2: {
      nama: 'Zat Padat',
      keyTekanan: ['p_padat_pa', 'p_pa'],
      zona: 'Zona Tengah • Pagoda & Load Cell',
      rumus: 'P = F / A',
      judul: 'Praktikum Tekanan Zat Padat',
      deskripsi: 'Amati bagaimana gaya tekan (F) dan luas bidang sentuh (A) memengaruhi besarnya tekanan pada benda padat.',
      color: '#d97706',
      bg: 'rgba(217, 119, 6, 0.14)',
    },
    0: {
      nama: 'Zat Cair',
      keyTekanan: ['p_cair_pa', 'p_pa'],
      zona: 'Zona Kanan • Kincir Angin & Tabung Air',
      rumus: 'P = ρ · g · h',
      judul: 'Praktikum Tekanan Hidrostatis (Zat Cair)',
      deskripsi: 'Amati bagaimana kedalaman air (h) dan massa jenis fluida (ρ) memengaruhi tekanan di dalam tabung.',
      color: '#0284c7',
      bg: 'rgba(2, 132, 199, 0.14)',
    },
    1: {
      nama: 'Zat Gas',
      keyTekanan: ['p_gauge_pa', 'p_pa'],
      zona: 'Zona Kiri • Balon Udara Sakura',
      rumus: 'P · V = n · R · T',
      judul: 'Praktikum Tekanan Zat Gas',
      deskripsi: 'Amati tekanan udara di dalam balon, suhu ruangan (T), dan perkiraan volume gas (V).',
      color: '#e11d48',
      bg: 'rgba(225, 29, 72, 0.14)',
    },
  };

  const state = {
    config: loadConfig(),
    mode: 1, // 2=Padat, 0=Cair, 1=Gas
    rangeMenit: 1,
    mqttStatus: 'offline',
    espOnline: false,
    simulasiAktif: false,
    simulasiTimer: null,
    client: null,
    riwayat: [],
    terakhirPerMode: { 0: null, 1: null, 2: null },
    terakhir: null,
    modePraktikumAktif: false,
    sesiTersimpan: loadSesi(),
    captures: loadCaptures(),
    flippedCards: new Set(),
    chart: null,
  };

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

  function loadCaptures() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_CAPTURES);
      const parsed = raw ? JSON.parse(raw) : null;
      return parsed && typeof parsed === 'object' ? { 0: [], 1: [], 2: [], ...parsed } : { 0: [], 1: [], 2: [] };
    } catch {
      return { 0: [], 1: [], 2: [] };
    }
  }

  function saveCaptures() {
    localStorage.setItem(STORAGE_KEY_CAPTURES, JSON.stringify(state.captures));
  }

  // --- Loading / Splash Screen ---
  function runLoadingScreen() {
    const screen = $('#loading-screen');
    const bar = $('#loading-bar-fill');
    const statusText = $('#loading-status-text');
    if (!screen) return;

    const dismiss = () => screen.classList.add('fade-out');
    screen.addEventListener('click', dismiss);
    setTimeout(dismiss, 1800);

    const steps = [
      { pct: 40, text: 'Menyiapkan tampilan laboratorium...' },
      { pct: 80, text: 'Memuat grafik & panduan praktikum...' },
      { pct: 100, text: 'Siap digunakan!' },
    ];

    let idx = 0;
    const timer = setInterval(() => {
      if (idx < steps.length) {
        if (bar) bar.style.width = `${steps[idx].pct}%`;
        if (statusText) statusText.textContent = steps[idx].text;
        idx++;
      } else {
        clearInterval(timer);
        setTimeout(dismiss, 200);
      }
    }, 300);
  }

  // --- Konversi Satuan ---
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
          judul: 'Tekanan Zat Padat (P)',
          nilai: formatTekanan(pPa),
          satuan: pUnit,
          rumus: 'P = F / A',
          penjelasan: 'Besar gaya tekan (F) per satuan luas bidang sentuh (A). Semakin kecil luas, tekanan semakin besar.',
          stat: hitungStatistik(2, ['p_padat_pa', 'p_pa'], konversiTekanan, pDec),
        },
        {
          judul: 'Gaya Tekan (F)',
          nilai: gaya != null ? gaya.toFixed(2) : '--',
          satuan: 'N',
          rumus: 'F = m · g',
          penjelasan: 'Gaya berat benda yang menekan permukaan sensor (massa dikali gravitasi 9,81 m/s²).',
          stat: hitungStatistik(2, 'gaya_n', (v) => v, 2),
        },
        {
          judul: 'Luas Bidang (A)',
          nilai: luas != null ? luas.toFixed(2) : '--',
          satuan: 'cm²',
          rumus: 'A = p × l',
          penjelasan: 'Luas permukaan benda yang bersentuhan langsung dengan alas beban.',
          stat: hitungStatistik(2, 'luas_cm2', (v) => v, 2),
        },
        {
          judul: 'Massa Beban (m)',
          nilai: massa != null ? massa.toFixed(1) : '--',
          satuan: 'g',
          rumus: 'Sensor Load Cell',
          penjelasan: 'Massa benda uji yang diukur secara langsung oleh sensor berat (Load Cell HX711).',
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
          judul: 'Tekanan Hidrostatis (P)',
          nilai: formatTekanan(pPa),
          satuan: pUnit,
          rumus: 'P = ρ · g · h',
          penjelasan: 'Tekanan zat cair yang dipengaruhi oleh massa jenis (ρ), gravitasi (g), dan kedalaman (h).',
          stat: hitungStatistik(0, ['p_cair_pa', 'p_pa'], konversiTekanan, pDec),
        },
        {
          judul: 'Kedalaman Air (h)',
          nilai: tinggi != null ? tinggi.toFixed(1) : '--',
          satuan: 'cm',
          rumus: 'h = P / (ρ · g)',
          penjelasan: 'Jarak titik ukur dari permukaan atas air di dalam tabung uji.',
          stat: hitungStatistik(0, 'tinggi_cm', (v) => v, 1),
        },
        {
          judul: 'Massa Jenis (ρ)',
          nilai: rho != null ? rho.toFixed(0) : '--',
          satuan: 'kg/m³',
          rumus: 'ρ air ≈ 1000',
          penjelasan: 'Kerapatan zat cair yang digunakan dalam percobaan (air murni ≈ 1000 kg/m³).',
          stat: hitungStatistik(0, 'rho', (v) => v, 0),
        },
      ];
    }

    const pPa = ambilAngka(sumber, ['p_gauge_pa', 'p_pa']);
    const suhuK = ambilAngka(sumber, 'suhu_k');
    const vol = ambilAngka(sumber, 'volume_m3');
    const mol = ambilAngka(sumber, 'n_mol');
    return [
      {
        judul: 'Tekanan Gas (P)',
        nilai: formatTekanan(pPa),
        satuan: pUnit,
        rumus: 'P · V = n · R · T',
        penjelasan: 'Tekanan udara di dalam ruang/balon yang diukur oleh sensor tekanan gas.',
        stat: hitungStatistik(1, ['p_gauge_pa', 'p_pa'], konversiTekanan, pDec),
      },
      {
        judul: 'Suhu Gas (T)',
        nilai: formatSuhu(suhuK),
        satuan: state.config.satuanSuhu,
        rumus: state.config.satuanSuhu === 'K' ? 'T = °C + 273,15' : 'T = K - 273,15',
        penjelasan: 'Suhu udara terukur oleh sensor DHT22 (satuan dapat diubah antara °C dan K di Pengaturan).',
        stat: hitungStatistik(1, 'suhu_k', konversiSuhu, 1),
      },
      {
        judul: 'Volume Balon (V)',
        nilai: vol != null ? vol.toFixed(4) : '--',
        satuan: 'm³',
        rumus: 'V = (4/3) · π · r³',
        penjelasan: 'Perkiraan volume ruang udara di dalam balon dalam satuan meter kubik (m³).',
        stat: hitungStatistik(1, 'volume_m3', (v) => v, 4),
      },
      {
        judul: 'Jumlah Mol (n)',
        nilai: mol != null ? mol.toFixed(4) : '--',
        satuan: 'mol',
        rumus: 'n = (P · V) / (R · T)',
        penjelasan: 'Banyaknya partikel molekul gas berdasarkan persamaan gas ideal (R = 8,314 J/mol·K).',
        stat: hitungStatistik(1, 'n_mol', (v) => v, 4),
      },
    ];
  }

  // --- Render UI ---
  function renderModeTheme() {
    document.documentElement.setAttribute('data-mode', String(state.mode));
    const info = MODE_INFO[state.mode];
    if ($('#mode-banner-icon')) $('#mode-banner-icon').innerHTML = MODE_SVGS[state.mode];
    if ($('#mode-zone-tag')) $('#mode-zone-tag').textContent = info.zona;
    if ($('#mode-formula-pill')) $('#mode-formula-pill').textContent = info.rumus;
    if ($('#mode-banner-title')) $('#mode-banner-title').textContent = info.judul;
    if ($('#mode-banner-desc')) $('#mode-banner-desc').textContent = info.deskripsi;
    if ($('#btn-ambil-data')) $('#btn-ambil-data').textContent = `📸 Ambil Nilai ${info.nama}`;
    if ($('#capture-title')) $('#capture-title').textContent = `Tabel Data Pengamatan — ${info.nama}`;
  }

  function ambilNilaiSaatIni() {
    const m = state.mode;
    const sumber = state.terakhirPerMode[m] || (state.terakhir?.data?.mode === m ? state.terakhir : null);
    if (!sumber) {
      alert(`Belum ada data untuk ${MODE_INFO[m].nama}. Hubungkan alat atau nyalakan Simulasi terlebih dahulu.`);
      return;
    }

    const waktu = new Date().toLocaleTimeString('id-ID', { hour12: false });
    let entry;

    if (m === 2) {
      entry = {
        id: Date.now().toString(),
        waktu,
        p_pa: ambilAngka(sumber, ['p_padat_pa', 'p_pa']),
        gaya_n: ambilAngka(sumber, 'gaya_n'),
        luas_cm2: ambilAngka(sumber, 'luas_cm2'),
        massa_g: ambilAngka(sumber, 'massa_g'),
      };
    } else if (m === 0) {
      entry = {
        id: Date.now().toString(),
        waktu,
        p_pa: ambilAngka(sumber, ['p_cair_pa', 'p_pa']),
        tinggi_cm: ambilAngka(sumber, 'tinggi_cm'),
        rho: ambilAngka(sumber, 'rho') ?? 1000,
      };
    } else {
      entry = {
        id: Date.now().toString(),
        waktu,
        p_pa: ambilAngka(sumber, ['p_gauge_pa', 'p_pa']),
        suhu_k: ambilAngka(sumber, 'suhu_k'),
        volume_m3: ambilAngka(sumber, 'volume_m3'),
        n_mol: ambilAngka(sumber, 'n_mol'),
      };
    }

    state.captures[m].push(entry);
    saveCaptures();
    renderCaptureTable();
  }

  function renderCaptureTable() {
    const wrap = $('#capture-table-wrap');
    const m = state.mode;
    const list = state.captures[m] || [];
    const pUnit = state.config.satuanTekanan;
    const tUnit = state.config.satuanSuhu;

    if (list.length === 0) {
      wrap.innerHTML = `<p class="card-sub">Belum ada data yang diambil untuk <strong>${MODE_INFO[m].nama}</strong>.</p>`;
      return;
    }

    let headers = [];
    let rowsHtml = '';

    if (m === 2) {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, 'Gaya (N)', 'Luas (cm²)', 'Massa (g)', 'Aksi'];
      rowsHtml = list
        .map(
          (r, i) => `
        <tr>
          <td>${i + 1}</td>
          <td>${r.waktu}</td>
          <td>${formatTekanan(r.p_pa)}</td>
          <td>${r.gaya_n != null ? r.gaya_n.toFixed(2) : '--'}</td>
          <td>${r.luas_cm2 != null ? r.luas_cm2.toFixed(2) : '--'}</td>
          <td>${r.massa_g != null ? r.massa_g.toFixed(1) : '--'}</td>
          <td><button class="btn btn-danger btn-sm" data-del-capture="${r.id}">Hapus</button></td>
        </tr>`
        )
        .join('');
    } else if (m === 0) {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, 'Kedalaman (cm)', 'Massa Jenis (kg/m³)', 'Aksi'];
      rowsHtml = list
        .map(
          (r, i) => `
        <tr>
          <td>${i + 1}</td>
          <td>${r.waktu}</td>
          <td>${formatTekanan(r.p_pa)}</td>
          <td>${r.tinggi_cm != null ? r.tinggi_cm.toFixed(1) : '--'}</td>
          <td>${r.rho != null ? r.rho.toFixed(0) : '--'}</td>
          <td><button class="btn btn-danger btn-sm" data-del-capture="${r.id}">Hapus</button></td>
        </tr>`
        )
        .join('');
    } else {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, `Suhu (${tUnit})`, 'Volume (m³)', 'Mol (mol)', 'Aksi'];
      rowsHtml = list
        .map(
          (r, i) => `
        <tr>
          <td>${i + 1}</td>
          <td>${r.waktu}</td>
          <td>${formatTekanan(r.p_pa)}</td>
          <td>${formatSuhu(r.suhu_k)}</td>
          <td>${r.volume_m3 != null ? r.volume_m3.toFixed(4) : '--'}</td>
          <td>${r.n_mol != null ? r.n_mol.toFixed(4) : '--'}</td>
          <td><button class="btn btn-danger btn-sm" data-del-capture="${r.id}">Hapus</button></td>
        </tr>`
        )
        .join('');
    }

    wrap.innerHTML = `
      <table class="data-table">
        <thead>
          <tr>${headers.map((h) => `<th>${h}</th>`).join('')}</tr>
        </thead>
        <tbody>${rowsHtml}</tbody>
      </table>`;
  }

  function exportCaptureCsv() {
    const m = state.mode;
    const list = state.captures[m] || [];
    if (list.length === 0) {
      alert('Belum ada data pengamatan untuk diunduh.');
      return;
    }

    const pUnit = state.config.satuanTekanan;
    const tUnit = state.config.satuanSuhu;
    let headers;
    let rows;

    if (m === 2) {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, 'Gaya (N)', 'Luas (cm2)', 'Massa (g)'];
      rows = list.map((r, i) => [
        i + 1,
        r.waktu,
        formatTekanan(r.p_pa),
        r.gaya_n != null ? r.gaya_n.toFixed(2) : '',
        r.luas_cm2 != null ? r.luas_cm2.toFixed(2) : '',
        r.massa_g != null ? r.massa_g.toFixed(1) : '',
      ]);
    } else if (m === 0) {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, 'Kedalaman (cm)', 'Massa Jenis (kg/m3)'];
      rows = list.map((r, i) => [
        i + 1,
        r.waktu,
        formatTekanan(r.p_pa),
        r.tinggi_cm != null ? r.tinggi_cm.toFixed(1) : '',
        r.rho != null ? r.rho.toFixed(0) : '',
      ]);
    } else {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, `Suhu (${tUnit})`, 'Volume (m3)', 'Mol (mol)'];
      rows = list.map((r, i) => [
        i + 1,
        r.waktu,
        formatTekanan(r.p_pa),
        formatSuhu(r.suhu_k),
        r.volume_m3 != null ? r.volume_m3.toFixed(4) : '',
        r.n_mol != null ? r.n_mol.toFixed(4) : '',
      ]);
    }

    const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `pengamatan_${MODE_INFO[m].nama.toLowerCase().replace(/\s+/g, '_')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function renderPanduanIcons() {
    $('#icon-panduan-padat').innerHTML = MODE_SVGS[2];
    $('#icon-panduan-cair').innerHTML = MODE_SVGS[0];
    $('#icon-panduan-gas').innerHTML = MODE_SVGS[1];
  }

  function renderMetrics() {
    const grid = $('#metric-grid');
    const specs = getKartuSpecs(state.mode);

    if (grid.dataset.renderedMode !== String(state.mode)) {
      grid.dataset.renderedMode = String(state.mode);
      grid.innerHTML = specs
        .map((s, idx) => {
          const key = `${state.mode}_${idx}`;
          const isFlipped = state.flippedCards.has(key) ? 'flipped' : '';
          return `
        <div class="metric-flip-card ${isFlipped}" data-card-idx="${idx}" title="Klik untuk membalik kartu">
          <div class="metric-flip-inner">
            <!-- Sisi Depan: Hanya Keterangan, Nilai & Satuan -->
            <div class="metric-face metric-face-front">
              <div class="metric-top">
                <span class="metric-title">${s.judul}</span>
                <span class="flip-hint">🔄 Info</span>
              </div>
              <div class="metric-value">
                <span class="js-val">${s.nilai}</span><span class="metric-unit js-unit">${s.satuan}</span>
              </div>
              <div class="metric-front-sub">Klik kotak untuk lihat rumus &amp; arti</div>
            </div>
            <!-- Sisi Belakang: Rumus, Penjelasan & Statistik -->
            <div class="metric-face metric-face-back">
              <div class="metric-top">
                <span class="metric-title">${s.judul}</span>
                <span class="metric-formula js-formula">${s.rumus}</span>
              </div>
              <p class="metric-desc">${s.penjelasan}</p>
              <div class="metric-stats js-stats">
                <span>Min: ${s.stat ? s.stat.min : '--'}</span>
                <span>Avg: ${s.stat ? s.stat.avg : '--'}</span>
                <span>Max: ${s.stat ? s.stat.max : '--'}</span>
              </div>
            </div>
          </div>
        </div>`;
        })
        .join('');
      return;
    }

    // Update nilai & satuan secara langsung tanpa mereset animasi flip
    const cards = grid.querySelectorAll('.metric-flip-card');
    specs.forEach((s, idx) => {
      const card = cards[idx];
      if (!card) return;
      card.querySelector('.js-val').textContent = s.nilai;
      card.querySelector('.js-unit').textContent = s.satuan;
      card.querySelector('.js-formula').textContent = s.rumus;
      card.querySelector('.js-stats').innerHTML = `
        <span>Min: ${s.stat ? s.stat.min : '--'}</span>
        <span>Avg: ${s.stat ? s.stat.avg : '--'}</span>
        <span>Max: ${s.stat ? s.stat.max : '--'}</span>`;
    });
  }

  function initChart() {
    const canvas = $('#pressure-chart');
    if (!canvas || typeof Chart === 'undefined') return;
    const ctx = canvas.getContext('2d');
    const info = MODE_INFO[state.mode];
    state.chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: [],
        datasets: [
          {
            label: `Tekanan (${state.config.satuanTekanan})`,
            data: [],
            borderColor: info.color,
            backgroundColor: info.bg,
            borderWidth: 2.8,
            tension: 0.3,
            fill: true,
            pointRadius: 2.5,
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
    const info = MODE_INFO[state.mode];
    const filtered = state.riwayat.filter(
      (item) => Number(item.data.mode) === state.mode && item.waktu.getTime() >= cutoff
    );

    const labels = filtered.map((item) =>
      item.waktu.toLocaleTimeString('id-ID', { hour12: false })
    );
    const values = filtered.map((item) => {
      const pa = ambilAngka(item, info.keyTekanan);
      return konversiTekanan(pa);
    });

    const ds = state.chart.data.datasets[0];
    state.chart.data.labels = labels;
    ds.label = `Tekanan ${info.nama} (${state.config.satuanTekanan})`;
    ds.borderColor = info.color;
    ds.backgroundColor = info.bg;
    ds.data = values;
    state.chart.update();

    $('#chart-title').textContent = `Grafik Tekanan ${info.nama}`;
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
      listEl.innerHTML = '<p class="card-sub">Belum ada sesi praktikum tersimpan. Buka <strong>Panduan Praktikum</strong> → klik <strong>Mulai Praktikum</strong> → ambil nilai lalu simpan ke riwayat.</p>';
      return;
    }
    listEl.innerHTML = state.sesiTersimpan
      .map(
        (sesi) => `
      <div class="sesi-item">
        <div>
          <div class="sesi-title">${escapeHtml(sesi.judul)}</div>
          <div class="sesi-meta">${MODE_INFO[sesi.mode]?.nama || 'Mode'} • ${sesi.sampel.length} data pengamatan • ${new Date(sesi.waktu).toLocaleString('id-ID')}</div>
        </div>
        <div class="sesi-actions">
          <button class="btn btn-outline btn-sm" data-export="${sesi.id}">Unduh CSV</button>
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

  function pilihMode(modeBaru) {
    state.mode = modeBaru;
    $$('.seg-btn').forEach((b) => {
      b.classList.toggle('active', Number(b.dataset.mode) === modeBaru);
    });
    kirimPerintahMode(modeBaru);
    renderModeTheme();
    renderMetrics();
    renderCaptureTable();
    renderChart();
  }

  function toggleSidebar(forceOpen) {
    const sb = $('#sidebar');
    const ov = $('#sidebar-overlay');
    const isOpen = forceOpen !== undefined ? forceOpen : !sb.classList.contains('open');
    sb.classList.toggle('open', isOpen);
    ov.classList.toggle('open', isOpen);
  }

  function renderPraktikumVisibility() {
    const show = Boolean(state.modePraktikumAktif);
    $('#banner-capture-wrap')?.classList.toggle('hidden', !show);
    $('#capture-card')?.classList.toggle('hidden', !show);
  }

  function bukaTab(tabName, mulaiPraktikum = false) {
    if (tabName === 'dashboard') {
      state.modePraktikumAktif = Boolean(mulaiPraktikum);
      renderPraktikumVisibility();
    }
    $$('.nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.tab === tabName));
    $$('.tab-panel').forEach((p) => p.classList.toggle('active', p.id === `tab-${tabName}`));
    toggleSidebar(false);
  }

  function simpanTabelKeRiwayat() {
    const m = state.mode;
    const list = state.captures[m] || [];
    if (list.length === 0) {
      alert(`Belum ada nilai yang diambil pada Tabel Data Pengamatan ${MODE_INFO[m].nama}. Klik tombol "📸 Ambil Nilai" terlebih dahulu.`);
      return;
    }

    const judulInput = $('#input-judul-sesi').value.trim();
    const sesiBaru = {
      id: Date.now().toString(),
      mode: m,
      judul: judulInput || `Praktikum ${MODE_INFO[m].nama}`,
      waktu: new Date().toISOString(),
      sampel: [...list],
    };

    state.sesiTersimpan.unshift(sesiBaru);
    saveSesi();
    state.captures[m] = [];
    saveCaptures();
    $('#input-judul-sesi').value = '';
    renderCaptureTable();
    renderRiwayatSesi();
    alert(`Sesi "${sesiBaru.judul}" berhasil disimpan ke Riwayat Praktikum!`);
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
      const luas = 4.0;
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

  // --- Export CSV dari Riwayat ---
  function exportCsv(sesiId) {
    const sesi = state.sesiTersimpan.find((s) => s.id === sesiId);
    if (!sesi || sesi.sampel.length === 0) return;

    const m = Number(sesi.mode);
    const pUnit = state.config.satuanTekanan;
    const tUnit = state.config.satuanSuhu;
    let headers;
    let rows;

    if (m === 2) {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, 'Gaya (N)', 'Luas (cm2)', 'Massa (g)'];
      rows = sesi.sampel.map((r, i) => {
        const src = r.data || r;
        return [
          i + 1,
          r.waktu || '',
          formatTekanan(src.p_pa ?? src.p_padat_pa),
          src.gaya_n != null ? Number(src.gaya_n).toFixed(2) : '',
          src.luas_cm2 != null ? Number(src.luas_cm2).toFixed(2) : '',
          src.massa_g != null ? Number(src.massa_g).toFixed(1) : '',
        ];
      });
    } else if (m === 0) {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, 'Kedalaman (cm)', 'Massa Jenis (kg/m3)'];
      rows = sesi.sampel.map((r, i) => {
        const src = r.data || r;
        return [
          i + 1,
          r.waktu || '',
          formatTekanan(src.p_pa ?? src.p_cair_pa),
          src.tinggi_cm != null ? Number(src.tinggi_cm).toFixed(1) : '',
          src.rho != null ? Number(src.rho).toFixed(0) : '',
        ];
      });
    } else {
      headers = ['No', 'Waktu', `Tekanan (${pUnit})`, `Suhu (${tUnit})`, 'Volume (m3)', 'Mol (mol)'];
      rows = sesi.sampel.map((r, i) => {
        const src = r.data || r;
        return [
          i + 1,
          r.waktu || '',
          formatTekanan(src.p_pa ?? src.p_gauge_pa),
          formatSuhu(src.suhu_k),
          src.volume_m3 != null ? Number(src.volume_m3).toFixed(4) : '',
          src.n_mol != null ? Number(src.n_mol).toFixed(4) : '',
        ];
      });
    }

    const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${sesi.judul.replace(/[^a-z0-9_-]/gi, '_')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  // --- Event Listeners ---
  function bindEvents() {
    $('#btn-open-sidebar')?.addEventListener('click', () => toggleSidebar(true));
    $('#btn-close-sidebar')?.addEventListener('click', () => toggleSidebar(false));
    $('#sidebar-overlay')?.addEventListener('click', () => toggleSidebar(false));

    $$('.nav-btn').forEach((btn) => {
      btn.addEventListener('click', () => bukaTab(btn.dataset.tab, false));
    });

    $$('.seg-btn').forEach((btn) => {
      btn.addEventListener('click', () => pilihMode(Number(btn.dataset.mode)));
    });

    $$('.btn-go-mode').forEach((btn) => {
      btn.addEventListener('click', () => {
        pilihMode(Number(btn.dataset.goMode));
        bukaTab('dashboard', true);
      });
    });

    $$('.range-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        $$('.range-btn').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        state.rangeMenit = Number(btn.dataset.range);
        renderChart();
      });
    });

    $('#btn-clear-chart')?.addEventListener('click', () => {
      state.riwayat = [];
      renderMetrics();
      renderChart();
    });

    $('#metric-grid')?.addEventListener('click', (e) => {
      const card = e.target.closest('.metric-flip-card');
      if (!card) return;
      const idx = card.dataset.cardIdx;
      const key = `${state.mode}_${idx}`;
      const willFlip = !card.classList.contains('flipped');
      card.classList.toggle('flipped', willFlip);
      if (willFlip) state.flippedCards.add(key);
      else state.flippedCards.delete(key);
    });

    $('#btn-ambil-data')?.addEventListener('click', ambilNilaiSaatIni);
    $('#btn-simpan-sesi')?.addEventListener('click', simpanTabelKeRiwayat);
    $('#btn-export-capture')?.addEventListener('click', exportCaptureCsv);
    $('#btn-clear-capture')?.addEventListener('click', () => {
      state.captures[state.mode] = [];
      saveCaptures();
      renderCaptureTable();
    });
    $('#capture-table-wrap')?.addEventListener('click', (e) => {
      const delId = e.target.dataset.delCapture;
      if (delId) {
        state.captures[state.mode] = state.captures[state.mode].filter((r) => r.id !== delId);
        saveCaptures();
        renderCaptureTable();
      }
    });

    $('#btn-connect')?.addEventListener('click', () => {
      if (state.mqttStatus === 'online' || state.mqttStatus === 'connecting') {
        putuskanMqtt();
      } else {
        hubungkanMqtt();
      }
    });

    $('#btn-simulasi')?.addEventListener('click', toggleSimulasi);

    $('#btn-theme')?.addEventListener('click', () => {
      state.config.tema = state.config.tema === 'light' ? 'dark' : 'light';
      applyTheme();
      saveConfig();
    });

    $('#riwayat-list')?.addEventListener('click', (e) => {
      const exportId = e.target.dataset.export;
      const hapusId = e.target.dataset.hapus;
      if (exportId) exportCsv(exportId);
      if (hapusId) {
        state.sesiTersimpan = state.sesiTersimpan.filter((s) => s.id !== hapusId);
        saveSesi();
        renderRiwayatSesi();
      }
    });

    $('#btn-hapus-semua-sesi')?.addEventListener('click', () => {
      state.sesiTersimpan = [];
      saveSesi();
      renderRiwayatSesi();
    });

    $('#form-pengaturan')?.addEventListener('submit', (e) => {
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
      renderCaptureTable();
      renderChart();
      if (state.mqttStatus === 'online') hubungkanMqtt();
      alert('Pengaturan berhasil disimpan!');
    });

    $('#btn-reset-pengaturan')?.addEventListener('click', () => {
      state.config = { ...DEFAULT_CONFIG };
      saveConfig();
      isiFormPengaturan();
      applyTheme();
      renderStatus();
      renderMetrics();
      renderCaptureTable();
      renderChart();
    });
  }

  function isiFormPengaturan() {
    if ($('#cfg-host')) $('#cfg-host').value = state.config.host;
    if ($('#cfg-protocol')) $('#cfg-protocol').value = state.config.protocol;
    if ($('#cfg-port')) $('#cfg-port').value = state.config.port;
    if ($('#cfg-path')) $('#cfg-path').value = state.config.path;
    if ($('#cfg-id')) $('#cfg-id').value = state.config.idAlat;
    if ($('#cfg-satuan-tekanan')) $('#cfg-satuan-tekanan').value = state.config.satuanTekanan;
    if ($('#cfg-satuan-suhu')) $('#cfg-satuan-suhu').value = state.config.satuanSuhu;
  }

  function applyTheme() {
    document.documentElement.setAttribute('data-theme', state.config.tema);
    if ($('#btn-theme')) $('#btn-theme').textContent = state.config.tema === 'light' ? '🌙 Mode Gelap' : '☀️ Mode Terang';
  }

  // --- Init ---
  runLoadingScreen();
  try {
    applyTheme();
    isiFormPengaturan();
    renderModeTheme();
    renderPanduanIcons();
    renderPraktikumVisibility();
    initChart();
    bindEvents();
    renderStatus();
    renderMetrics();
    renderCaptureTable();
    renderRiwayatSesi();
  } catch (err) {
    console.error('Init warning:', err);
  }
})();
