import React from 'react';
import { FilePlus, FolderOpen, GitBranch, Clock } from 'lucide-react';

interface WelcomePageProps {
  recentFolders?: string[];
}

const WelcomePage = ({ recentFolders = [] }: WelcomePageProps) => {
  // Format recent folders for display
  const items = recentFolders.map(path => {
    const name = path.split(/[/\\]/).pop() || path;
    return { name, path };
  });

  const displayItems = items;

  const handleAction = (cmd: string, data?: any) => {
    if (data) {
       window.dispatchEvent(new CustomEvent('top-menu-action', { detail: { type: cmd, path: data.path } }));
    } else {
       window.dispatchEvent(new CustomEvent('top-menu-action', { detail: cmd }));
    }
  };

  return (
    <div className="flex-1 h-full bg-bg-main overflow-y-auto flex flex-col p-12 select-none animate-in fade-in duration-700">
      <div className="max-w-[800px] mx-auto w-full flex flex-col gap-10">
        
        <div>
          <h1 className="text-3xl font-light text-white/90 mb-1">AkyuzIDE</h1>
          <p className="text-lg text-text-dim/60 font-light italic">Editing evolved</p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-16">
          {/* Start Section */}
          <div className="flex flex-col gap-6">
            <h2 className="text-sm font-semibold text-white/40 uppercase tracking-widest mb-2 border-b border-white/5 pb-2">Start</h2>
            
            <button 
              onClick={() => handleAction('new file')} 
              className="flex items-center gap-3 text-accent-ide hover:text-white transition-all group hover:translate-x-1"
            >
              <FilePlus size={20} className="group-hover:scale-110 transition-transform" />
              <span className="text-[15px]">New File...</span>
            </button>

            <button 
              onClick={() => handleAction('open file...')} 
              className="flex items-center gap-3 text-accent-ide hover:text-white transition-all group hover:translate-x-1"
            >
              <FolderOpen size={20} className="group-hover:scale-110 transition-transform" />
              <span className="text-[15px]">Open File...</span>
            </button>

            <button 
              onClick={() => handleAction('open folder...')} 
              className="flex items-center gap-3 text-accent-ide hover:text-white transition-all group hover:translate-x-1"
            >
              <FolderOpen size={20} className="group-hover:scale-110 transition-transform" />
              <span className="text-[15px]">Open Folder...</span>
            </button>

            <button 
              onClick={() => handleAction('clone git repository')}
              className="flex items-center gap-3 text-accent-ide hover:text-white transition-all group hover:translate-x-1"
            >
              <GitBranch size={20} className="group-hover:scale-110 transition-transform" />
              <span className="text-[15px]">Clone Git Repository...</span>
            </button>
          </div>

          {/* Recent Section */}
          <div className="flex flex-col gap-6">
            <h2 className="text-sm font-semibold text-white/40 uppercase tracking-widest mb-2 flex items-center gap-2 border-b border-white/5 pb-2">
              <Clock size={14} />
              Recent
            </h2>
            <div className="flex flex-col gap-4">
              {displayItems.map((item, idx) => (
                <div
                  key={idx}
                  onClick={() => handleAction('open folder...', item)}
                  className="flex flex-col group cursor-pointer hover:translate-x-1 transition-all"
                >
                  <span className="text-[14px] text-accent-ide group-hover:text-white transition-colors truncate">{item.name}</span>
                  <span className="text-[11px] text-text-dim/30 truncate">{item.path}</span>
                </div>
              ))}
              {displayItems.length === 0 && (
                <div className="text-[12px] text-text-dim/45 italic">
                  Henüz son kullanılan klasör yok. "Open Folder..." ile bir klasör açabilirsin.
                </div>
              )}
              <button 
                onClick={() => handleAction('open recent')}
                className="text-[12px] text-text-dim/40 hover:text-white mt-2 self-start transition-colors"
              >
                More...
              </button>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-12 pt-10 border-t border-white/5 flex items-center justify-center">
          <label className="flex items-center gap-2 cursor-pointer group">
            <input type="checkbox" defaultChecked className="w-3.5 h-3.5 accent-accent-ide bg-transparent border border-white/20 rounded" />
            <span className="text-[12px] text-text-dim/40 group-hover:text-white transition-colors">Show welcome page on startup</span>
          </label>
        </div>
      </div>
    </div>
  );
};

export default WelcomePage;
