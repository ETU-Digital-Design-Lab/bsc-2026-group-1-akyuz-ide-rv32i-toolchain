import React, { useState, useEffect, useRef } from 'react';
import { Activity, X, ZoomIn, ZoomOut, ChevronDown, ChevronRight } from 'lucide-react';

function resolveWaveformBase(): string {
  const savedBackend = typeof window !== 'undefined' ? localStorage.getItem('akyuz_backend_url') : null;
  if (savedBackend && savedBackend.trim()) return savedBackend.replace(/\/$/, '');

  const savedOllama = typeof window !== 'undefined' ? localStorage.getItem('akyuz_ollama_host') : null;
  if (savedOllama && savedOllama.trim()) {
    try {
      const url = new URL(savedOllama);
      return `${url.protocol}//${url.hostname}:8001`;
    } catch (e) {
      const host = savedOllama.replace(/^https?:\/\//, '').split(':')[0];
      return `http://${host}:8001`;
    }
  }
  return 'http://127.0.0.1:8001';
}
const BASE_URL = { toString() { return resolveWaveformBase(); } };

interface SignalChange { time: number; value: string; }
interface Signal { name: string; width: number; module: string; changes: SignalChange[]; }
interface WaveformData { timescale: string; end_time: number; signals: Signal[]; error?: string; }

function WaveRow({ signal, endTime, zoom, pixelsPerUnit }: {
  signal: Signal; endTime: number; zoom: number; pixelsPerUnit: number;
}) {
  const totalWidth = Math.max(endTime * pixelsPerUnit * zoom, 400);
  const height = 24;
  const segments: { x: number; w: number; val: string }[] = [];

  for (let i = 0; i < signal.changes.length; i++) {
    const t0 = signal.changes[i].time;
    const t1 = i + 1 < signal.changes.length ? signal.changes[i + 1].time : endTime;
    const x = t0 * pixelsPerUnit * zoom;
    const w = Math.max((t1 - t0) * pixelsPerUnit * zoom, 1);
    segments.push({ x, w, val: signal.changes[i].value });
  }

  const color = (val: string) => {
    if (val === '1' || val === '1') return '#34d399';
    if (val === '0') return '#6b7280';
    if (val.startsWith('x') || val.startsWith('X')) return '#f87171';
    if (val.startsWith('z') || val.startsWith('Z')) return '#a78bfa';
    return '#60a5fa';
  };

  return (
    <svg width={totalWidth} height={height} className="block">
      {segments.map((seg, i) => {
        const isBit = signal.width === 1;
        const high = seg.val === '1';
        if (isBit) {
          const y = high ? 4 : 16;
          const yPrev = i > 0 ? (segments[i - 1].val === '1' ? 4 : 16) : y;
          return (
            <g key={i}>
              {i > 0 && <line x1={seg.x} y1={yPrev} x2={seg.x} y2={y} stroke={color(seg.val)} strokeWidth={1.5} />}
              <line x1={seg.x} y1={y} x2={seg.x + seg.w} y2={y} stroke={color(seg.val)} strokeWidth={1.5} />
            </g>
          );
        }
        return (
          <g key={i}>
            <rect x={seg.x + 1} y={4} width={Math.max(seg.w - 2, 1)} height={16} fill={color(seg.val)} fillOpacity={0.15} stroke={color(seg.val)} strokeWidth={1} rx={2} />
            {seg.w > 20 && (
              <text x={seg.x + 4} y={16} fontSize={9} fill={color(seg.val)} fontFamily="monospace">
                {seg.val.length > 8 ? seg.val.slice(0, 7) + '…' : seg.val}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

export default function WaveformViewer({ vcdPath, onClose }: { vcdPath: string; onClose: () => void }) {
  const [data, setData] = useState<WaveformData | null>(null);
  const [loading, setLoading] = useState(true);
  const [zoom, setZoom] = useState(1);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const scrollRef = useRef<HTMLDivElement>(null);
  const pixelsPerUnit = 0.5;

  useEffect(() => {
    setLoading(true);
    fetch(`${BASE_URL}/api/waveform?path=${encodeURIComponent(vcdPath)}`)
      .then(r => r.json())
      .then(d => { setData(d); setLoading(false); })
      .catch(e => { setData({ error: String(e), timescale: '', end_time: 0, signals: [] }); setLoading(false); });
  }, [vcdPath]);

  const modules = data ? [...new Set(data.signals.map(s => s.module))] : [];

  return (
    <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4">
      <div className="bg-bg-main border border-white/10 rounded-xl shadow-2xl w-full max-w-5xl h-[80vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center gap-2 px-4 py-2.5 border-b border-white/10 shrink-0">
          <Activity size={16} className="text-accent-ide" />
          <span className="text-[12px] font-semibold text-white">Dalga Görüntüleyici</span>
          <span className="text-[10px] text-white/40 font-mono truncate flex-1">{vcdPath.split('/').pop()}</span>
          {data && !data.error && (
            <span className="text-[10px] text-white/40">
              {data.signals.length} sinyal · {data.timescale} · {data.end_time} birim
            </span>
          )}
          <div className="flex items-center gap-1 ml-2">
            <button onClick={() => setZoom(z => Math.max(0.2, z - 0.2))} className="p-1 rounded hover:bg-white/10 text-white/60 hover:text-white">
              <ZoomOut size={13} />
            </button>
            <span className="text-[10px] text-white/40 w-10 text-center">{Math.round(zoom * 100)}%</span>
            <button onClick={() => setZoom(z => Math.min(8, z + 0.2))} className="p-1 rounded hover:bg-white/10 text-white/60 hover:text-white">
              <ZoomIn size={13} />
            </button>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-white/10 text-white/50 hover:text-white ml-1">
            <X size={14} />
          </button>
        </div>

        {/* Body */}
        {loading ? (
          <div className="flex-1 flex items-center justify-center text-white/40 text-[12px]">VCD yükleniyor…</div>
        ) : data?.error ? (
          <div className="flex-1 flex items-center justify-center text-red-400/70 text-[11px] px-8 text-center">{data.error}</div>
        ) : (
          <div className="flex-1 overflow-hidden flex">
            {/* Signal names */}
            <div className="w-44 shrink-0 border-r border-white/10 overflow-y-auto bg-[#181818]">
              <div className="h-6 border-b border-white/10 px-2 flex items-center text-[9px] text-white/30 font-mono uppercase">Sinyal</div>
              {modules.map(mod => (
                <div key={mod}>
                  <button
                    onClick={() => setCollapsed(c => { const n = new Set(c); n.has(mod) ? n.delete(mod) : n.add(mod); return n; })}
                    className="flex items-center gap-1 w-full px-2 py-0.5 text-[10px] text-white/50 hover:bg-white/5 font-mono"
                  >
                    {collapsed.has(mod) ? <ChevronRight size={10} /> : <ChevronDown size={10} />}
                    {mod}
                  </button>
                  {!collapsed.has(mod) && data!.signals.filter(s => s.module === mod).map(sig => (
                    <div key={sig.name} className="px-3 h-6 flex items-center text-[10px] text-white/70 font-mono border-b border-white/5 hover:bg-white/5">
                      <span className="truncate" title={sig.name}>{sig.name}</span>
                      {sig.width > 1 && <span className="ml-1 text-white/30 text-[8px]">[{sig.width}]</span>}
                    </div>
                  ))}
                </div>
              ))}
            </div>
            {/* Waveforms */}
            <div ref={scrollRef} className="flex-1 overflow-auto bg-[#161618]">
              <div className="h-6 border-b border-white/10 flex items-center text-[9px] text-white/30 font-mono px-2 sticky top-0 bg-[#161618] z-10">
                Zaman ({data!.timescale})
              </div>
              {modules.map(mod => (
                <div key={mod}>
                  <div className="h-[22px] bg-white/3" />
                  {!collapsed.has(mod) && data!.signals.filter(s => s.module === mod).map(sig => (
                    <div key={sig.name} className="h-6 border-b border-white/5 overflow-hidden">
                      <WaveRow signal={sig} endTime={data!.end_time} zoom={zoom} pixelsPerUnit={pixelsPerUnit} />
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
