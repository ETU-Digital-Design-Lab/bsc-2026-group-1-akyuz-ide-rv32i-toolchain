import React from 'react';
import { Files, Cpu, Layers } from 'lucide-react';

interface ActivityBarProps {
  activeTab: string;
  setActiveTab: (tab: string) => void;
}

const ActivityBar = ({ activeTab, setActiveTab }: ActivityBarProps) => {
  const tabs = [
    { id: 'explorer', icon: Files, label: 'Explorer' },
    { id: 'vivado', icon: Layers, label: 'Vivado Operations' },
    { id: 'hardware', icon: Cpu, label: 'Hardware & C-Compiler' },
  ];

  return (
    <div className="w-[48px] bg-bg-activity flex flex-col items-center py-4 border-r border-border-ide shrink-0 select-none" style={{boxShadow:'inset -1px 0 0 rgba(0,212,255,0.08)'}}>
      <div className="flex flex-col gap-4 w-full">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <div 
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              title={tab.label}
              className={`relative flex items-center justify-center h-12 w-full cursor-pointer transition-all group`}
            >
              {isActive && (
                <div className="absolute left-0 w-[2px] h-full bg-accent-ide" />
              )}
              <Icon 
                size={22} 
                className={`transition-colors ${isActive ? 'text-white' : 'text-text-dim group-hover:text-white/80'}`} 
                strokeWidth={1.5}
              />
            </div>
          );
        })}
      </div>

    </div>
  );
};

export default ActivityBar;
