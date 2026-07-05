import React, { useState, useEffect, useRef, useCallback } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { Minus, Maximize2, X, Sun, Moon } from 'lucide-react';

// Import our modular components
import ActivityBar from './components/ActivityBar';
import Sidebar from './components/Sidebar';
import VivadoPanel from './components/VivadoPanel';
import CCompilerPanel from './components/CCompilerPanel';
import Editor from './components/Editor';
import Terminal, { LogEntry } from './components/Terminal';
import ChatPanel from './components/ChatPanel';
import TopMenu from './components/TopMenu';
import StatusBar from './components/StatusBar';

import { api } from './services/api';

function makeLog(text: string): LogEntry {
  const now = new Date();
  const ts = now.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  return { ts, text };
}

// TitleBar is now a simple wrapper for window controls
const WindowControls = () => {
  const handleControl = (command: string) => {
    // @ts-ignore
    window.ipcRenderer?.send('window-control', command);
  };

  return (
    <div className="flex items-center gap-4 opacity-70 ml-auto pr-3" style={{ WebkitAppRegion: 'no-drag' } as any}>
        <Minus
          size={14}
          className="cursor-pointer hover:opacity-100 hover:bg-white/10 p-0.5 rounded"
          onClick={() => handleControl('minimize')}
        />
        <Maximize2
          size={12}
          className="cursor-pointer hover:opacity-100 hover:bg-white/10 p-0.5 rounded"
          onClick={() => handleControl('maximize')}
        />
        <X
          size={14}
          className="cursor-pointer hover:text-red-500 hover:bg-red-500/10 p-0.5 rounded"
          onClick={() => handleControl('close')}
        />
    </div>
  );
};

export default function App() {
  const [theme, setTheme] = useState<'dark' | 'cream'>(
    () => (localStorage.getItem('akyuz_theme') as 'dark' | 'cream') || 'dark'
  );

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('akyuz_theme', theme);
  }, [theme]);

  const toggleTheme = () => setTheme(t => t === 'dark' ? 'cream' : 'dark');

  const [activeActivity, setActiveActivity] = useState<string | null>(null);
  const [sidebarWidth, setSidebarWidth] = useState(240);
  const [terminalHeight, setTerminalHeight] = useState(0);
  const [chatWidth, setChatWidth] = useState(() => Math.max(320, Math.min(420, Math.round(window.innerWidth * 0.28))));
  const [isResizingSidebar, setIsResizingSidebar] = useState(false);
  const [isResizingTerminal, setIsResizingTerminal] = useState(false);
  const [isResizingChat, setIsResizingChat] = useState(false);
  
  const [openFiles, setOpenFiles] = useState<string[]>([]);
  const [activeFile, setActiveFile] = useState<string>('');
  const [showChat, setShowChat] = useState(false);
  const [terminalLogs, setTerminalLogs] = useState<LogEntry[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [workspaceName, setWorkspaceName] = useState<string>('AkyuzIDE');
  const [refreshKey, setRefreshKey] = useState(0);

  const fetchHealth = async () => {
    try {
      const data = await api.getHealth();
      if (data.workspace) {
        const name = data.workspace.split(/[/\\]/).pop() || data.workspace;
        setWorkspaceName(name);
      }
    } catch (e) { console.error(e); }
  };

  useEffect(() => {
    fetchHealth();
    const handleWorkspaceRefresh = () => fetchHealth();
    window.addEventListener('workspace-changed', handleWorkspaceRefresh);
    return () => window.removeEventListener('workspace-changed', handleWorkspaceRefresh);
  }, []);

  const handleRefreshExplorer = useCallback(() => {
    setRefreshKey(prev => prev + 1);
    window.dispatchEvent(new CustomEvent('refresh-explorer'));
  }, []);

  const handleOpenFile = useCallback((path: string) => {
    if (!openFiles.includes(path)) {
      setOpenFiles(prev => [...prev, path]);
    }
    setActiveFile(path);
    if (!activeActivity) setActiveActivity('explorer');
  }, [openFiles, activeActivity]);

  const handleCloseFile = useCallback((path: string) => {
    const newFiles = openFiles.filter(f => f !== path);
    setOpenFiles(newFiles);
    if (activeFile === path && newFiles.length > 0) {
      setActiveFile(newFiles[newFiles.length - 1]);
    } else if (newFiles.length === 0) {
      setActiveFile('');
    }
  }, [openFiles, activeFile]);

  const handleSaveFile = useCallback(async (content: string, fileName?: string) => {
    const targetFile = fileName || activeFile;
    if (!targetFile) return;
    
    setIsSaving(true);
    try {
      await api.writeFile(targetFile, content);
      setTerminalLogs(prev => [...prev, makeLog(`[System] File ${targetFile} saved successfully.`)]);
      handleRefreshExplorer();
      if (fileName) {
        setOpenFiles(prev => !prev.includes(fileName) ? [...prev, fileName] : prev);
        setActiveFile(fileName);
        setActiveActivity('explorer');
      }
    } catch (err: any) {
      setTerminalLogs(prev => [...prev, makeLog(`[Error] Failed to save: ${err.message}`)]);
    } finally {
      setIsSaving(false);
    }
  }, [activeFile, handleRefreshExplorer]);

  const handleRunSimulation = useCallback(async () => {
    setTerminalLogs(prev => [...prev, makeLog('$ Simülasyon başlatılıyor — workspace taranıyor...')]);
    try {
      const result = await api.runSimulationAuto();
      if (result.files?.length) {
        setTerminalLogs(prev => [...prev, makeLog(`Dosyalar: ${result.files.join(', ')}`)]);
      }
      setTerminalLogs(prev => [...prev, makeLog(result.log ?? JSON.stringify(result))]);
    } catch (err: any) {
      setTerminalLogs(prev => [...prev, makeLog(`Error: ${err.message}`)]);
    }
  }, []);

  const runAgentInTerminal = useCallback(async (msg: string) => {
    const ollamaHost = localStorage.getItem('akyuz_ollama_host') || 'http://127.0.0.1:11434';
    const modeModels = (() => { try { return JSON.parse(localStorage.getItem('akyuz_mode_models') || '{}'); } catch { return {}; } })();
    const modelId = modeModels.agent || 'qwen3:latest';
    setTerminalLogs(prev => [...prev, makeLog(`[agent] ${msg}`)]);
    try {
      const res = await api.agentChat(msg, ollamaHost, modelId, '', '');
      const reply: string = (res as any).reply || (res as any).content || JSON.stringify(res);
      setTerminalLogs(prev => [...prev, makeLog(reply)]);
    } catch (err: any) {
      setTerminalLogs(prev => [...prev, makeLog(`[agent hata] ${err.message}`)]);
    }
  }, []);

  const TERMINAL_HELP = [
    'Agent komutları:',
    '  agent <mesaj>        → AI agenta mesaj gönder',
    '  listele              → Workspace dosyalarını listele',
    '  derle <dosya.v>      → iverilog ile Verilog derle',
    '  simule <dosya.v> [tb.v]  → Simülasyon çalıştır',
    '  oku <dosya>          → Dosya içeriğini göster',
    '  yeni klasör <ad>     → Klasör oluştur',
    '  yeni dosya <ad>      → Dosya oluştur',
    '',
    'Shell komutları (direkt çalışır):',
    '  ls / dir             → Dizin listesi',
    '  mkdir <ad>           → Klasör oluştur',
    '  cat <dosya>          → Dosya içeriği',
    '  pwd / cd             → Dizin işlemleri',
    '  help / yardım        → Bu yardım mesajı',
  ].join('\n');

  const handleTerminalCommand = useCallback(async (cmd: string) => {
    const trimmed = cmd.trim();
    if (!trimmed) return;
    setTerminalLogs(prev => [...prev, makeLog(`$ ${trimmed}`)]);

    const low = trimmed.toLowerCase();

    // ── help ──────────────────────────────────────────────────────
    if (low === 'help' || low === 'yardım') {
      setTerminalLogs(prev => [...prev, makeLog(TERMINAL_HELP)]);
      return;
    }

    // ── agent <mesaj> ─────────────────────────────────────────────
    if (low.startsWith('agent ')) {
      await runAgentInTerminal(trimmed.slice(6).trim());
      return;
    }

    // ── listele ───────────────────────────────────────────────────
    if (low === 'listele') {
      await runAgentInTerminal('workspace dosyalarını listele');
      return;
    }

    // ── derle <dosya.v> ───────────────────────────────────────────
    if (low.startsWith('derle ')) {
      const file = trimmed.slice(6).trim();
      await runAgentInTerminal(`${file} dosyasını iverilog ile derle`);
      return;
    }

    // ── simule <dosya.v> [<tb.v>] ─────────────────────────────────
    if (low.startsWith('simule ')) {
      const args = trimmed.slice(7).trim();
      await runAgentInTerminal(`${args} ile simülasyon çalıştır`);
      return;
    }

    // ── oku <dosya> ───────────────────────────────────────────────
    if (low.startsWith('oku ')) {
      const file = trimmed.slice(4).trim();
      await runAgentInTerminal(`${file} dosyasını oku ve içeriğini göster`);
      return;
    }

    // ── yeni klasör/dosya ─────────────────────────────────────────
    if (low.startsWith('yeni klasör ') || low.startsWith('yeni klasor ')) {
      const name = trimmed.split(' ').slice(2).join(' ').trim();
      await runAgentInTerminal(`${name} klasörü oluştur`);
      return;
    }
    if (low.startsWith('yeni dosya ')) {
      const name = trimmed.slice(11).trim();
      await runAgentInTerminal(`${name} dosyası oluştur`);
      return;
    }

    // ── shell komutları ───────────────────────────────────────────
    try {
      const res = await api.runTerminalCommand(trimmed);
      if (res.stdout?.trim()) setTerminalLogs(prev => [...prev, makeLog(res.stdout.trimEnd())]);
      if (res.stderr?.trim()) setTerminalLogs(prev => [...prev, makeLog(res.stderr.trimEnd())]);
      if (!res.stdout?.trim() && !res.stderr?.trim()) setTerminalLogs(prev => [...prev, makeLog('[ok]')]);
    } catch (err: any) {
      setTerminalLogs(prev => [...prev, makeLog(`[Hata] ${err.message}`)]);
    }
  }, [runAgentInTerminal, TERMINAL_HELP]);

  const [autoSave, setAutoSave] = useState(false);
  const [recentFolders, setRecentFolders] = useState<string[]>(() => {
    const saved = localStorage.getItem('recentFolders');
    return saved ? JSON.parse(saved) : [];
  });

  const addRecentFolder = (path: string) => {
    setRecentFolders(prev => {
      const next = [path, ...prev.filter(p => p !== path)].slice(0, 10);
      localStorage.setItem('recentFolders', JSON.stringify(next));
      return next;
    });
  };

  const openWorkspacePath = useCallback((rawPath: string) => {
    const path = (rawPath || '').trim().replace(/^"(.*)"$/, '$1');
    if (!path) return;
    api.setWorkspace(path).then((res: any) => {
      if (res.success) {
        const name = path.split(/[/\\]/).pop() || path;
        setWorkspaceName(name);
        setOpenFiles([]);
        setActiveFile('');
        setActiveActivity('explorer');
        handleRefreshExplorer();
        addRecentFolder(path);
      } else {
        alert(`Hata: Klasör açılamadı.\n${path}`);
      }
    }).catch(() => {
      alert(`Hata: Klasör açılamadı.\n${path}`);
    });
  }, [handleRefreshExplorer]);

  const executeAction = useCallback((cmdInput: any) => {
    if (!cmdInput) return;
    
    try {
      const cmd = typeof cmdInput === 'string' ? cmdInput : (cmdInput.type || '');
      const actionPath = typeof cmdInput === 'object' ? cmdInput.path : null;

      const cmdClean = cmd.toLowerCase().replace(/\.+$/, '');
      const normalizedCmd = cmdClean
        .replace('new text file', 'new file')
        .replace('open file from', 'open file')
        .replace('open workspace from file', 'open folder')
        .replace('add folder to workspace', 'open folder')
        .replace('save workspace as', 'save')
        .replace('split terminal', 'new terminal')
        .replace('new terminal window', 'new terminal')
        .replace('run task', 'run active file')
        .replace('run build task', 'run active file')
        .replace('run selected text', 'new terminal')
        .replace('show running tasks', 'new terminal')
        .replace('restart running task', 'new terminal')
        .replace('terminate task', 'new terminal')
        .replace('configure tasks', 'new terminal')
        .replace('configure default build task', 'new terminal')
        .replace('find in files', 'find')
        .replace('replace in files', 'replace')
        .replace('toggle line comment', 'find')
        .replace('toggle block comment', 'find')
        .replace('emmet: expand abbreviation', 'find');

      switch (normalizedCmd) {
      case 'save as': {
        if (!activeFile) return;
        const newName = window.prompt("Yeni dosya adı ile kaydet:", activeFile.split(/[/\\]/).pop());
        if (newName) {
            window.dispatchEvent(new CustomEvent('editor-save-as', { detail: { name: newName } }));
        }
        break;
      }
      case 'save':
      case 'save all':
        window.dispatchEvent(new CustomEvent('request-save'));
        break;
      case 'auto save':
        setAutoSave(prev => !prev);
        break;
      case 'new text file':
      case 'new file': {
        const name = window.prompt("Yeni dosya adı (ör: test.v):", "new_file.v");
        if (name) handleSaveFile("", name);
        break;
      }
      case 'new window':
      case 'new window with profile':
      case 'duplicate workspace':
        // @ts-ignore
        window.ipcRenderer?.send('window-control', 'new-window');
        break;
      case 'close window':
      case 'exit':
        // @ts-ignore
        window.ipcRenderer?.send('window-control', 'close');
        break;
      case 'close folder':
        api.setWorkspace('').then(() => {
           setOpenFiles([]);
           setActiveFile('');
           setWorkspaceName('AkyuzIDE');
           handleRefreshExplorer();
        });
        break;
      case 'close editor':
        if (activeFile) handleCloseFile(activeFile);
        break;
      case 'undo':
      case 'redo':
      case 'cut':
      case 'copy':
      case 'paste':
      case 'find':
      case 'replace':
        window.dispatchEvent(new CustomEvent('editor-action', { detail: cmdClean }));
        break;
      case 'open file': {
        // @ts-ignore
        if (window.ipcRenderer) {
          // @ts-ignore
          window.ipcRenderer.invoke('dialog:openFile').then((filePath: string) => {
            if (filePath) handleOpenFile(filePath);
          });
        } else {
          const filePath = window.prompt("Açmak istediğiniz dosya yolunu girin (workspace'e göre):", "main.v");
          if (filePath && filePath.trim()) handleOpenFile(filePath.trim());
        }
        break;
      }
      case 'open folder': {
        if (actionPath) {
           openWorkspacePath(actionPath);
           break;
        }

        // @ts-ignore
        if (window.ipcRenderer) {
          // @ts-ignore
          window.ipcRenderer.invoke('dialog:openDirectory').then((dirPath: string) => {
            if (dirPath) {
              openWorkspacePath(dirPath);
            }
          });
        } else {
          const dirPath = window.prompt("Açmak istediğiniz klasör yolunu girin:", "C:\\Users\\Taha\\Desktop\\");
          if (dirPath && dirPath.trim()) {
            openWorkspacePath(dirPath.trim());
          }
        }
        break;
      }
      case 'clone git repository': {
        const repoUrl = window.prompt("Git Repository URL:", "https://github.com/user/repo.git");
        if (repoUrl) {
           const dest = window.prompt("Hedef klasör:", "C:\\Users\\Taha\\Desktop\\cloned_repo");
           if (dest) {
             setTerminalLogs(prev => [...prev, makeLog(`[Git] Cloning ${repoUrl} to ${dest}...`)]);
             api.runTerminalCommand(`git clone ${repoUrl} ${dest}`).then(res => {
               setTerminalLogs(prev => [...prev, makeLog(res.stdout || res.stderr || 'Clone complete.')]);
               executeAction({ type: 'open folder', path: dest });
             });
           }
        }
        break;
      }
      case 'open recent': {
        const path = window.prompt("Açmak istediğiniz yolu seçin:\n" + recentFolders.join('\n'), recentFolders[0]);
        if (path) executeAction({ type: 'open folder', path });
        break;
      }
      case 'run active file': {
        if (!activeFile) return;
        if (activeFile.endsWith('.v') || activeFile.endsWith('.sv')) {
            alert(`Simülasyon başlatılıyor: ${activeFile}`);
        } else if (activeFile.endsWith('.c')) {
            api.compileFile(activeFile).then(res => {
              if (res.success) alert("Derleme başarılı!");
              else alert("Derleme hatası: " + res.log);
            });
        }
        break;
      }
      case 'preferences':
        setShowChat(true);
        setTimeout(() => {
          alert("AI Ayarları paneli sağ üstteki CPU ikonuna tıklayarak açılır.\n\nOrada:\n• Ollama sunucu adresi\n• Moonshot (Kimi) API Key\n• OpenRouter API Key\n• Sistem Prompt / Persona\n\nayarlarını yapabilirsiniz.");
        }, 100);
        break;
      case 'explorer': setActiveActivity('explorer'); break;
      case 'terminal': 
      case 'new terminal':
        if (terminalHeight === 0) setTerminalHeight(250);
        setActiveActivity('explorer');
        break;
      default: console.log("Action not implemented:", normalizedCmd);
    }
    } catch (err) {
      console.error("Error executing action:", err);
    }
  }, [activeFile, openFiles, terminalHeight, handleOpenFile, handleCloseFile, handleSaveFile, handleRefreshExplorer, recentFolders, openWorkspacePath]);

  // Resize and Event Handlers
  useEffect(() => {
    const handleTopMenuAction = (e: any) => executeAction(e.detail);
    const handleSaveAsCommit = (e: any) => {
      const { name, content } = e.detail;
      handleSaveFile(content, name);
    };

    const handleMouseMove = (e: MouseEvent) => {
      if (isResizingSidebar) {
        const newWidth = Math.max(160, Math.min(600, e.clientX - 48));
        setSidebarWidth(newWidth);
      }
      if (isResizingTerminal) {
        const maxHeight = window.innerHeight * 0.8;
        const newHeight = Math.max(40, Math.min(maxHeight, window.innerHeight - e.clientY));
        setTerminalHeight(newHeight);
      }
      if (isResizingChat) {
        const maxChat = Math.round(window.innerWidth * 0.55);
        const newWidth = Math.max(280, Math.min(maxChat, window.innerWidth - e.clientX));
        setChatWidth(newWidth);
      }
    };
    const handleMouseUp = () => {
      setIsResizingSidebar(false);
      setIsResizingTerminal(false);
      setIsResizingChat(false);
    };

    if (isResizingSidebar || isResizingTerminal || isResizingChat) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    }

    window.addEventListener('top-menu-action', handleTopMenuAction);
    window.addEventListener('save-as-commit', handleSaveAsCommit);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
      window.removeEventListener('top-menu-action', handleTopMenuAction);
      window.removeEventListener('save-as-commit', handleSaveAsCommit);
    };
  }, [isResizingSidebar, isResizingTerminal, isResizingChat, executeAction, handleSaveFile]);

  const handleToggleActivity = (id: string) => {
    setActiveActivity(prev => prev === id ? null : id);
  };

  return (
    <div className={`flex flex-col h-screen bg-bg-main text-text-main font-sans selection:bg-accent-ide/30 overflow-hidden ${(isResizingSidebar || isResizingTerminal || isResizingChat) ? 'select-none cursor-col-resize' : ''}`}>
      <div className="flex items-center h-10 bg-[#323233] border-b border-border-ide shrink-0 z-50" style={{ WebkitAppRegion: 'drag' } as any}>
         <div className="flex-1 h-full flex items-center">
            <TopMenu onAction={executeAction} showChat={showChat} onToggleChat={() => setShowChat(prev => !prev)} />
         </div>
         <button
           onClick={toggleTheme}
           title={theme === 'dark' ? 'Krem temaya geç' : 'Koyu temaya geç'}
           className="mr-3 p-1.5 rounded transition-colors text-text-dim hover:text-text-main hover:bg-white/10 shrink-0"
           style={{ WebkitAppRegion: 'no-drag' } as any}
         >
           {theme === 'dark'
             ? <Sun size={14} />
             : <Moon size={14} />}
         </button>
         <WindowControls />
      </div>
      
      <div className="flex-1 flex overflow-hidden relative">
        <ActivityBar activeTab={activeActivity || ''} setActiveTab={handleToggleActivity} />
        {activeActivity && (
          <>
            <div style={{ width: sidebarWidth }} className="h-full overflow-hidden shrink-0 bg-bg-sidebar pt-1">
               {activeActivity === 'explorer' && (
                 <Sidebar 
                    onFileClick={handleOpenFile} 
                    activeFile={activeFile} 
                    workspaceName={workspaceName}
                    refreshToken={refreshKey}
                 />
               )}
               {activeActivity === 'vivado' && <VivadoPanel />}
               {activeActivity === 'hardware' && <CCompilerPanel />}
            </div>
            <div 
              onMouseDown={() => setIsResizingSidebar(true)}
              className={`w-[4px] h-full cursor-col-resize transition-all z-50 border-x border-black/10 flex justify-center items-center group ${isResizingSidebar ? 'bg-accent-ide shadow-[0_0_10px_rgba(0,136,204,0.5)]' : 'bg-transparent hover:bg-accent-ide/30'}`}
            >
               <div className="w-[1px] h-24 bg-white/5 group-hover:bg-white/20 transition-all rounded-full" />
            </div>
          </>
        )}
        
        <div className="flex-1 flex overflow-hidden relative">
          <div className="flex-1 flex flex-col h-full overflow-hidden border-r border-border-ide min-w-[200px]">
            <div className="flex-1 relative overflow-hidden bg-[#1e1e1e] flex flex-col">
               <Editor
                  openFiles={openFiles}
                  activeFile={activeFile}
                  onOpenFile={handleOpenFile}
                  onCloseFile={handleCloseFile}
                  onRunSimulation={handleRunSimulation}
                  onSave={handleSaveFile}
                  isSaving={isSaving}
                  recentFolders={recentFolders}
                  theme={theme}
               />
            </div>

            <div 
              onMouseDown={() => setIsResizingTerminal(true)}
              className={`h-[4px] w-full cursor-row-resize transition-all z-50 border-y border-black/10 flex justify-center items-center group ${isResizingTerminal ? 'bg-accent-ide shadow-[0_0_10px_rgba(0,136,204,0.5)]' : 'bg-transparent hover:bg-accent-ide/30'}`}
            >
               <div className="h-[1px] w-24 bg-white/5 group-hover:bg-white/20 transition-all rounded-full" />
            </div>

            <div style={{ height: terminalHeight }} className="shrink-0 overflow-hidden bg-bg-main">
               <Terminal logs={terminalLogs} onCommand={handleTerminalCommand} />
            </div>
          </div>
  
          {showChat && (
            <>
              <div 
                onMouseDown={() => setIsResizingChat(true)}
                className={`w-[4px] h-full cursor-col-resize transition-all z-50 border-x border-black/10 flex justify-center items-center group ${isResizingChat ? 'bg-accent-ide shadow-[0_0_10px_rgba(0,136,204,0.5)]' : 'bg-transparent hover:bg-accent-ide/30'}`}
              >
                 <div className="w-[1px] h-24 bg-white/5 group-hover:bg-white/20 transition-all rounded-full" />
              </div>
              
              <div
                style={{ width: chatWidth }}
                className="shrink-0 h-full min-w-0 overflow-hidden flex flex-col border-l border-border-ide bg-bg-main"
              >
                <ChatPanel
                  onRefreshExplorer={handleRefreshExplorer}
                  onSave={() => executeAction('save')}
                  onRun={handleRunSimulation}
                  isSaving={isSaving}
                  activeFile={activeFile}
                  openFiles={openFiles}
                  onTerminalLog={(line) => {
                    setTerminalLogs(prev => [...prev, makeLog(line)]);
                    // Agent çalışmaya başladığında terminal kapalıysa otomatik aç
                    setTerminalHeight(prev => prev < 80 ? 220 : prev);
                  }}
                  onAgentStart={() => setTerminalHeight(prev => prev < 80 ? 220 : prev)}
                />
              </div>
            </>
          )}
        </div>
      </div>
      <StatusBar />
    </div>
  );
}
