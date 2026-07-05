import React, { useEffect, useState, useRef } from 'react';
import { Folder, FolderOpen, FileCode, FileText, Loader2, FilePlus, FolderPlus, Trash2, Edit3, Copy, ChevronRight, RefreshCcw, FolderOpen as FolderOpenIcon } from 'lucide-react';
import { api } from '../services/api';

interface SidebarProps {
  onFileClick: (path: string) => void;
  activeFile?: string;
  workspaceName?: string;
  refreshToken?: number;
}

interface FileNode {
  name: string;
  path: string;
  type: 'file' | 'dir';
  children?: FileNode[];
}

function buildTree(files: string[]): FileNode[] {
  const root: FileNode[] = [];
  const map: Record<string, FileNode> = {};

  files.forEach(f => {
    const parts = f.replace(/\\/g, '/').split('/');
    let current = root;
    let cumPath = '';
    parts.forEach((part, i) => {
      cumPath = cumPath ? `${cumPath}/${part}` : part;
      if (!map[cumPath]) {
        const node: FileNode = { name: part, path: cumPath, type: i < parts.length - 1 ? 'dir' : 'file' };
        map[cumPath] = node;
        current.push(node);
      }
      if (i < parts.length - 1) {
        if (!map[cumPath].children) map[cumPath].children = [];
        current = map[cumPath].children!;
      }
    });
  });

  return root;
}

const FileIcon = ({ path, isDir }: { path: string; isDir: boolean }) => {
  if (isDir) return <Folder size={14} className="text-[#dcb67a] shrink-0" />;
  if (path.endsWith('.v') || path.endsWith('.sv')) return <FileCode size={14} className="text-green-400/70 shrink-0" />;
  if (path.endsWith('.py')) return <FileCode size={14} className="text-blue-400/70 shrink-0" />;
  if (path.endsWith('.tcl')) return <FileCode size={14} className="text-purple-400/70 shrink-0" />;
  return <FileText size={14} className="text-white/30 shrink-0" />;
};

const TreeNode = ({
  node, depth, activeFile, onFileClick, onContextMenu, expandedDirs, toggleDir
}: {
  node: FileNode; depth: number; activeFile?: string;
  onFileClick: (p: string) => void;
  onContextMenu: (e: React.MouseEvent, p: string, isDir: boolean) => void;
  expandedDirs: Set<string>; toggleDir: (p: string) => void;
}) => {
  const isActive = activeFile === node.path;
  const isExpanded = expandedDirs.has(node.path);

  return (
    <>
      <div
        title={node.path}
        onClick={() => node.type === 'dir' ? toggleDir(node.path) : onFileClick(node.path)}
        onContextMenu={(e) => onContextMenu(e, node.path, node.type === 'dir')}
        style={{ paddingLeft: `${12 + depth * 14}px` }}
        className={`flex items-center gap-1.5 py-[3px] pr-2 text-[12.5px] cursor-pointer transition-colors relative group ${
          isActive ? 'bg-[#2a2d2e] text-white' : 'text-[#cccccc] hover:bg-[#2a2a2a]'
        }`}
      >
        {node.type === 'dir' && (
          <ChevronRight size={12} className={`shrink-0 text-white/30 transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
        )}
        {node.type === 'file' && <span className="w-3 shrink-0" />}
        <FileIcon path={node.path} isDir={node.type === 'dir'} />
        <span className="truncate flex-1">{node.name}</span>
      </div>
      {node.type === 'dir' && isExpanded && node.children?.map(child => (
        <React.Fragment key={child.path}>
          <TreeNode node={child} depth={depth + 1} activeFile={activeFile}
            onFileClick={onFileClick} onContextMenu={onContextMenu}
            expandedDirs={expandedDirs} toggleDir={toggleDir} />
        </React.Fragment>
      ))}
    </>
  );
};

const Sidebar = ({ onFileClick, activeFile, workspaceName = 'Workspace', refreshToken = 0 }: SidebarProps) => {
  const [files, setFiles] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [menu, setMenu] = useState<{ x: number; y: number; path: string; isDir: boolean } | null>(null);
  const [expandedDirs, setExpandedDirs] = useState<Set<string>>(new Set());
  const [workspacePath, setWorkspacePath] = useState('');
  const [editingPath, setEditingPath] = useState(false);
  const [currentWorkspace, setCurrentWorkspace] = useState(workspaceName);
  const pathInputRef = useRef<HTMLInputElement>(null);

  const fetchFiles = async () => {
    setLoading(true);
    try {
      const [data, health] = await Promise.all([api.getFiles(), api.getHealth()]);
      if (Array.isArray(data)) {
        setFiles(data);
      }
      if (health?.workspace) {
        const ws = health.workspace as string;
        setWorkspacePath(ws);
        setCurrentWorkspace(ws.split('/').pop() || ws.split('\\').pop() || ws);
      }
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleOpenPath = async (path: string) => {
    const cleaned = path.trim().replace(/^"(.*)"$/, '$1');
    if (!cleaned) return;
    try {
      const res = await api.setWorkspace(cleaned);
      if (res.success) {
        setEditingPath(false);
        window.dispatchEvent(new CustomEvent('workspace-changed'));
        fetchFiles();
      } else {
        alert('Klasör açılamadı: ' + cleaned);
      }
    } catch (err) {
      alert('Klasör açılamadı: ' + cleaned);
    }
  };

  useEffect(() => {
    fetchFiles();
  }, [refreshToken]);

  useEffect(() => {
    const handleRefresh = () => fetchFiles();
    window.addEventListener('refresh-explorer', handleRefresh);
    return () => window.removeEventListener('refresh-explorer', handleRefresh);
  }, []);

  useEffect(() => {
    const close = () => setMenu(null);
    window.addEventListener('click', close);
    return () => window.removeEventListener('click', close);
  }, []);

  const toggleDir = (path: string) => {
    setExpandedDirs(prev => {
      const next = new Set(prev);
      next.has(path) ? next.delete(path) : next.add(path);
      return next;
    });
  };

  const onContextMenu = (e: React.MouseEvent, path: string, isDir: boolean) => {
    e.preventDefault();
    setMenu({ x: e.clientX, y: e.clientY, path, isDir });
  };

  const handleNewFile = async () => {
    const name = window.prompt('Yeni dosya adı (örn: counter.v):');
    if (!name) return;
    const dir = menu?.isDir ? menu.path : (menu?.path.includes('/') ? menu.path.split('/').slice(0, -1).join('/') : '');
    const fullPath = dir ? `${dir}/${name}` : name;
    await api.writeFile(fullPath, '');
    fetchFiles();
    setMenu(null);
  };

  const handleNewFolder = async () => {
    const name = window.prompt('Yeni klasör adı:');
    if (!name) return;
    const dir = menu?.isDir ? menu.path : (menu?.path.includes('/') ? menu.path.split('/').slice(0, -1).join('/') : '');
    const fullPath = dir ? `${dir}/${name}/.gitkeep` : `${name}/.gitkeep`;
    await api.writeFile(fullPath, '');
    fetchFiles();
    setMenu(null);
  };

  const handleRename = async () => {
    if (!menu) return;
    const newName = window.prompt('Yeni ad:', menu.path.split('/').pop());
    if (!newName) return;
    const dir = menu.path.includes('/') ? menu.path.split('/').slice(0, -1).join('/') : '';
    const newPath = dir ? `${dir}/${newName}` : newName;
    try { await api.renameFile(menu.path, newPath); fetchFiles(); } catch { alert('Hata'); }
    setMenu(null);
  };

  const handleDelete = async () => {
    if (!menu) return;
    if (!window.confirm(`'${menu.path}' silinsin mi?`)) return;
    try { await api.deleteFile(menu.path); fetchFiles(); } catch { alert('Hata'); }
    setMenu(null);
  };

  const handleCopyPath = () => {
    if (menu) navigator.clipboard.writeText(menu.path);
    setMenu(null);
  };

  const tree = buildTree(files);

  return (
    <div className="w-full bg-bg-sidebar flex flex-col h-full select-none">
      <div className="px-3 py-2 text-[10px] font-bold uppercase text-text-dim tracking-widest flex justify-between items-center border-b border-border-ide/30">
        <span className="truncate max-w-[120px]" title={workspacePath}>EXPLORER</span>
        <div className="flex items-center gap-2">
          <span title="Yenile"><RefreshCcw size={13} className={`cursor-pointer hover:text-white transition-all ${loading ? 'animate-spin' : ''}`}
            onClick={fetchFiles} /></span>
          <span title="Yeni Dosya"><FilePlus size={13} className="cursor-pointer hover:text-white transition-colors"
            onClick={() => { setMenu({ x: 0, y: 0, path: '', isDir: true }); setTimeout(handleNewFile, 0); }} /></span>
          <span title="Yeni Klasör"><FolderPlus size={13} className="cursor-pointer hover:text-white transition-colors"
            onClick={() => { setMenu({ x: 0, y: 0, path: '', isDir: true }); setTimeout(handleNewFolder, 0); }} /></span>
        </div>
      </div>
      {/* Workspace path bar */}
      <div className="px-2 py-1 border-b border-border-ide/20 flex items-center gap-1">
        {editingPath ? (
          <input
            ref={pathInputRef}
            className="flex-1 text-[11px] bg-bg-main text-white border border-accent-ide/50 rounded px-2 py-0.5 outline-none"
            defaultValue={workspacePath}
            placeholder="C:\Users\Taha\Desktop\..."
            onKeyDown={e => {
              if (e.key === 'Enter') handleOpenPath((e.target as HTMLInputElement).value);
              if (e.key === 'Escape') setEditingPath(false);
            }}
            onBlur={e => { if (e.target.value !== workspacePath) handleOpenPath(e.target.value); else setEditingPath(false); }}
            autoFocus
          />
        ) : (
          <button
            className="flex-1 text-left text-[11px] text-text-dim hover:text-white truncate px-1 py-0.5 rounded hover:bg-white/5 transition-colors"
            title={`Workspace: ${workspacePath}\nDeğiştirmek için tıkla`}
            onClick={() => { setEditingPath(true); setTimeout(() => pathInputRef.current?.select(), 50); }}
          >
            📁 {currentWorkspace || 'workspace'}
          </button>
        )}
      </div>

      {loading ? (
        <div className="flex-1 flex items-center justify-center text-text-dim">
          <Loader2 className="animate-spin" size={18} />
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto py-0.5">
          {tree.map(node => (
            <React.Fragment key={node.path}>
              <TreeNode node={node} depth={0} activeFile={activeFile}
                onFileClick={onFileClick} onContextMenu={onContextMenu}
                expandedDirs={expandedDirs} toggleDir={toggleDir} />
            </React.Fragment>
          ))}
          {tree.length === 0 && (
            <div className="px-4 py-6 text-[11px] text-text-dim italic">'{workspaceName}' klasörü boş</div>
          )}
        </div>
      )}

      {menu && menu.x > 0 && (
        <div
          className="fixed z-[1000] bg-bg-main border border-border-ide shadow-2xl rounded py-1 min-w-[180px]"
          style={{ top: menu.y, left: menu.x }}
          onClick={e => e.stopPropagation()}
        >
          <div className="px-3 py-1 text-[9px] text-white/30 font-bold uppercase tracking-widest border-b border-white/5 mb-1 truncate max-w-[220px]">
            {menu.path || 'Workspace'}
          </div>
          <button onClick={handleNewFile} className="w-full text-left px-3 py-1.5 text-[12px] text-white/70 hover:bg-white/5 flex items-center gap-2">
            <FilePlus size={12} /> Yeni Dosya
          </button>
          <button onClick={handleNewFolder} className="w-full text-left px-3 py-1.5 text-[12px] text-white/70 hover:bg-white/5 flex items-center gap-2">
            <FolderPlus size={12} /> Yeni Klasör
          </button>
          <div className="h-px bg-white/5 my-1" />
          <button onClick={handleRename} className="w-full text-left px-3 py-1.5 text-[12px] text-white/70 hover:bg-white/5 flex items-center gap-2">
            <Edit3 size={12} /> Yeniden Adlandır
          </button>
          <button onClick={handleCopyPath} className="w-full text-left px-3 py-1.5 text-[12px] text-white/70 hover:bg-white/5 flex items-center gap-2">
            <Copy size={12} /> Yolu Kopyala
          </button>
          <div className="h-px bg-white/5 my-1" />
          <button onClick={handleDelete} className="w-full text-left px-3 py-1.5 text-[12px] text-red-400 hover:bg-red-500/10 flex items-center gap-2">
            <Trash2 size={12} /> Sil
          </button>
        </div>
      )}
    </div>
  );
};

export default Sidebar;
