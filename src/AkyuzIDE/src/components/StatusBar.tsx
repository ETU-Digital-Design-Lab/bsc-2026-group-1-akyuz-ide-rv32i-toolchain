import React, { useState, useEffect } from 'react';
import { Layers, Globe, Wifi, WifiOff } from 'lucide-react';
import { api } from '../services/api';

type ConnState = 'connected' | 'disconnected' | 'checking';

const StatusBar = () => {
  const [conn, setConn] = useState<ConnState>('checking');
  const [workspace, setWorkspace] = useState<string>('');

  useEffect(() => {
    let cancelled = false;

    const check = async () => {
      try {
        const data = await api.getHealth();
        if (cancelled) return;
        setConn('connected');
        if (data.workspace) {
          setWorkspace(data.workspace.split(/[/\\]/).pop() || '');
        }
      } catch {
        if (!cancelled) setConn('disconnected');
      }
    };

    check();
    const id = setInterval(check, 4000);
    return () => { cancelled = true; clearInterval(id); };
  }, []);

  const connMeta = {
    connected:    { icon: <Wifi size={11} className="text-[#32cd32]" />, label: 'Backend Connected',    dot: 'bg-[#32cd32] shadow-[0_0_6px_#32cd32]' },
    disconnected: { icon: <WifiOff size={11} className="text-red-400" />, label: 'Backend Disconnected', dot: 'bg-red-500 shadow-[0_0_6px_#ef4444]' },
    checking:     { icon: <Wifi size={11} className="text-yellow-400 animate-pulse" />, label: 'Bağlanıyor…',        dot: 'bg-yellow-400 animate-pulse' },
  }[conn];

  return (
    <div className="h-[22px] bg-status-bg text-white flex items-center px-4 justify-between text-[11px] font-medium shrink-0 select-none shadow-[0_-2px_10px_rgba(0,0,0,0.3)]">
      <div className="flex items-center h-full">
        <div className="flex items-center gap-2 hover:bg-white/10 px-3 h-full cursor-pointer transition-colors">
          <Globe size={11} />
          <span className="tracking-tight">AkyuzIDE Station</span>
        </div>

        {/* ── Dinamik bağlantı göstergesi ── */}
        <div className="flex items-center gap-2 hover:bg-white/10 px-3 h-full cursor-pointer transition-colors">
          <span className={`w-[7px] h-[7px] rounded-full shrink-0 ${connMeta.dot}`} />
          {connMeta.icon}
          <span className="tracking-tight">{connMeta.label}</span>
        </div>

        {workspace && (
          <div className="flex items-center gap-2 hover:bg-white/10 px-3 h-full cursor-pointer transition-colors">
            <Layers size={11} />
            <span className="tracking-tight">{workspace}</span>
          </div>
        )}
      </div>

      <div className="flex items-center gap-4">
        <div className="flex items-center gap-2">
          <span className="opacity-70">Ln 1, Col 1</span>
          <span className="opacity-70">Spaces: 4</span>
        </div>
        <div className="flex items-center gap-2 font-bold tracking-tight">
          <span>UTF-8</span>
          <span>Verilog HDL</span>
        </div>
        <span className="font-semibold px-1 rounded hover:bg-white/10 transition-colors cursor-pointer">v2.0.0-beta</span>
      </div>
    </div>
  );
};

export default StatusBar;
