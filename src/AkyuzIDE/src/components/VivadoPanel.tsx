import React, { useState } from 'react';
import { RefreshCw, Layers, Zap, Radio, PlaySquare, Info } from 'lucide-react';
import { api } from '../services/api';

const VivadoPanel = () => {
  const [selectedBoard, setSelectedBoard] = useState('basys3');
  const [projectStage, setProjectStage] = useState<string>('Design');
  const [isLoading, setIsLoading] = useState(false);
  const [buildStatus, setBuildStatus] = useState<string | null>(null);

  const boards = [
    { id: 'basys3', name: 'Basys 3 (xc7a35t)' },
    { id: 'arty_a7_35t', name: 'Arty A7-35T' },
    { id: 'nexys_a7_100t', name: 'Nexys A7-100T' },
  ];

  const handleAnalyze = async () => {
    setIsLoading(true);
    try {
      const res = await api.getProjectPlan();
      (window as any).dispatchEvent(new CustomEvent('insert-chat', { detail: res.plan }));
      setProjectStage(res.plan.includes('Synthesis') ? 'Synthesis' : 'Design');
    } catch (err) {
      console.error("Failed to analyze project", err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleBuild = async () => {
    setBuildStatus('Building...');
    try {
      // In a real flow, the agent would have prepared the list of files
      const res = await api.vivadoBuild(['counter.v', 'counter.xdc'], 'counter', 'xc7a35tcpg236-1');
      if (res.success) setBuildStatus('Success');
      else setBuildStatus('Failed');
    } catch (err) {
      setBuildStatus('Error');
    }
  };

  return (
    <div className="w-full bg-bg-sidebar flex flex-col h-full select-none">
      <div className="px-4 py-2 text-[10px] font-bold uppercase text-text-dim tracking-widest border-b border-border-ide/30 mb-4">
        VIVADO OPERATIONS
      </div>

      <div className="px-4 space-y-6">
        {/* Project Stage Card */}
        <div className="p-3 bg-accent-ide/5 border border-accent-ide/20 rounded-lg space-y-3 relative group overflow-hidden shadow-inner">
           <div className="absolute top-0 right-0 w-16 h-16 bg-accent-ide/10 blur-2xl rounded-full -mr-8 -mt-8 group-hover:bg-accent-ide/20 transition-all" />
           <div className="flex justify-between items-center relative z-10">
              <span className="text-[9px] text-text-dim uppercase font-black tracking-widest">Stage</span>
              <span className="text-[11px] text-black font-black px-2 py-0.5 bg-accent-ide rounded shadow-[0_0_10px_rgba(0,184,212,0.4)] uppercase">
                 {projectStage}
              </span>
           </div>
           <button 
              onClick={handleAnalyze}
              disabled={isLoading}
              className="w-full py-2 bg-[#2d2d30] hover:bg-[#3e3e42] text-white border border-white/5 rounded text-[11px] font-bold hover:brightness-110 active:scale-95 transition-all flex items-center justify-center gap-2 relative z-10"
           >
              {isLoading ? <RefreshCw size={12} className="animate-spin" /> : <Layers size={12} />}
              Analyze & Plan
           </button>
        </div>

        {/* Board Selection */}
        <div className="space-y-2">
           <label className="text-[10px] text-text-dim uppercase font-bold flex items-center gap-1">
              <Info size={10} /> Target Board
           </label>
           <select 
              value={selectedBoard}
              onChange={(e) => setSelectedBoard(e.target.value)}
              className="w-full bg-bg-main border border-white/10 rounded px-2 py-1.5 text-[11px] text-white focus:outline-none focus:border-accent-ide"
           >
              {boards.map(b => (
                 <option key={b.id} value={b.id} className="bg-bg-sidebar">{b.name}</option>
              ))}
           </select>
        </div>

        {/* Action Buttons */}
        <div className="space-y-2 pt-4 border-t border-border-ide/30">
           <button 
              onClick={handleBuild}
              className="w-full py-2 bg-[#3e3e42] hover:bg-[#4e4e52] text-white rounded text-[11px] font-bold transition-all flex items-center justify-center gap-2"
           >
              <Zap size={14} className="text-accent-ide" />
              {buildStatus || 'Build Project'}
           </button>
           <button className="w-full py-2 bg-[#3e3e42] hover:bg-[#4e4e52] text-white rounded text-[11px] font-bold transition-all flex items-center justify-center gap-2">
              <PlaySquare size={14} className="text-success-ide" />
              Program FPGA
           </button>
        </div>

        <div className="text-[10px] text-text-dim leading-relaxed opacity-50 pt-4">
           Project mode is active. All builds generate a persistent .xpr file compatible with Xilinx Vivado Desktop.
        </div>
      </div>
    </div>
  );
};

export default VivadoPanel;
