import React, { useState, useEffect, useRef, useMemo } from 'react';
import { AlertCircle, Terminal as TermIcon, FileText, Bug, CheckCircle2, Activity } from 'lucide-react';

export interface LogEntry {
  ts: string;   // "HH:MM:SS"
  text: string;
}

interface TerminalProps {
  logs: LogEntry[];
  onCommand?: (cmd: string) => void;
}

const PS_HEADER = [
  'PowerShell Extension v2025.4.0',
  'Copyright (c) Microsoft Corporation.',
  '',
  'https://aka.ms/vscode-powershell',
  "Type 'help' to get help.",
  '',
];

const Terminal = ({ logs, onCommand }: TerminalProps) => {
  const [activeTab, setActiveTab] = useState('Terminal');
  const [input, setInput] = useState('');
  const [history, setHistory] = useState<string[]>([]);
  const [historyIdx, setHistoryIdx] = useState(-1);
  const scrollRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  const tabs = [
    { id: 'Problems',      icon: <AlertCircle size={13} /> },
    { id: 'Output',        icon: <FileText size={13} /> },
    { id: 'Debug Console', icon: <Bug size={13} /> },
    { id: 'Terminal',      icon: <TermIcon size={13} /> },
    { id: 'Aktivite',      icon: <Activity size={13} /> },
  ];

  const filteredLogs = useMemo((): LogEntry[] => {
    if (activeTab === 'Problems') {
      return logs.filter(l =>
        l.text.toLowerCase().includes('error') ||
        l.text.toLowerCase().includes('failed') ||
        l.text.toLowerCase().includes('warning')
      );
    }
    if (activeTab === 'Output') {
      return logs.filter(l =>
        l.text.includes('SIMULATION') ||
        l.text.includes('COMPILATION') ||
        l.text.includes('Binary:') ||
        l.text.includes('$finish') ||
        l.text.includes('Time ') ||
        l.text.includes('[System]') ||
        l.text.includes('exit code')
      );
    }
    if (activeTab === 'Debug Console') {
      return logs.filter(l =>
        l.text.startsWith('>') || l.text.startsWith('[error]') || l.text.startsWith('[agent') || l.text.startsWith('$ ')
      );
    }
    if (activeTab === 'Aktivite') {
      return logs; // tüm kayıtlar — filtresiz
    }
    // Terminal: kullanıcı komutları + sistem mesajları
    return logs.filter(l => !l.text.startsWith('>') && !l.text.startsWith('[agent'));
  }, [logs, activeTab]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [filteredLogs, activeTab]);

  const handleAreaKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
      e.preventDefault();
      e.stopPropagation();
      const el = contentRef.current;
      if (!el) return;
      const range = document.createRange();
      range.selectNodeContents(el);
      const sel = window.getSelection();
      sel?.removeAllRanges();
      sel?.addRange(range);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && input.trim()) {
      onCommand?.(input);
      setHistory(prev => [input, ...prev]);
      setHistoryIdx(-1);
      setInput('');
    } else if (e.key === 'ArrowUp') {
      const idx = Math.min(historyIdx + 1, history.length - 1);
      setHistoryIdx(idx);
      setInput(history[idx] ?? '');
    } else if (e.key === 'ArrowDown') {
      const idx = historyIdx - 1;
      if (idx < 0) { setHistoryIdx(-1); setInput(''); }
      else { setHistoryIdx(idx); setInput(history[idx]); }
    }
  };

  const errorCount = logs.filter(l =>
    l.text.toLowerCase().includes('error') || l.text.toLowerCase().includes('failed')
  ).length;
  const warningCount = logs.filter(l => l.text.toLowerCase().includes('warning')).length;

  const renderLine = (entry: LogEntry, i: number) => {
    const log = entry.text;
    const isError   = log.toLowerCase().includes('error') || log.includes('FAILED');
    const isWarning = log.toLowerCase().includes('warning');
    const isToolCall = log.startsWith('>');
    const isCmd     = log.startsWith('$ ');
    const isSuccess = log.includes('SUCCESSFUL') || log.includes('OK:') || log.includes('✓');
    const isSimOut  = log.includes('Time ') || log.includes('$finish');
    const showTs    = activeTab === 'Aktivite';

    return (
      <div key={i} className={`flex gap-1.5 leading-relaxed items-start text-[11.5px] ${
        isError   ? 'text-[#f14c4c]' :
        isWarning ? 'text-[#cca700]' :
        isToolCall ? 'text-emerald-400/85' :
        isCmd      ? 'text-[#4fc1ff] font-semibold' :
        isSuccess  ? 'text-emerald-300/90' :
        isSimOut   ? 'text-cyan-300/80' :
        'text-[#cccccc]'
      }`}>
        {showTs && (
          <span className="text-white/20 shrink-0 select-none text-[10px] mt-px min-w-[56px]">{entry.ts}</span>
        )}
        {activeTab === 'Problems' && <AlertCircle size={12} className="mt-0.5 shrink-0 text-[#f14c4c]" />}
        {isToolCall && <span className="text-emerald-400/40 shrink-0 mt-px">▶</span>}
        <span className="whitespace-pre-wrap break-all select-text">
          {isToolCall ? log.slice(2) : log}
        </span>
      </div>
    );
  };

  return (
    <div className="h-full bg-bg-main border-t border-border-ide flex flex-col overflow-hidden">

      {/* Tab Header */}
      <div className="flex gap-0 px-1 h-[34px] items-center bg-bg-sidebar shrink-0 border-b border-border-ide/30">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`cursor-pointer h-full px-3.5 flex items-center gap-1.5 text-[10.5px] font-semibold transition-all relative select-none whitespace-nowrap ${
              activeTab === tab.id
                ? 'text-white bg-bg-main shadow-[0_-2px_0_inset_#00d4ff]'
                : 'text-text-dim hover:text-text-main hover:bg-white/5'
            }`}
          >
            {tab.icon}
            <span className="tracking-tight">{tab.id}</span>
            {tab.id === 'Problems' && errorCount > 0 && (
              <span className="bg-[#f14c4c] text-white rounded-full px-1 text-[9px] font-black min-w-[16px] text-center">
                {errorCount}
              </span>
            )}
            {tab.id === 'Problems' && warningCount > 0 && errorCount === 0 && (
              <span className="bg-[#cca700] text-black rounded-full px-1 text-[9px] font-black min-w-[16px] text-center">
                {warningCount}
              </span>
            )}
            {tab.id === 'Aktivite' && logs.length > 0 && (
              <span className="text-white/25 text-[9px] font-normal">{logs.length}</span>
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      <div
        ref={scrollRef}
        tabIndex={0}
        onKeyDown={handleAreaKeyDown}
        className="flex-1 overflow-y-auto bg-[#0c0c0c] focus:outline-none"
      >
        <div ref={contentRef} className="p-3 font-mono">
          {/* Terminal tab: PS header */}
          {activeTab === 'Terminal' && (
            <div className="mb-1">
              {PS_HEADER.map((line, i) => (
                <div key={i} className="text-[11.5px] text-[#cccccc] leading-relaxed select-text whitespace-pre">
                  {line || ' '}
                </div>
              ))}
            </div>
          )}

          {/* Aktivite tab: başlık */}
          {activeTab === 'Aktivite' && logs.length > 0 && (
            <div className="mb-2 pb-1 border-b border-white/5 flex items-center justify-between">
              <span className="text-[9px] text-white/25 uppercase tracking-widest">Tam Aktivite Kaydı</span>
              <span className="text-[9px] text-white/20">{logs.length} kayıt</span>
            </div>
          )}

          {filteredLogs.length > 0 ? (
            <div className="flex flex-col gap-px mb-6">
              {filteredLogs.map((entry, i) => renderLine(entry, i))}
            </div>
          ) : activeTab !== 'Terminal' ? (
            <div className="flex flex-col items-center justify-center py-10 text-[#555] gap-3 select-none">
              <CheckCircle2 size={28} strokeWidth={1.2} />
              <span className="text-[10px] uppercase tracking-widest">
                {activeTab === 'Problems' ? 'Sorun yok' :
                 activeTab === 'Aktivite' ? 'Henüz kayıt yok' : 'Çıktı yok'}
              </span>
            </div>
          ) : null}
        </div>
      </div>

      {/* PS Prompt — Terminal tab only */}
      {activeTab === 'Terminal' && (
        <div className="px-3 py-1.5 flex items-center gap-0 bg-[#0c0c0c] border-t border-white/[0.06] shrink-0 font-mono">
          <span className="text-[#4ec9b0] text-[11.5px] mr-1 select-none">PS</span>
          <span className="text-[#4fc1ff] text-[11.5px] mr-1 select-none">
            C:\Users\Taha\Desktop\AkyuzIde
          </span>
          <span className="text-white/70 text-[11.5px] mr-2 select-none">&gt;</span>
          <input
            type="text"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            spellCheck={false}
            autoFocus
            className="flex-1 bg-transparent border-none text-[11.5px] text-white focus:outline-none caret-white"
            placeholder=""
          />
        </div>
      )}
    </div>
  );
};

export default Terminal;
