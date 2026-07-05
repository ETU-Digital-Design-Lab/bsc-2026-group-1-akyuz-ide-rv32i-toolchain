import React, { useState, useEffect } from 'react';
import { RefreshCw, Cpu, Zap, Radio, CheckCircle2, AlertCircle, PlaySquare } from 'lucide-react';
import { api } from '../services/api';

const HardwareSidebar = () => {
  const [ports, setPorts] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [selectedPort, setSelectedPort] = useState<string | null>(null);
  const [uploadStatus, setUploadStatus] = useState<string | null>(null);
  const [lastLogPath, setLastLogPath] = useState<string | null>(null);
  const [flow, setFlow] = useState<'serial' | 'vivado'>('serial');
  const [selectedBoard, setSelectedBoard] = useState('basys3');
  const [projectStage, setProjectStage] = useState<string>('Design');

  const boards = [
    { id: 'basys3', name: 'Basys 3 (xc7a35t)' },
    { id: 'arty_a7_35t', name: 'Arty A7-35T' },
    { id: 'nexys_a7_100t', name: 'Nexys A7-100T' },
  ];

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

  const handleUpload = async () => {
    setUploadStatus('Processing...');
    setLastLogPath(null);
    try {
      if (flow === 'serial') {
        if (!selectedPort) return;
        await api.uploadFile(selectedPort, 'workspace/_hardware/program.bin');
        setUploadStatus('Upload Success!');
      } else {
        setUploadStatus('Building FPGA...');
        // AI will handle file discovery in the future, for now we assume counter project
        // In a real autonomous flow, the agent would have prepared these already
        const res = await api.vivadoBuild(['counter.v', 'counter.xdc'], 'counter', 'xc7a35tcpg236-1'); // Fallback part
        
        if (res.success) {
           setUploadStatus('Build Success!');
           setLastLogPath(res.log_path);
        } else {
           setUploadStatus('Build Failed');
           setLastLogPath(res.log_path);
        }
      }
    } catch (err: any) {
      setUploadStatus(`Error: ${err.message}`);
    } finally {
      // Don't auto-clear if there's a log to view
      if (!lastLogPath) setTimeout(() => setUploadStatus(null), 3000);
    }
  };

  const handleViewLog = async () => {
    if (!lastLogPath) return;
    try {
      const log = await api.getVivadoFullLog(lastLogPath);
      // For now, we print it to the terminal console or open in a new tab/modal
      // In this modernized IDE, we'll send it to the terminal
      (window as any).dispatchEvent(new CustomEvent('terminal-output', { detail: log }));
    } catch (err) {
      console.error('Failed to load log', err);
    }
  };

  return (
    <div className="flex flex-col h-full bg-[#252526] text-[13px]">
      <div className="p-3 uppercase font-bold text-[11px] text-text-dim flex justify-between items-center bg-[#252526] border-b border-border-ide">
        <span>Hardware Manager</span>
        <button 
          onClick={scanPorts} 
          disabled={isLoading}
          className="hover:text-white transition-colors disabled:opacity-30"
        >
          <RefreshCw size={14} className={isLoading ? 'animate-spin' : ''} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <div className="flex bg-black/20 p-1 rounded-lg">
          <button 
            onClick={() => setFlow('serial')}
            className={`flex-1 py-1.5 rounded-md text-[11px] font-bold transition-all ${flow === 'serial' ? 'bg-accent-ide text-black' : 'text-text-dim hover:text-white'}`}
          >
            Serial Flow
          </button>
          <button 
            onClick={() => setFlow('vivado')}
            className={`flex-1 py-1.5 rounded-md text-[11px] font-bold transition-all ${flow === 'vivado' ? 'bg-accent-ide text-black' : 'text-text-dim hover:text-white'}`}
          >
            Vivado Flow
          </button>
        </div>

        {flow === 'vivado' && (
          <div className="py-2 px-3 bg-accent-ide/10 border border-accent-ide/20 rounded-md flex justify-between items-center">
             <div className="flex flex-col">
               <span className="text-[9px] text-text-dim uppercase font-bold">Project Stage</span>
               <span className="text-[12px] text-accent-ide font-bold">{projectStage}</span>
             </div>
             <button 
                onClick={async () => {
                   const res = await api.getProjectPlan();
                   // Emit event or show in chat
                   (window as any).dispatchEvent(new CustomEvent('insert-chat', { detail: res.plan }));
                   setProjectStage(res.plan.includes('Synthesis') ? 'Synthesis' : 'Design');
                }}
                className="bg-accent-ide text-black text-[10px] px-2 py-1 rounded font-bold hover:brightness-110 active:scale-95 transition-all"
             >
                Analyze & Plan
             </button>
          </div>
        )}

        <div className="space-y-2">
          <div className="text-[10px] uppercase font-bold text-text-dim flex items-center gap-1">
             <Radio size={12} className="text-accent-ide" />
             {flow === 'serial' ? 'Connected Devices' : 'FPGA Target'}
          </div>
          
          {ports.length === 0 ? (
            <div className="text-text-dim text-[11px] italic py-4 text-center bg-black/10 rounded flex flex-col items-center gap-2">
               <AlertCircle size={20} className="opacity-20" />
               No devices found. Plug in your FPGA or COM device.
            </div>
          ) : (
            <div className="flex flex-col gap-1">
              {ports.map((port) => (
                <div 
                  key={port.port}
                  onClick={() => setSelectedPort(port.port)}
                  className={`p-2 rounded cursor-pointer border transition-all flex items-center gap-3 ${
                    selectedPort === port.port 
                      ? 'bg-accent-ide/10 border-accent-ide/40 text-white' 
                      : 'bg-[#2a2a2d] border-transparent text-text-dim hover:text-white hover:border-white/10'
                  }`}
                >
                  <Cpu size={16} className={port.is_fpga ? 'text-success-ide' : 'text-text-dim'} />
                  <div className="flex flex-col leading-tight overflow-hidden">
                    <span className="font-bold truncate text-[12px]">{port.port}</span>
                    <span className="text-[10px] opacity-60 truncate">{port.description}</span>
                  </div>
                  {selectedPort === port.port && <CheckCircle2 size={12} className="ml-auto text-accent-ide" />}
                </div>
              ))}
            </div>
          )}
        </div>

        {flow === 'vivado' && (
          <div className="space-y-2">
             <div className="text-[10px] uppercase font-bold text-text-dim">Target FPGA Board</div>
             <select 
               value={selectedBoard}
               onChange={(e) => setSelectedBoard(e.target.value)}
               className="w-full bg-black/20 border border-white/5 rounded px-2 py-1.5 text-[11px] text-white focus:outline-none focus:border-accent-ide cursor-pointer"
             >
               {boards.map(b => (
                 <option key={b.id} value={b.id} className="bg-[#252526]">{b.name}</option>
               ))}
             </select>
          </div>
        )}

        {(selectedPort || flow === 'vivado') && (
          <div className="pt-4 border-t border-border-ide space-y-3 animate-in fade-in duration-500">
             <div className="flex justify-between items-center">
               <div className="text-[10px] uppercase font-bold text-text-dim">Device Actions</div>
               {lastLogPath && (
                 <button 
                   onClick={handleViewLog}
                   className="text-[10px] text-accent-ide hover:underline cursor-pointer flex items-center gap-1"
                 >
                   <PlaySquare size={10} /> View Full Log
                 </button>
               )}
             </div>
             <button 
                onClick={handleUpload}
                disabled={!!uploadStatus}
                className="w-full bg-accent-ide hover:brightness-110 text-black font-bold py-2 rounded flex items-center justify-center gap-2 transition-all active:scale-95 disabled:opacity-50"
             >
                <Zap size={16} fill="black" />
                {uploadStatus || 'Upload to Hardware'}
             </button>
             <button className="w-full bg-[#3e3e42] hover:bg-[#4e4e52] text-white py-2 rounded flex items-center justify-center gap-2 transition-colors active:scale-95">
                <PlaySquare size={16} />
                Open Serial Monitor
             </button>
          </div>
        )}
      </div>

      <div className="p-4 bg-black/10 text-[10px] text-text-dim leading-relaxed">
         <p>Hardware Station v1.0. Connect your device via USB to scan. Compatible with RV32I bootloaders.</p>
      </div>
    </div>
  );
};

export default HardwareSidebar;
