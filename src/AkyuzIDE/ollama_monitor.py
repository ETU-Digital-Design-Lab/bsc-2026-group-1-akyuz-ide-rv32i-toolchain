"""
Ollama Monitor — Proxy + Web Dashboard
=======================================
Port 11435: Ollama proxy (diğer cihazlar buraya bağlanır)
Port 11436: Web dashboard (tarayıcıda izle)

Çalıştırma:
  python ollama_monitor.py

Dashboard:
  http://localhost:11436
  http://100.97.45.128:11436  (Tailscale'den)
"""

import asyncio
import json
import time
import uuid
from collections import deque
from datetime import datetime
from pathlib import Path

import aiohttp
from aiohttp import web

OLLAMA_URL   = "http://127.0.0.1:11434"
PROXY_PORT   = 11435
MONITOR_PORT = 11436
LOG_DIR      = Path(__file__).parent / "server" / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE     = LOG_DIR / "proxy_requests.log"

# Son 200 istek bellekte tutulur
recent_requests: deque = deque(maxlen=200)
stats = {"total": 0, "errors": 0, "total_ms": 0}
ws_clients: set = set()

# ── WebSocket broadcast ──────────────────────────────────────
async def broadcast(data: dict):
    dead = set()
    msg = json.dumps(data, ensure_ascii=False)
    for ws in ws_clients:
        try:
            await ws.send_str(msg)
        except Exception:
            dead.add(ws)
    ws_clients.difference_update(dead)

# ── Proxy handler ────────────────────────────────────────────
async def proxy_handler(request: web.Request) -> web.StreamResponse:
    ip      = request.headers.get("X-Forwarded-For", request.remote or "?")
    path    = request.path
    method  = request.method
    t0      = time.time()
    req_id  = str(uuid.uuid4())[:8]

    body_bytes = await request.read()
    model = "-"; prompt = "-"; is_stream = False

    try:
        bj = json.loads(body_bytes) if body_bytes else {}
        model     = bj.get("model", "-")
        is_stream = bj.get("stream", True)
        if "messages" in bj:
            content = bj["messages"][-1].get("content", "")
            prompt  = content[:300].replace("\n", " ")
        elif "prompt" in bj:
            prompt  = bj["prompt"][:300].replace("\n", " ")
    except Exception:
        pass

    target = OLLAMA_URL + path
    if request.query_string:
        target += "?" + request.query_string

    headers = {k: v for k, v in request.headers.items()
               if k.lower() not in ("host", "content-length")}

    response_text = "-"
    status = 502
    elapsed = 0

    try:
        async with aiohttp.ClientSession() as session:
            async with session.request(method, target, headers=headers, data=body_bytes) as resp:
                resp_body = await resp.read()
                status    = resp.status
                elapsed   = round((time.time() - t0) * 1000)

                try:
                    ct = resp.content_type or ""
                    if "json" in ct and "ndjson" not in ct:
                        rj = json.loads(resp_body)
                        if "message" in rj:
                            response_text = rj["message"].get("content", "")[:300].replace("\n"," ")
                        elif "response" in rj:
                            response_text = rj["response"][:300].replace("\n"," ")
                        elif "models" in rj:
                            names = [m.get("name","") for m in rj["models"]]
                            response_text = "models: " + ", ".join(names)
                    elif "ndjson" in ct:
                        lines = resp_body.decode("utf-8","replace").strip().split("\n")
                        chunks = []
                        for ln in lines:
                            try:
                                obj = json.loads(ln)
                                c = ""
                                if "message" in obj:
                                    c = obj["message"].get("content","")
                                elif "response" in obj:
                                    c = obj["response"]
                                if c:
                                    chunks.append(c)
                            except Exception:
                                pass
                        response_text = "".join(chunks)[:300].replace("\n"," ")
                except Exception:
                    pass

                out_headers = {k: v for k, v in resp.headers.items()
                               if k.lower() not in ("content-encoding","transfer-encoding","content-length")}
                result = web.Response(status=status, headers=out_headers, body=resp_body)
    except aiohttp.ClientConnectorError:
        result = web.Response(status=502, text="Ollama bağlantı hatası")

    # Kayıt
    record = {
        "id":       req_id,
        "ts":       datetime.now().isoformat(timespec="milliseconds"),
        "ip":       ip,
        "method":   method,
        "path":     path,
        "model":    model,
        "stream":   is_stream,
        "status":   status,
        "ms":       elapsed,
        "prompt":   prompt,
        "response": response_text,
    }
    recent_requests.appendleft(record)
    stats["total"] += 1
    stats["total_ms"] += elapsed
    if status >= 400:
        stats["errors"] += 1

    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

    asyncio.create_task(broadcast({"type": "request", "data": record}))
    return result

# ── Dashboard HTML ───────────────────────────────────────────
DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ollama Monitor</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  :root{
    --bg:#0d1117;--surface:#161b22;--surface2:#1c2128;--border:#30363d;
    --text:#e6edf3;--muted:#7d8590;--accent:#58a6ff;--green:#3fb950;
    --orange:#d29922;--red:#f85149;--purple:#bc8cff;
  }
  body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;font-size:14px;min-height:100vh}
  header{background:var(--surface);border-bottom:1px solid var(--border);padding:14px 24px;display:flex;align-items:center;gap:16px;position:sticky;top:0;z-index:10}
  header h1{font-size:16px;font-weight:600;color:var(--accent)}
  .dot{width:8px;height:8px;border-radius:50%;background:var(--green);box-shadow:0 0 6px var(--green);animation:pulse 2s infinite}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.5}}
  .stats{display:flex;gap:24px;margin-left:auto}
  .stat{text-align:center}
  .stat-val{font-size:20px;font-weight:700;color:var(--accent)}
  .stat-lbl{font-size:11px;color:var(--muted);margin-top:2px}
  .container{max-width:1400px;margin:0 auto;padding:20px 24px}
  .toolbar{display:flex;gap:10px;margin-bottom:16px;align-items:center;flex-wrap:wrap}
  input[type=text]{background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:7px 12px;color:var(--text);font-size:13px;width:220px;outline:none}
  input[type=text]:focus{border-color:var(--accent)}
  select{background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:7px 10px;color:var(--text);font-size:13px;outline:none;cursor:pointer}
  button{background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:7px 14px;color:var(--text);font-size:13px;cursor:pointer;transition:.15s}
  button:hover{border-color:var(--accent);color:var(--accent)}
  button.danger:hover{border-color:var(--red);color:var(--red)}
  .badge{display:inline-block;padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600}
  .badge-green{background:#1e3a2a;color:var(--green)}
  .badge-red{background:#3d1a1a;color:var(--red)}
  .badge-orange{background:#3a2a1a;color:var(--orange)}
  .badge-blue{background:#1a2a3d;color:var(--accent)}
  table{width:100%;border-collapse:collapse;font-size:13px}
  thead th{background:var(--surface);border-bottom:1px solid var(--border);padding:10px 12px;text-align:left;color:var(--muted);font-weight:600;font-size:12px;white-space:nowrap;position:sticky;top:57px;z-index:5}
  tbody tr{border-bottom:1px solid var(--border);cursor:pointer;transition:.1s}
  tbody tr:hover{background:var(--surface2)}
  tbody tr.new-row{animation:flash .6s ease}
  @keyframes flash{0%{background:#1a2a3d}100%{background:transparent}}
  td{padding:10px 12px;vertical-align:top;max-width:0}
  .td-ts{white-space:nowrap;color:var(--muted);font-size:12px;width:130px}
  .td-ip{white-space:nowrap;width:130px;font-family:monospace}
  .td-model{white-space:nowrap;width:160px;color:var(--purple)}
  .td-status{width:60px}
  .td-ms{width:70px;text-align:right;color:var(--muted)}
  .td-prompt{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--muted)}
  .td-response{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .empty{text-align:center;padding:60px;color:var(--muted)}

  /* Detail modal */
  .modal-bg{display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:100;align-items:center;justify-content:center}
  .modal-bg.open{display:flex}
  .modal{background:var(--surface);border:1px solid var(--border);border-radius:10px;width:min(760px,95vw);max-height:85vh;overflow-y:auto;padding:24px}
  .modal h2{font-size:15px;margin-bottom:16px;color:var(--accent)}
  .modal-close{float:right;background:none;border:none;color:var(--muted);font-size:18px;cursor:pointer;line-height:1}
  .field{margin-bottom:14px}
  .field label{display:block;font-size:11px;color:var(--muted);margin-bottom:4px;font-weight:600;text-transform:uppercase;letter-spacing:.5px}
  .field pre{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:12px;white-space:pre-wrap;word-break:break-word;font-size:13px;max-height:220px;overflow-y:auto;line-height:1.5}
  .meta-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:10px;margin-bottom:16px}
  .meta-item{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:10px}
  .meta-item .v{font-size:16px;font-weight:700;color:var(--text)}
  .meta-item .l{font-size:11px;color:var(--muted);margin-top:2px}
</style>
</head>
<body>

<header>
  <div class="dot" id="dot"></div>
  <h1>Ollama Monitor</h1>
  <div class="stats">
    <div class="stat"><div class="stat-val" id="s-total">0</div><div class="stat-lbl">Toplam</div></div>
    <div class="stat"><div class="stat-val" id="s-avg">—</div><div class="stat-lbl">Ort. süre</div></div>
    <div class="stat"><div class="stat-val" id="s-errors" style="color:var(--red)">0</div><div class="stat-lbl">Hata</div></div>
  </div>
</header>

<div class="container">
  <div class="toolbar">
    <input type="text" id="filter-ip" placeholder="IP filtrele…" oninput="applyFilter()">
    <input type="text" id="filter-model" placeholder="Model filtrele…" oninput="applyFilter()">
    <select id="filter-status" onchange="applyFilter()">
      <option value="">Tüm durumlar</option>
      <option value="2">2xx Başarılı</option>
      <option value="4">4xx Hata</option>
      <option value="5">5xx Sunucu hatası</option>
    </select>
    <button onclick="clearRows()" class="danger">Temizle</button>
    <span style="margin-left:auto;color:var(--muted);font-size:12px" id="count-label"></span>
  </div>

  <table>
    <thead>
      <tr>
        <th>Zaman</th>
        <th>IP</th>
        <th>Model</th>
        <th>Durum</th>
        <th style="text-align:right">Süre</th>
        <th>Prompt</th>
        <th>Yanıt</th>
      </tr>
    </thead>
    <tbody id="tbody">
      <tr><td colspan="7" class="empty" id="empty-row">Henüz istek yok — diğer cihazdan bağlan</td></tr>
    </tbody>
  </table>
</div>

<!-- Modal -->
<div class="modal-bg" id="modal-bg" onclick="closeModal(event)">
  <div class="modal" id="modal">
    <button class="modal-close" onclick="closeModal()">✕</button>
    <h2 id="modal-title">İstek Detayı</h2>
    <div class="meta-grid" id="modal-meta"></div>
    <div class="field"><label>Prompt</label><pre id="modal-prompt"></pre></div>
    <div class="field"><label>Yanıt</label><pre id="modal-response"></pre></div>
  </div>
</div>

<script>
let allRows = [];
let statsData = {total:0, errors:0, total_ms:0};

const $ = id => document.getElementById(id);
const tbody = $('tbody');

function statusBadge(s){
  if(s>=200&&s<300) return `<span class="badge badge-green">${s}</span>`;
  if(s>=400&&s<500) return `<span class="badge badge-orange">${s}</span>`;
  if(s>=500)        return `<span class="badge badge-red">${s}</span>`;
  return `<span class="badge badge-blue">${s}</span>`;
}

function msColor(ms){
  if(ms<500)  return 'var(--green)';
  if(ms<2000) return 'var(--orange)';
  return 'var(--red)';
}

function timeStr(ts){
  return ts.split('T')[1].substring(0,12);
}

function truncate(s, n){ return s&&s.length>n ? s.substring(0,n)+'…' : (s||'-'); }

function renderRow(r, prepend=false){
  const tr = document.createElement('tr');
  if(prepend) tr.classList.add('new-row');
  tr.dataset.id = r.id;
  tr.innerHTML = `
    <td class="td-ts">${timeStr(r.ts)}</td>
    <td class="td-ip"><code>${r.ip}</code></td>
    <td class="td-model">${r.model}</td>
    <td class="td-status">${statusBadge(r.status)}</td>
    <td class="td-ms" style="color:${msColor(r.ms)}">${r.ms}ms</td>
    <td class="td-prompt">${truncate(r.prompt,80)}</td>
    <td class="td-response">${truncate(r.response,80)}</td>
  `;
  tr.onclick = () => openModal(r);
  return tr;
}

function applyFilter(){
  const fIp    = $('filter-ip').value.toLowerCase();
  const fModel = $('filter-model').value.toLowerCase();
  const fSt    = $('filter-status').value;
  const visible = allRows.filter(r =>
    (!fIp    || r.ip.includes(fIp)) &&
    (!fModel || r.model.toLowerCase().includes(fModel)) &&
    (!fSt    || String(r.status).startsWith(fSt))
  );
  tbody.innerHTML = '';
  if(visible.length===0){
    tbody.innerHTML = '<tr><td colspan="7" class="empty">Filtreyle eşleşen istek yok</td></tr>';
  } else {
    visible.forEach(r => tbody.appendChild(renderRow(r)));
  }
  $('count-label').textContent = `${visible.length} / ${allRows.length} istek`;
}

function addRow(r){
  allRows.unshift(r);
  const emptyRow = $('empty-row');
  if(emptyRow) emptyRow.remove();
  const fIp    = $('filter-ip').value.toLowerCase();
  const fModel = $('filter-model').value.toLowerCase();
  const fSt    = $('filter-status').value;
  const show = (!fIp||r.ip.includes(fIp)) && (!fModel||r.model.toLowerCase().includes(fModel)) && (!fSt||String(r.status).startsWith(fSt));
  if(show) tbody.insertBefore(renderRow(r,true), tbody.firstChild);
  $('count-label').textContent = `${tbody.querySelectorAll('tr:not(.empty)').length} / ${allRows.length} istek`;
}

function updateStats(s){
  $('s-total').textContent = s.total;
  $('s-errors').textContent = s.errors;
  $('s-avg').textContent = s.total>0 ? Math.round(s.total_ms/s.total)+'ms' : '—';
}

function clearRows(){
  allRows=[];
  tbody.innerHTML='<tr><td colspan="7" class="empty">Temizlendi</td></tr>';
  $('count-label').textContent='';
}

function openModal(r){
  $('modal-title').textContent = `İstek — ${r.id}`;
  $('modal-meta').innerHTML = [
    ['Zaman', timeStr(r.ts)],
    ['IP', r.ip],
    ['Model', r.model],
    ['Durum', r.status],
    ['Süre', r.ms+'ms'],
    ['Path', r.path],
    ['Stream', r.stream?'Evet':'Hayır'],
  ].map(([l,v])=>`<div class="meta-item"><div class="v">${v}</div><div class="l">${l}</div></div>`).join('');
  $('modal-prompt').textContent   = r.prompt   || '-';
  $('modal-response').textContent = r.response || '-';
  $('modal-bg').classList.add('open');
}

function closeModal(e){
  if(!e||e.target===$('modal-bg')) $('modal-bg').classList.remove('open');
}

document.addEventListener('keydown', e=>{ if(e.key==='Escape') closeModal(); });

// ── WebSocket ───────────────────────────────────────────────
function connect(){
  const ws = new WebSocket(`ws://${location.host}/ws`);
  const dot = $('dot');

  ws.onopen = ()=>{ dot.style.background='var(--green)'; dot.style.boxShadow='0 0 6px var(--green)'; };
  ws.onclose= ()=>{ dot.style.background='var(--red)';   dot.style.boxShadow='0 0 6px var(--red)';   setTimeout(connect,2000); };

  ws.onmessage = e => {
    const msg = JSON.parse(e.data);
    if(msg.type==='request'){
      addRow(msg.data);
    } else if(msg.type==='init'){
      msg.requests.forEach(r=>{ allRows.push(r); });
      applyFilter();
      updateStats(msg.stats);
    } else if(msg.type==='stats'){
      updateStats(msg.data);
    }
  };
}
connect();
</script>
</body>
</html>"""

# ── Dashboard WebSocket ──────────────────────────────────────
async def ws_handler(request: web.Request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    ws_clients.add(ws)

    # Mevcut kayıtları gönder
    await ws.send_str(json.dumps({
        "type": "init",
        "requests": list(recent_requests),
        "stats": stats,
    }, ensure_ascii=False))

    try:
        async for _ in ws:
            pass
    finally:
        ws_clients.discard(ws)
    return ws


async def dashboard_handler(request: web.Request):
    return web.Response(text=DASHBOARD_HTML, content_type="text/html")


async def stats_broadcast_loop():
    while True:
        await asyncio.sleep(5)
        await broadcast({"type": "stats", "data": dict(stats)})


async def main():
    # Proxy app
    proxy_app = web.Application(client_max_size=100 * 1024 * 1024)
    proxy_app.router.add_route("*", "/{path_info:.*}", proxy_handler)

    proxy_runner = web.AppRunner(proxy_app)
    await proxy_runner.setup()
    await web.TCPSite(proxy_runner, "0.0.0.0", PROXY_PORT).start()

    # Monitor app
    mon_app = web.Application()
    mon_app.router.add_get("/", dashboard_handler)
    mon_app.router.add_get("/ws", ws_handler)

    mon_runner = web.AppRunner(mon_app)
    await mon_runner.setup()
    await web.TCPSite(mon_runner, "0.0.0.0", MONITOR_PORT).start()

    asyncio.create_task(stats_broadcast_loop())

    print(f"\n{'='*50}")
    print(f"  Ollama Monitor çalışıyor")
    print(f"{'='*50}")
    print(f"  Proxy   → 0.0.0.0:{PROXY_PORT}  (diğer cihazlar buraya bağlanır)")
    print(f"  Ollama  → {OLLAMA_URL}")
    print(f"  Dashboard → http://localhost:{MONITOR_PORT}")
    print(f"  Tailscale → http://100.97.45.128:{MONITOR_PORT}")
    print(f"  Log       → {LOG_FILE}")
    print(f"{'='*50}\n")
    print("  Durdurmak için: Ctrl+C\n")

    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(main())
