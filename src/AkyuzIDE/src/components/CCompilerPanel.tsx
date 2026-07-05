import React, { useState, useEffect } from 'react';
import { RefreshCw, Cpu, Zap, Radio, CheckCircle2, AlertCircle, Terminal as SerialIcon } from 'lucide-react';
import { api } from '../services/api';

const CCompilerPanel = () => {
  const [ports, setPorts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [selectedPort, setSelectedPort] = useState<string | null>(null);
  const [status, setStatus] = useState<{ msg: string, type: 'info' | 'success' | 'error' } | null>(null);

  const scanPorts = async () => {
    setIsLoading(true);
    try {
      const data = await api.getPorts();
      setPorts(data);
      if (data.length > 0 && !selectedPort) setSelectedPort(data[0].port);
    } catch (err) {
      console.error('Failed to scan ports:', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    scanPorts();
  }, []);

  const showStatus = (msg: string, type: 'info' | 'success' | 'error' = 'info') => {
    setStatus({ msg, type });
    if (type !== 'info') setTimeout(() => setStatus(null), 5000);
  };

  const handleCompile = async () => {
    const file = window.prompt("Derlenecek C dosyası:", "main.c");
    if (!file) return;
    
    showStatus('Derleniyor...', 'info');
    try {
      const res = await api.compileFile(file);
      if (res.success) {
        showStatus('Derleme Başarılı!', 'success');
      } else {
        showStatus('Hata: ' + res.log, 'error');
        // Show log in terminal
        window.dispatchEvent(new CustomEvent('terminal-output', { detail: res.log }));
      }
    } catch (err: any) {
      showStatus('Sistem Hatası: ' + err.message, 'error');
    }
  };

  const handleUpload = async () => {
    if (!selectedPort) {
        showStatus('Lütfen bir port seçin', 'error');
        return;
    }
    showStatus('Yükleniyor...', 'info');
    try {
      // The build path is relative to workspace root in our hardware service
      await api.uploadFile(selectedPort, '_hardware/_build/program.bin');
      showStatus('Yükleme Başarılı!', 'success');
    } catch (err: any) {
      showStatus('Yükleme Başarısız: ' + err.message, 'error');
    }
  };

  const handleOpenSerial = () => {
    if (!selectedPort) {
        showStatus('Lütfen bir port seçin', 'error');
        return;
    }
    // For now, we'll just log it. A real serial monitor modal would be next.
    showStatus(`${selectedPort} Serial Monitor açılıyor...`, 'info');
    window.dispatchEvent(new CustomEvent('terminal-output', { detail: `\n--- Serial Monitor Opened on ${selectedPort} (115200) ---\n` }));
  };

  return (
    <div className="w-full bg-bg-sidebar flex flex-col h-full select-none">
      <div className="px-4 py-2 text-[10px] font-bold uppercase text-text-dim tracking-widest border-b border-border-ide/30 mb-4 flex justify-between items-center">
        <span>HARDWARE & C</span>
        <button onClick={scanPorts} className="hover:text-white transition-colors">
           <RefreshCw size={12} className={isLoading ? 'animate-spin' : ''} />
        </button>
      </div>

      <div className="px-4 space-y-6 overflow-y-auto custom-scrollbar">
        {/* Connection Status */}
        <div className="space-y-2">
           <div className="text-[10px] uppercase font-bold text-text-dim flex items-center gap-1">
              <Radio size={12} className="text-accent-ide" /> Connected Devices
           </div>
           
           {ports.length === 0 ? (
             <div className="text-text-dim text-[11px] italic py-4 text-center bg-black/10 rounded flex flex-col items-center gap-2">
                <AlertCircle size={16} className="opacity-20" />
                No devices found.
             </div>
           ) : (
             <div className="flex flex-col gap-1">
               {ports.map((port) => (
                 <div 
                   key={port.port}
                   onClick={() => setSelectedPort(port.port)}
                   className={`p-2 rounded cursor-pointer border transition-all flex items-center gap-2 ${
                     selectedPort === port.port 
                       ? 'bg-accent-ide/10 border-accent-ide/40 text-white' 
                       : 'bg-[#2a2a2d]/50 border-transparent text-text-dim hover:text-white hover:border-white/10'
                   }`}
                 >
                   <Cpu size={14} className={port.is_fpga ? 'text-success-ide' : 'text-text-dim'} />
                   <div className="flex flex-col leading-tight overflow-hidden">
                     <span className="font-bold truncate text-[11px]">{port.port}</span>
                     <span className="text-[9px] opacity-40 truncate">{port.description}</span>
                   </div>
                   {selectedPort === port.port && <CheckCircle2 size={10} className="ml-auto text-accent-ide" />}
                 </div>
               ))}
             </div>
           )}
        </div>

        {/* Build Section */}
        <div className="space-y-2 pt-4 border-t border-border-ide/30">
           <div className="text-[10px] uppercase font-bold text-text-dim flex justify-between items-center">
              <span>C Toolchain</span>
              {status && (
                <span className={`text-[9px] font-bold ${status.type === 'error' ? 'text-red-400' : status.type === 'success' ? 'text-green-400' : 'text-accent-ide'}`}>
                  {status.msg}
                </span>
              )}
           </div>
           <button 
              onClick={handleCompile}
              className="w-full py-2 bg-[#3e3e42] hover:bg-[#4e4e52] text-white rounded text-[11px] font-bold transition-all flex items-center justify-center gap-2 active:scale-95"
           >
              <Zap size={14} className="text-accent-ide" />
              Compile Firmware (GCC)
           </button>
           <button 
              onClick={handleUpload}
              disabled={!selectedPort || (status?.type === 'info' && status.msg === 'Yükleniyor...')}
              className="w-full py-2 bg-accent-ide hover:brightness-110 text-black rounded text-[11px] font-bold transition-all flex items-center justify-center gap-2 active:scale-95 disabled:opacity-50"
           >
              <Zap size={14} fill="currentColor" />
              Upload to Hardware
           </button>
        </div>

        <div className="space-y-2">
           <button 
              onClick={handleOpenSerial}
              className="w-full py-2 border border-border-ide hover:bg-white/5 text-text-dim hover:text-white rounded text-[11px] font-bold transition-all flex items-center justify-center gap-2"
           >
              <SerialIcon size={14} />
              Open Serial Monitor
           </button>
        </div>

        <div className="text-[9px] text-text-dim leading-relaxed opacity-40 pt-4">
           Bundled RISC-V GCC toolchain is active. Ensure your C code has a proper crt0 and linker script for target SoC.
        </div>
      </div>
    </div>
  );
};

export default CCompilerPanel;
