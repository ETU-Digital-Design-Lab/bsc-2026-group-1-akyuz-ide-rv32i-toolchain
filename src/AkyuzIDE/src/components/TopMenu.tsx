import React, { useState, useRef, useEffect } from 'react';
import { Layers, MessageSquare, Download, RefreshCw } from 'lucide-react';

interface TopMenuProps {
  onAction?: (cmd: string) => void;
  showChat?: boolean;
  onToggleChat?: () => void;
}

const TopMenu = ({ onAction, showChat, onToggleChat }: TopMenuProps) => {
  const [openMenu, setOpenMenu] = useState<string | null>(null);
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [updateDownloaded, setUpdateDownloaded] = useState(false);
  const [updateVersion, setUpdateVersion] = useState('');
  const menuRef = useRef<HTMLDivElement>(null);

  const menuItems = [
    { 
      label: 'File', 
      items: [
        'New Text File', 'New File...', 'New Window', 'New Window with Profile',
        '---',
        'Open File...', 'Open Folder...', 'Open Workspace from File...', 'Open Recent',
        '---',
        'Add Folder to Workspace...', 'Save Workspace As...', 'Duplicate Workspace',
        '---',
        'Save', 'Save As...', 'Save All',
        '---',
        'Share',
        '---',
        'Auto Save', 'Preferences',
        '---',
        'Revert File', 'Close Editor', 'Close Folder', 'Close Window',
        '---',
        'Exit'
      ] 
    },
    { 
      label: 'Edit', 
      items: [
        'Undo', 'Redo',
        '---',
        'Cut', 'Copy', 'Paste',
        '---',
        'Find', 'Replace',
        '---',
        'Find in Files', 'Replace in Files',
        '---',
        'Toggle Line Comment', 'Toggle Block Comment', 'Emmet: Expand Abbreviation'
      ] 
    },
    { 
      label: 'Terminal', 
      items: [
        'New Terminal', 'Split Terminal', 'New Terminal Window',
        '---',
        'Run Task...', 'Run Build Task...', 'Run Active File', 'Run Selected Text',
        '---',
        'Show Running Tasks...', 'Restart Running Task...', 'Terminate Task...',
        '---',
        'Configure Tasks...', 'Configure Default Build Task...'
      ] 
    },
  ];

  const shortcuts: Record<string, string> = {
    'New Text File': 'Ctrl+N',
    'New File...': 'Ctrl+Alt+Win+N',
    'New Window': 'Ctrl+Shift+N',
    'Open File...': 'Ctrl+O',
    'Open Folder...': 'Ctrl+K Ctrl+O',
    'Save': 'Ctrl+S',
    'Save As...': 'Ctrl+Shift+S',
    'Save All': 'Ctrl+K S',
    'Close Editor': 'Ctrl+F4',
    'Close Folder': 'Ctrl+K F',
    'Close Window': 'Alt+F4',
    'Undo': 'Ctrl+Z',
    'Redo': 'Ctrl+Y',
    'Cut': 'Ctrl+X',
    'Copy': 'Ctrl+C',
    'Paste': 'Ctrl+V',
    'Find': 'Ctrl+F',
    'Replace': 'Ctrl+H',
    'Find in Files': 'Ctrl+Shift+F',
    'Replace in Files': 'Ctrl+Shift+H',
    'Toggle Line Comment': 'Ctrl+/',
    'Toggle Block Comment': 'Shift+Alt+A',
    'Emmet: Expand Abbreviation': 'Tab',
    'New Terminal': 'Ctrl+Shift+`',
    'Split Terminal': 'Ctrl+Shift+5',
    'New Terminal Window': 'Ctrl+Shift+Alt+`',
    'Run Build Task...': 'Ctrl+Shift+B',
  };

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setOpenMenu(null);
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  useEffect(() => {
    const ipc = (window as any).ipcRenderer;
    if (!ipc) return;

    const onAvailable = (_: any, info: any) => {
      setUpdateAvailable(true);
      setUpdateVersion(info.version ?? '');
    };
    const onDownloaded = (_: any, info: any) => {
      setUpdateDownloaded(true);
      setUpdateVersion(info.version ?? '');
    };

    ipc.on('update-available', onAvailable);
    ipc.on('update-downloaded', onDownloaded);
    return () => {
      ipc.off('update-available', onAvailable);
      ipc.off('update-downloaded', onDownloaded);
    };
  }, []);

  const handleInstallUpdate = () => {
    (window as any).ipcRenderer?.send('install-update');
  };

  const handleAction = (item: string) => {
    if (item === '---') return;
    setOpenMenu(null);
    onAction?.(item);
  };

  return (
    <div className="h-full w-full bg-bg-sidebar flex items-center px-1 text-[12px] select-none" style={{borderBottom:'1px solid rgba(0,212,255,0.08)'}} ref={menuRef}>
      <div className="flex items-center gap-1 pr-3 mr-1 border-r border-border-ide ml-1">
        <img src="./logo.png" alt="AkyuzIDE" className="w-5 h-5 object-contain" />
      </div>

      <div className="flex items-center gap-0.5">
        {menuItems.map(menu => (
          <div key={menu.label} className="relative">
            <span
              style={{ WebkitAppRegion: 'no-drag' } as any}
              onMouseEnter={() => openMenu && setOpenMenu(menu.label)}
              onClick={() => setOpenMenu(prev => prev === menu.label ? null : menu.label)}
              className={`text-text-main hover:text-white cursor-pointer px-2.5 py-1 rounded transition-colors font-medium ${openMenu === menu.label ? 'bg-accent-ide/20 text-white' : 'hover:bg-white/5'}`}
            >
              {menu.label}
            </span>
            {openMenu === menu.label && (
              <div
                style={{ WebkitAppRegion: 'no-drag' } as any}
                className="absolute top-full left-0 mt-0.5 w-[240px] bg-bg-sidebar border border-border-ide shadow-2xl z-[9999] py-1"
                style={{boxShadow:'0 8px 32px rgba(0,0,0,0.6), 0 0 0 1px rgba(0,212,255,0.08)'}}
              >
                {menu.items.map((item, idx) => (
                  item === '---' ? (
                    <div key={`sep-${idx}`} className="h-[1px] bg-border-ide my-1 mx-3" />
                  ) : (
                    <div
                      key={item}
                      onClick={() => handleAction(item)}
                      className="px-3 py-1.5 hover:bg-accent-ide hover:text-white cursor-pointer flex justify-between items-center group"
                    >
                      <span className="text-[12px]">{item}</span>
                      <span className="text-[10px] opacity-40 group-hover:opacity-100">{shortcuts[item] || ''}</span>
                    </div>
                  )
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="ml-auto flex items-center gap-3 pr-2">
        <div className="flex items-center gap-1.5 text-text-dim text-[11px] font-medium opacity-60">
          <Layers size={11} className="text-accent-ide" />
          <span>Main Branch</span>
        </div>

        {updateDownloaded && (
          <button
            onClick={handleInstallUpdate}
            title={`v${updateVersion} hazır — yeniden başlatıp yükle`}
            style={{ WebkitAppRegion: 'no-drag' } as any}
            className="flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-medium bg-green-600 hover:bg-green-500 text-white transition-colors"
          >
            <RefreshCw size={11} />
            <span>Güncelle v{updateVersion}</span>
          </button>
        )}

        {updateAvailable && !updateDownloaded && (
          <div
            title={`v${updateVersion} indiriliyor…`}
            className="flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-medium text-yellow-400 opacity-70"
          >
            <Download size={11} className="animate-pulse" />
            <span>İndiriliyor…</span>
          </div>
        )}

        <button
          onClick={onToggleChat}
          title="AI Paneli Aç/Kapat"
          style={{ WebkitAppRegion: 'no-drag' } as any}
          className={`p-1 rounded transition-all ${showChat ? 'text-accent-ide bg-accent-ide/10' : 'text-text-dim hover:text-white hover:bg-white/10'}`}
        >
          <MessageSquare size={13} />
        </button>
      </div>
    </div>
  );
};

export default TopMenu;
