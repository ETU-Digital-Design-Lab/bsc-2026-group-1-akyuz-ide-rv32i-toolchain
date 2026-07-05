# AkyuzIDE

AkyuzIDE, RISC-V/FPGA donanım geliştirme süreci için tasarlanmış, yapay zeka destekli bir masaüstü IDE'dir. Amaç; Verilog/SystemVerilog tasarımı, simülasyon, FPGA sentezi (Xilinx Vivado) ve seri port üzerinden donanıma yükleme gibi normalde birbirinden kopuk araçlarla (Vivado, Icarus Verilog, RISC-V toolchain, terminal, seri port yazılımları) yapılan işleri tek bir arayüzde, yerel veya bulut tabanlı bir LLM ajanı eşliğinde yürütülebilir hale getirmek.

Klasik bir metin editörünün üstüne konmuş bir "chat" değil; IDE içindeki dosya sistemine, derleyicilere, simülatöre ve FPGA araç zincirine doğrudan erişebilen, dosya oluşturma/düzenleme gibi kritik işlemlerden önce kullanıcıdan onay isteyen bir agent mimarisi kullanılıyor. Bu sayede bir öğrenci ya da mühendis, "bir ALU modülü yaz ve simüle et" gibi bir isteği, IDE'nin editör/terminal/waveform panelleri üzerinden adım adım takip ederek gerçekleştirebiliyor.

## Öne Çıkan Özellikler

- **AI Agent (agent/ask/plan modları)** — Kullanıcı mesajı otomatik olarak sınıflandırılır: `agent` modu dosya/komut çalıştırabilen tam yetkili mod, `ask` modu salt metinsel açıklama, `plan` modu ise yalnızca read-only araçlarla (dosya okuma, proje planı) çalışan güvenli bir keşif modudur. Sınıflandırma Türkçe/İngilizce anahtar kelime regex'leri ile yapılır (`server/services/agent/mode_detector.py`), isteğe bağlı olarak Gemini ile de desteklenebilir.
- **Dosya işlemleri için onay akışı** — `write_file`, `edit_file`, `delete_file`, `create_dir`, `rename_file` gibi dosya değiştiren araçlar çalıştırılmadan önce akış duraklatılır, kullanıcıya "confirm_required" olayı gönderilir; kullanıcı onaylayana (`/api/agent/resume`) veya reddedene (`/api/agent/reject`) kadar bekler.
- **Çoklu LLM sağlayıcı desteği** — Yerel Ollama modelleri (varsayılan), OpenRouter ve Moonshot/Kimi API'leri arasında görev karmaşıklığına göre otomatik yönlendirme yapan bir "smart router" (`server/services/smart_router.py`) bulunur; ayrıca hızlı niyet tespiti için opsiyonel Gemini entegrasyonu vardır.
- **Verilog/SystemVerilog simülasyonu** — Icarus Verilog (`iverilog`/`vvp`) ile derleme ve simülasyon; üretilen `.vcd` dalga formu dosyaları backend'de parse edilip (`services/vcd_parser.py`) frontend'deki `WaveformViewer` bileşeninde görselleştirilir.
- **Xilinx Vivado FPGA akışı** — Sentez → implementasyon → bitstream üretimi tek bir TCL akışıyla tetiklenir (`server/services/vivado.py`, `server/services/tools/fpga.py`); kaynak kullanımı (LUT/FF/BRAM/DSP) ve zamanlama (WNS) raporları ayrıştırılır. Basys 3, Arty A7-35T, Nexys A7-100T gibi kartlar için hazır XDC üretimi desteklenir.
- **RISC-V assembler** — RV32I komut setini destekleyen basit bir assembler (`server/services/assembler.py`), kaynağı `readmemh` formatına çevirip sembol tablosu/listing üretir.
- **Donanım/seri port yönetimi** — `HardwareSidebar` ve `CCompilerPanel` bileşenleri üzerinden bağlı seri portlar taranır, C kodu RISC-V toolchain ile derlenir ve üretilen ikili dosya seçilen porttan karta yüklenir.
- **Monaco tabanlı editör** — Dil algılamalı çoklu sekme editör, entegre terminal (backend üzerinden gerçek shell komutu çalıştırır) ve dosya gezgini.
- **Elektron masaüstü paketleme** — Uygulama, Python backend'ini alt süreç olarak başlatan bir Electron kabuğu içinde çalışır; Windows için portable exe, Linux için AppImage/deb hedefleri electron-builder ile üretilir.
- **Fine-tuning / eğitim altyapısı** (`training/`) — Agent'ın `agent/ask/plan` davranışını öğretmek için JSONL formatında bir RISC-V/Verilog veri seti, bu veriyi doğrulayan script'ler ve LoRA/QLoRA ile yerel GPU üzerinde (ör. RTX 5070 Ti, CUDA) fine-tuning yapmayı sağlayan `finetune.py`/`merge_export.py` betikleri bulunur.

## Mimari Genel Bakış

Sistem iki ana süreçten oluşur ve ikisi de aynı anda çalışmak zorundadır:

```
┌─────────────────────────────┐        HTTP/SSE (/api/*)        ┌───────────────────────────────┐
│  Frontend (React + Vite)    │ ───────────────────────────────▶│  Backend (Python FastAPI)      │
│  - Monaco Editor            │        :3000 → proxy → :8001    │  - REST + SSE endpoints         │
│  - ChatPanel (agent UI)     │◀─────────────────────────────── │  - Agent Engine (tool loop)     │
│  - VivadoPanel/HardwareBar  │        streaming events         │  - Icarus / Vivado / RISC-V      │
│  - WaveformViewer           │                                  │    toolchain çağrıları          │
└─────────────┬────────────────┘                                └───────────────┬─────────────────┘
              │ Electron paketlemesinde                                          │
              ▼                                                                  ▼
┌─────────────────────────────┐                                  Ollama (yerel) / OpenRouter /
│  Electron (masaüstü kabuğu) │ ─── child_process spawn ───────▶  Moonshot / (opsiyonel) Gemini
│  main.ts: pencere + backend │
│  süreç yönetimi              │
└─────────────────────────────┘
```

- **Frontend** (`src/`, Vite dev sunucusu): Geliştirmede `/api` istekleri `vite.config.ts` üzerinden `:8001`'deki backend'e proxy'lenir. Electron/üretim modunda (file: protokolü) `src/services/api.ts` doğrudan `http://127.0.0.1:8001` adresini kullanır.
- **Backend** (`server/`, FastAPI, `:8001`): Tüm iş mantığı, araç (tool) çalıştırma ve LLM çağrıları burada yaşar. `server/main.py` REST/SSE endpoint'lerini, CORS ayarlarını ve workspace başlatmayı içerir; `server/services/agent/engine.py` gerçek zamanlı (streaming) agent döngüsünü yürütür.
- **Electron** (`electron/`): `main.ts`, uygulama açıldığında Python backend'ini bir alt süreç olarak başlatır (paketlenmiş sürümde `server/` klasörü `asar` dışına çıkarılarak çalıştırılır) ve backend `:8001` portunda ayağa kalkana kadar bekler.

Ayrıca `docker-compose.yml` / `Dockerfile` ile tek konteynerlik bir dağıtım da mümkündür: frontend derlenip `server/static` altına kopyalanır, backend bu statik dosyaları da servis eder (bkz. Kurulum bölümü).

## Kurulum ve Çalıştırma

### Gereksinimler
- Node.js (>= 18 önerilir)
- Python 3.10+
- Icarus Verilog (`iverilog`/`vvp`) — Verilog simülasyonu için
- (Opsiyonel) Ollama — yerel LLM çalıştırmak için
- (Opsiyonel) Xilinx Vivado — FPGA sentez/bitstream akışı için
- (Opsiyonel) RISC-V GCC toolchain — C kodunu donanıma derlemek için

### 1. Ortam değişkenleri (`.env`)
`.env.example` dosyasını `.env` olarak kopyalayın ve gerekirse düzenleyin:

```
GEMINI_API_KEY=            # Opsiyonel — hızlı mod tespiti/açıklama için (Google AI Studio anahtarı)
OLLAMA_HOST=http://127.0.0.1:11434   # Yerel Ollama adresi
REMOTE_AI_HOST=http://127.0.0.1:11434  # Ollama'ya uzaktan erişim (Tailscale/ngrok tüneli vb.)
APP_URL=                   # Uygulamanın barındırıldığı URL (opsiyonel)
```

Backend ayrıca şu ortam değişkenlerini de okur (opsiyonel): `WORKSPACE_DIR` (varsayılan `./workspace/`), `VIVADO_PATH`, `AI_MODEL`.

### 2. Backend (FastAPI)
```bash
cd server
pip install -r requirements.txt
uvicorn main:app --reload --port 8001
```
(Veya doğrudan `python server/main.py` — bu durumda backend `0.0.0.0:8001` üzerinde başlar.)

### 3. Frontend (React + Vite)
```bash
npm install
npm run dev          # Dev sunucusu (varsayılan :3001, vite.config.ts üzerinden /api → :8001 proxy)
```

`package.json`'daki script'ler:
```bash
npm run dev            # Vite dev sunucusu + Electron (geliştirme)
npm run build           # Vite production build
npm run preview         # Build çıktısını önizle
npm run desktop         # Sadece Vite (Electron olmadan)
npm run build:desktop   # Vite build + electron-builder → release/ klasörü
npm run release         # build:desktop + GitHub Releases'e yayınla
npm run lint            # tsc --noEmit (tip kontrolü)
```

Not: Dev sırasında hem backend (`uvicorn` / `python server/main.py`) hem de frontend (`npm run dev`) aynı anda çalışır durumda olmalıdır.

### 4. Masaüstü (Electron) paketi
```bash
npm run build:desktop
```
Bu komut önce Vite build'ini alır, sonra `electron-builder` ile `release/` klasörüne Windows için portable `.exe`, Linux için `AppImage`/`.deb` üretir. Electron, uygulama açıldığında `server/` altındaki Python backend'ini otomatik olarak alt süreç olarak başlatır.

### 5. Docker ile çalıştırma (opsiyonel)
Tek konteynerlik bir dağıtım için:
```bash
docker compose up --build
```
`docker-compose.yml`, frontend'i derleyip backend'e (`server/static`) gömen `Dockerfile`'ı kullanır ve `8000` portunu dışa açar. Ortam değişkenleri (`WORKSPACE_DIR`, `REMOTE_AI_HOST`, `AI_MODEL`) `docker-compose.yml` içinde tanımlıdır; `./workspace` klasörü konteynere bağlanır (volume).

### 6. Linux için otomatik kurulum betiği
Debian/Ubuntu/Pop!_OS tabanlı sistemlerde `setup.sh`, gerekli tüm bağımlılıkları (Node.js, Python venv, Icarus Verilog, Ollama, RISC-V GCC, opsiyonel Vivado tespiti) otomatik kurup `.env` dosyasını oluşturur:
```bash
bash setup.sh --dev        # Geliştirici modu (build atlanır)
bash setup.sh               # Kurulum + Electron build
```

## Klasör Yapısı

```
AkyuzIDE/
├── src/                  # React/TypeScript frontend
│   ├── App.tsx           # Üst seviye layout ve state orkestrasyonu
│   ├── components/        # ChatPanel, Editor, VivadoPanel, HardwareSidebar, Terminal, WaveformViewer, ...
│   └── services/api.ts    # Backend ile tüm iletişimin tek noktası (fetch/SSE)
├── server/               # Python FastAPI backend
│   ├── main.py            # Tüm REST/SSE endpoint'leri, CORS, workspace yönetimi
│   └── services/
│       ├── agent/          # Agent döngüsü (engine.py), mod tespiti, prompt'lar, tool registry
│       ├── providers/       # Ollama / OpenRouter / Moonshot / Gemini sağlayıcı adaptörleri
│       ├── tools/           # Agent'ın çağırabildiği dosya/shell/EDA/FPGA araçları
│       ├── assembler.py     # RISC-V (RV32I) assembler
│       ├── simulation.py    # Icarus Verilog derleme/simülasyon
│       ├── vivado.py        # Vivado TCL akışı üretimi ve çalıştırma
│       └── hardware.py      # Seri port tarama, C derleme, donanıma yükleme
├── electron/             # Electron main/preload süreçleri (masaüstü paketleme)
├── training/             # Agent davranışını öğretmek için fine-tuning altyapısı
│   ├── riscv_agent_dataset/  # JSONL eğitim/doğrulama veri seti + validate_dataset.py
│   ├── benchmark/            # Değerlendirme/benchmark ve release-gate script'leri
│   └── finetune.py, merge_export.py  # LoRA/QLoRA eğitimi ve model birleştirme
├── scripts/              # Yardımcı PowerShell script'leri (RISC-V toolchain indirme, Ollama model dizini ayarı)
├── public/               # Statik varlıklar (logo, favicon, splash ekranı)
├── .env.example          # Örnek ortam değişkenleri
├── docker-compose.yml / Dockerfile  # Tek konteyner dağıtımı
└── setup.sh              # Linux için otomatik kurulum betiği
```

## Ekran Görüntüleri

*(Buraya IDE'nin editör, agent chat paneli ve waveform görüntüleyicisinden ekran görüntüleri eklenebilir.)*

## İletişim

**Taha Tahsin Akyüz**
E-posta: takyuz515@gmail.com
