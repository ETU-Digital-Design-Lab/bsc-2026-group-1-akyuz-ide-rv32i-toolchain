import React, { useState, useEffect, useRef } from 'react';
import { FileCode, X } from 'lucide-react';
import MonacoEditor, { loader } from '@monaco-editor/react';
import { api } from '../services/api';
import WelcomePage from './WelcomePage';

// Monaco Loader configuration removed top-level await for stability

const codeMockup = `module counter(
    input clk,
    input rst,
    output [3:0] count
);

    reg [3:0] count_reg;
    always @(posedge clk) begin
        if (rst) count_reg <= 0;
        else count_reg <= count_reg + 1;
    end
    assign count = count_reg;
endmodule`;

interface CodeEditorProps {
  openFiles: string[];
  activeFile: string;
  onOpenFile: (path: string) => void;
  onCloseFile: (path: string) => void;
  onRunSimulation: () => void;
  onSave?: (content: string) => void;
  isSaving?: boolean;
  recentFolders?: string[];
  theme?: 'dark' | 'cream';
}


const CodeEditor = ({
  openFiles,
  activeFile,
  onOpenFile,
  onCloseFile,
  onRunSimulation,
  onSave,
  isSaving = false,
  recentFolders = [],
  theme = 'dark',
}: CodeEditorProps) => {
  const [code, setCode] = useState('');
  const editorRef = useRef<any>(null);
  const monacoTheme = 'vs-dark'; // CSS invert() filter handles light mode visually

  // Handle global editor actions (Undo, Redo, etc.)
  useEffect(() => {
    const handleAction = (e: any) => {
      const action = e.detail;
      if (!editorRef.current) return;
      
      switch(action) {
        case 'undo': editorRef.current.trigger('keyboard', 'undo', null); break;
        case 'redo': editorRef.current.trigger('keyboard', 'redo', null); break;
        case 'copy': editorRef.current.trigger('keyboard', 'editor.action.clipboardCopyAction', null); break;
        case 'cut': editorRef.current.trigger('keyboard', 'editor.action.clipboardCutAction', null); break;
        case 'paste': editorRef.current.trigger('keyboard', 'editor.action.clipboardPasteAction', null); break;
        case 'find': editorRef.current.trigger('keyboard', 'actions.find', null); break;
        case 'replace': editorRef.current.trigger('keyboard', 'editor.action.startFindReplaceAction', null); break;
      }
    };
    
    const handleSaveAs = (e: any) => {
      const { name } = e.detail;
      // We send the current code back to the parent to save as a new file
      window.dispatchEvent(new CustomEvent('save-as-commit', { detail: { name, content: code } }));
    };

    window.addEventListener('editor-action', handleAction);
    window.addEventListener('editor-save-as', handleSaveAs);
    
    const handleResize = () => editorRef.current?.layout();
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('editor-action', handleAction);
      window.removeEventListener('editor-save-as', handleSaveAs);
      window.removeEventListener('resize', handleResize);
    };
  }, [code]);

  // Handle global save requests
  useEffect(() => {
    const handleGlobalSave = () => {
       if (onSave) onSave(code);
    };
    window.addEventListener('request-save', handleGlobalSave);
    return () => window.removeEventListener('request-save', handleGlobalSave);
  }, [code, onSave]);

  // Fetch file content when activeFile changes
  useEffect(() => {
    const fetchContent = async () => {
      if (!activeFile) return;
      try {
        const content = await api.readFile(activeFile);
        setCode(content);
      } catch (err) {
        console.error("Failed to read file:", activeFile, err);
      }
    };
    fetchContent();
  }, [activeFile]);

  // Update Monaco theme live when theme prop changes
  useEffect(() => {
    if (!editorRef.current) return;
    import('monaco-editor').then((monaco) => {
      monaco.editor.setTheme(monacoTheme);
    });
  }, [monacoTheme]);

  const handleEditorChange = (value: string | undefined) => {
    if (value !== undefined) setCode(value);
  };

  return (
    <div className="flex-1 flex flex-col bg-[#1e1e1e] overflow-hidden">
      {/* Dynamic Tabs - Flattened VS Code Style */}
      <div className="flex bg-[#252526] h-[35px] items-center shrink-0 overflow-x-auto no-scrollbar border-b border-border-ide/10">
        {openFiles.map(path => (
          <div
            key={path}
            onClick={() => onOpenFile(path)}
            className={`flex items-center gap-2 px-3 h-full border-r border-border-ide/30 cursor-pointer min-w-[120px] transition-all group relative ${
              activeFile === path ? 'bg-[#1e1e1e] text-white' : 'text-text-dim hover:bg-[#2b2b2b]'
            }`}
          >
            <FileCode size={13} className={activeFile === path ? 'text-success-ide' : 'opacity-50'} />
            <span className="text-[12px] truncate flex-1">{path}</span>
            <X 
              size={12} 
              className="opacity-0 group-hover:opacity-100 hover:bg-white/10 rounded-sm p-0.5 transition-all" 
              onClick={(e) => {
                e.stopPropagation();
                onCloseFile(path);
              }}
            />
            {/* Active Indicator Line */}
            {activeFile === path && (
               <div className="absolute top-0 left-0 right-0 h-[2px] bg-accent-ide" />
            )}
          </div>
        ))}
      </div>


      {/* Editor Main Section */}
      <div className="flex-1 min-h-0 flex flex-col overflow-hidden relative">
        {activeFile ? (
          <div className="flex-1 relative h-full">
            <MonacoEditor
              key={activeFile}
              height="100%"
              language={activeFile.endsWith('.v') || activeFile.endsWith('.sv') ? 'verilog' : activeFile.endsWith('.py') ? 'python' : activeFile.endsWith('.c') || activeFile.endsWith('.h') ? 'c' : 'plaintext'}
              value={code}
              theme={monacoTheme}
              onChange={handleEditorChange}
              onMount={(editor) => {
                editorRef.current = editor;
                editor.layout();
                setTimeout(() => {
                  editor.focus();
                }, 100);
              }}
              options={{
                fontSize: 14,
                minimap: { enabled: true },
                scrollBeyondLastLine: false,
                automaticLayout: true,
                readOnly: false,
                padding: { top: 12 },
                fontFamily: "'Fira Code', 'Cascadia Code', Consolas, monospace",
                fontLigatures: true,
                lineHeight: 1.6,
                wordWrap: 'on',
              }}
            />
          </div>
        ) : (
          <WelcomePage recentFolders={recentFolders} />
        )}
      </div>
    </div>
  );
};

export default CodeEditor;
