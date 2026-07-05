import React, { useState, useRef, useEffect } from 'react';
import { Bot, Cpu, Send, Loader2, Sparkles, ChevronDown, ChevronRight, Check, Save, Play, RotateCcw, Copy, ListOrdered, MessageSquare, Code2, Activity } from 'lucide-react';
import { api } from '../services/api';
import { AnimatePresence, motion } from 'motion/react';
import ReactMarkdown from 'react-markdown';
import WaveformViewer from './WaveformViewer';

export type ChatMode = 'agent' | 'ask' | 'plan';

// ── Collapsible code block ──────────────────────────────────────────────────

function CollapsibleCode({ lang, content }: { lang: string; content: string }) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const lines = content.split('\n').length;
  const copy = () => { navigator.clipboard.writeText(content); setCopied(true); setTimeout(() => setCopied(false), 2000); };
  return (
    <div className="my-1.5 rounded-lg border border-white/10 overflow-hidden text-[11px] font-mono">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-2 w-full px-2.5 py-1.5 bg-[#2a2a2d] hover:bg-[#323235] transition-colors text-left"
      >
        <Code2 size={12} className="text-accent-ide shrink-0" />
        <span className="text-white/60 text-[10px] flex-1">{lang} · {lines} satır</span>
        {open
          ? <ChevronDown size={12} className="text-white/40 shrink-0" />
          : <ChevronRight size={12} className="text-white/40 shrink-0" />}
        <button
          onClick={e => { e.stopPropagation(); copy(); }}
          className="text-white/40 hover:text-white/80 p-0.5 ml-1"
          title="Kopyala"
        >
          {copied ? <Check size={11} className="text-accent-ide" /> : <Copy size={11} />}
        </button>
      </button>
      {open && (
        <pre className="p-3 bg-[#161618] text-white/85 overflow-x-auto leading-relaxed whitespace-pre text-[11px]">
          {content}
        </pre>
      )}
    </div>
  );
}

interface Step {
  type: string;
  content: string;
  tool?: string;
  args?: Record<string, string>;
}

const FILE_OP_TOOLS = new Set(['write_file', 'edit_file', 'delete_file', 'create_dir', 'rename_file']);

function normalizeFilePath(raw: string): string {
  const s = raw.replace(/\\\\/g, '/').replace(/\\/g, '/');
  const wsIdx = s.toLowerCase().search(/workspace\//);
  if (wsIdx >= 0) return s.slice(wsIdx + 10);
  const parts = s.split('/').filter(Boolean);
  return parts.slice(-2).join('/') || raw;
}

// ── LiveStepBlock: Claude Code tarzı canlı adım gösterimi ─────────────────
interface LiveStepBlockProps {
  call: Step;
  result?: Step;
  isRunning?: boolean;
}

function getLiveStepMeta(call: Step): { label: string; statNode: React.ReactNode; iconClass: string } {
  const tool = call.tool || '';
  const args = call.args || {};
  const rawPath: string = args.path || args.old_path || '';
  const fileName = rawPath ? (rawPath.split(/[\\/]/).pop() || rawPath) : '';

  if (tool === 'write_file') {
    const lines = (args.content || '').split('\n').length;
    return {
      label: `Wrote ${fileName || 'file'}`,
      statNode: <span className="text-emerald-400/65 shrink-0">+{lines}</span>,
      iconClass: 'text-emerald-400',
    };
  }
  if (tool === 'edit_file') {
    const added = (args.new_str || '').split('\n').length;
    const removed = (args.old_str || '').split('\n').length;
    return {
      label: `Edited ${fileName || 'file'}`,
      statNode: (
        <span className="shrink-0 flex gap-0.5">
          <span className="text-emerald-400/65">+{added}</span>
          <span className="text-red-400/60">-{removed}</span>
        </span>
      ),
      iconClass: 'text-amber-400',
    };
  }
  if (tool === 'read_file') return { label: `Read ${fileName || 'a file'}`, statNode: null, iconClass: 'text-blue-400/80' };
  if (tool === 'list_files') return { label: 'Listed files', statNode: null, iconClass: 'text-white/40' };
  if (tool === 'glob_files') return { label: 'Searched files (glob)', statNode: null, iconClass: 'text-purple-400/70' };
  if (tool === 'grep_files') return { label: `Searched code${args.pattern ? ': ' + args.pattern.slice(0, 30) : ''}`, statNode: null, iconClass: 'text-purple-400/70' };
  if (tool === 'compile_verilog') return { label: 'Compiled (iverilog)', statNode: null, iconClass: 'text-cyan-400/80' };
  if (tool === 'run_simulation') return { label: 'Ran simulation (vvp)', statNode: null, iconClass: 'text-cyan-400/80' };
  if (tool === 'delete_file') return { label: `Deleted ${fileName || 'file'}`, statNode: null, iconClass: 'text-red-400/80' };
  if (tool === 'create_dir') return { label: `Created dir: ${fileName}`, statNode: null, iconClass: 'text-emerald-400/70' };
  if (tool === 'rename_file') return { label: `Renamed ${args.old_path?.split(/[\\/]/).pop() || 'file'}`, statNode: null, iconClass: 'text-amber-400/70' };
  if (tool === 'run_command') {
    const cmd = (args.command || '').slice(0, 45) || call.content.slice(0, 45);
    return { label: `Ran: ${cmd}`, statNode: null, iconClass: 'text-[#4fc1ff]/80' };
  }
  if (tool === 'clear_workspace') return { label: 'Cleared workspace', statNode: null, iconClass: 'text-red-400/70' };
  if (tool === 'set_workspace_dir') return { label: `Workspace: ${args.path || ''}`, statNode: null, iconClass: 'text-white/30' };
  if (tool === 'check_vivado') return { label: 'Checked Vivado', statNode: null, iconClass: 'text-violet-400/70' };
  if (tool === 'get_board_info') return { label: `Board info: ${args.board_name || ''}`, statNode: null, iconClass: 'text-violet-400/70' };
  if (tool === 'generate_xdc') return { label: `Generated XDC: ${fileName}`, statNode: null, iconClass: 'text-violet-400/70' };
  if (tool === 'prepare_vivado_build') return { label: 'Prepared Vivado build', statNode: null, iconClass: 'text-violet-400/70' };
  if (tool === 'run_vivado_flow') return { label: 'Vivado flow (synth→impl→bit)', statNode: null, iconClass: 'text-violet-400' };
  return { label: call.content || tool, statNode: null, iconClass: 'text-emerald-400/70' };
}

function LiveStepBlock({ call, result, isRunning }: LiveStepBlockProps) {
  const [open, setOpen] = useState(false);
  const { label, statNode, iconClass } = getLiveStepMeta(call);
  const tool = call.tool || '';
  const args = call.args || {};

  type DiffLine = { line: string; kind: '+' | '-' };
  const diffLines: DiffLine[] = [];
  if (tool === 'write_file' && args.content) {
    args.content.split('\n').forEach(l => diffLines.push({ line: l, kind: '+' }));
  } else if (tool === 'edit_file') {
    (args.old_str || '').split('\n').forEach(l => diffLines.push({ line: l, kind: '-' }));
    (args.new_str || '').split('\n').forEach(l => diffLines.push({ line: l, kind: '+' }));
  }

  const hasDetail = diffLines.length > 0 || !!result?.content;

  return (
    <div className="font-mono">
      <button
        onClick={() => hasDetail && setOpen(o => !o)}
        className={`flex items-center gap-1.5 w-full text-left py-[3px] text-[11px] min-w-0 ${hasDetail ? 'cursor-pointer' : 'cursor-default'}`}
      >
        {isRunning ? (
          <Loader2 size={11} className="animate-spin text-accent-ide shrink-0" />
        ) : open ? (
          <ChevronDown size={11} className="text-white/20 shrink-0" />
        ) : (
          <ChevronRight size={11} className="text-white/20 shrink-0" />
        )}
        <span className={`shrink-0 w-3 text-center text-[11px] leading-none ${iconClass}`}>
          {tool === 'write_file' ? '↑' :
           tool === 'edit_file' ? '✎' :
           tool === 'read_file' ? '◎' :
           tool === 'list_files' || tool === 'glob_files' ? '≡' :
           tool === 'grep_files' ? '⌕' :
           tool === 'compile_verilog' || tool === 'run_simulation' ? '⚙' :
           tool === 'delete_file' ? '✗' :
           tool === 'run_command' ? '$' :
           tool === 'clear_workspace' ? '⊗' :
           '▶'}
        </span>
        <span className="text-white/65 truncate min-w-0 flex-1">{label}</span>
        {statNode}
        {hasDetail && !open && !isRunning && (
          <ChevronRight size={10} className="text-white/15 shrink-0 ml-0.5" />
        )}
      </button>
      {open && hasDetail && (
        <div className="ml-5 mb-1 rounded-md border border-white/8 overflow-hidden max-h-[200px] overflow-y-auto bg-[#0d0d0f]">
          {diffLines.length > 0 ? (
            diffLines.slice(0, 200).map((d, i) => (
              <div key={i} className={`flex text-[10px] font-mono leading-[1.5] px-1.5 ${d.kind === '+' ? 'bg-emerald-950/30 text-emerald-200/70' : 'bg-red-950/30 text-red-200/70'}`}>
                <span className={`w-3 shrink-0 select-none ${d.kind === '+' ? 'text-emerald-500/60' : 'text-red-500/60'}`}>{d.kind}</span>
                <span className="whitespace-pre-wrap break-all">{d.line}</span>
              </div>
            ))
          ) : result?.content ? (
            <div className="text-[10px] text-white/40 p-2 whitespace-pre-wrap break-words leading-relaxed">{result.content}</div>
          ) : null}
        </div>
      )}
    </div>
  );
}

// Adımları tool_call+tool_result çiftlerine gruplar
function groupSteps(steps: Step[]): Array<{ call: Step; result?: Step }> {
  const pairs: Array<{ call: Step; result?: Step }> = [];
  let i = 0;
  while (i < steps.length) {
    const s = steps[i];
    if (s.type === 'tool_call') {
      const next = steps[i + 1]?.type === 'tool_result' ? steps[i + 1] : undefined;
      pairs.push({ call: s, result: next });
      i += next ? 2 : 1;
    } else {
      i++; // thinking/reasoning/env_status atla
    }
  }
  return pairs;
}

function FileOpStep({ step, resultStep }: { step: Step; resultStep?: Step }) {
  const [open, setOpen] = useState(false);
  const tool = step.tool || '';
  const args = step.args || {};

  const path: string = args.path || args.old_path || '?';
  const fileName = path.split(/[\\/]/).pop() || path;

  let linesAdded = 0;
  let linesRemoved = 0;
  type DiffLine = { line: string; kind: '+' | '-' };
  let diffLines: DiffLine[] = [];

  if (tool === 'write_file') {
    const lines = (args.content || '').split('\n');
    linesAdded = lines.length;
    diffLines = lines.map(line => ({ line, kind: '+' as const }));
  } else if (tool === 'edit_file') {
    const oldLines = (args.old_str || '').split('\n');
    const newLines = (args.new_str || '').split('\n');
    linesRemoved = oldLines.length;
    linesAdded = newLines.length;
    diffLines = [
      ...oldLines.map(l => ({ line: l, kind: '-' as const })),
      ...newLines.map(l => ({ line: l, kind: '+' as const })),
    ];
  }

  const TOOL_LABEL: Record<string, string> = {
    write_file: 'Wrote',
    edit_file: 'Edited',
    create_dir: 'Created',
    delete_file: 'Deleted',
    rename_file: 'Renamed',
  };
  const label = TOOL_LABEL[tool] || tool;

  return (
    <div className="my-px">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-1.5 w-full text-left py-0.5 group"
      >
        {open
          ? <ChevronDown size={11} className="text-white/25 shrink-0" />
          : <ChevronRight size={11} className="text-white/25 shrink-0" />}
        <span className="text-emerald-400/80 font-semibold shrink-0">{label}</span>
        <span className="text-white/55 truncate min-w-0">{fileName}</span>
        {tool === 'write_file' && (
          <span className="text-emerald-400/55 shrink-0">+{linesAdded}</span>
        )}
        {tool === 'edit_file' && (
          <span className="shrink-0 flex gap-1">
            <span className="text-emerald-400/55">+{linesAdded}</span>
            <span className="text-red-400/55">-{linesRemoved}</span>
          </span>
        )}
      </button>
      {open && (
        <div className="ml-3 mt-0.5 mb-1 rounded-md border border-white/8 overflow-hidden max-h-[220px] overflow-y-auto bg-[#0d0d0f]">
          {diffLines.length > 0 ? (
            diffLines.map((d, i) => (
              <div
                key={i}
                className={`flex text-[10px] font-mono leading-[1.55] px-1.5 ${
                  d.kind === '+' ? 'bg-emerald-950/35 text-emerald-200/75' : 'bg-red-950/35 text-red-200/75'
                }`}
              >
                <span className={`w-3 shrink-0 select-none ${d.kind === '+' ? 'text-emerald-500/70' : 'text-red-500/70'}`}>{d.kind}</span>
                <span className="whitespace-pre-wrap break-all">{d.line}</span>
              </div>
            ))
          ) : (
            <div className="px-2 py-1.5 text-[10px] text-white/35">{resultStep?.content || path}</div>
          )}
        </div>
      )}
    </div>
  );
}

function CollapsibleSteps({ steps }: { steps: Step[] }) {
  const [open, setOpen] = useState(false);
  if (!steps.length) return null;
  const toolCount = steps.filter(s => s.type === 'tool_call').length;
  const pairs = groupSteps(steps);

  return (
    <div className="my-1 text-[11px]">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-1.5 text-left text-white/30 hover:text-white/50 transition-colors py-0.5"
      >
        {open ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
        <span className="font-mono">{toolCount} araç çağrısı &middot; {steps.length} adım</span>
      </button>
      {open && (
        <div className="mt-0.5 border-l border-white/10 ml-1 pl-2.5 flex flex-col gap-0">
          {pairs.map((p, pi) => (
            <LiveStepBlock key={pi} call={p.call} result={p.result} />
          ))}
        </div>
      )}
    </div>
  );
}

function MessageContent({ content }: { content: string }) {
  return (
    <div className="text-[12.5px] leading-relaxed text-white/90 select-text markdown-body">
      <ReactMarkdown
        components={{
          // Code blocks → CollapsibleCode
          code({ node, className, children, ...props }: any) {
            const inline = !className;
            const lang = (className || '').replace('language-', '') || 'text';
            const code = String(children).replace(/\n$/, '');
            if (inline) {
              return (
                <code className="bg-white/10 text-accent-ide px-1 py-0.5 rounded text-[11px] font-mono" {...props}>
                  {code}
                </code>
              );
            }
            return <CollapsibleCode lang={lang} content={code} />;
          },
          // Headings
          h1: ({ children }) => <h1 className="text-[15px] font-bold text-white mt-3 mb-1.5 border-b border-white/10 pb-1">{children}</h1>,
          h2: ({ children }) => <h2 className="text-[13px] font-bold text-white mt-2.5 mb-1">{children}</h2>,
          h3: ({ children }) => <h3 className="text-[12px] font-semibold text-accent-ide mt-2 mb-0.5">{children}</h3>,
          // Paragraphs
          p: ({ children }) => <p className="mb-2 last:mb-0 whitespace-pre-wrap">{children}</p>,
          // Lists
          ul: ({ children }) => <ul className="list-disc list-inside space-y-0.5 mb-2 pl-2">{children}</ul>,
          ol: ({ children }) => <ol className="list-decimal list-inside space-y-0.5 mb-2 pl-2">{children}</ol>,
          li: ({ children }) => <li className="text-white/85">{children}</li>,
          // Bold / italic
          strong: ({ children }) => <strong className="font-semibold text-white">{children}</strong>,
          em: ({ children }) => <em className="italic text-white/70">{children}</em>,
          // Blockquote
          blockquote: ({ children }) => (
            <blockquote className="border-l-2 border-accent-ide/50 pl-3 my-1.5 text-white/60 italic">{children}</blockquote>
          ),
          // Horizontal rule
          hr: () => <hr className="border-white/10 my-2" />,
          // Links
          a: ({ href, children }) => (
            <a href={href} target="_blank" rel="noreferrer" className="text-accent-ide underline underline-offset-2 hover:brightness-125">{children}</a>
          ),
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}

// ───────────────────────────────────────────────────────────────────────────

interface ChatPanelProps {
  onRefreshExplorer?: () => void;
  onSave?: () => void;
  onRun?: () => void;
  isSaving?: boolean;
  activeFile?: string;
  openFiles?: string[];
  onTerminalLog?: (line: string) => void;
  onAgentStart?: () => void;
}

const LS_PERSONA = 'akyuz_ai_persona';
const LS_OPENROUTER_KEY = 'akyuz_openrouter_key';
const LS_GEMINI_KEY = 'akyuz_gemini_key';
const LS_PERF_MODE = 'akyuz_perf_mode';
const LS_OLLAMA = 'akyuz_ollama_host';
const LS_BACKEND = 'akyuz_backend_url';

const ChatPanel = ({ onRefreshExplorer, onSave, onRun, isSaving, activeFile, openFiles, onTerminalLog, onAgentStart }: ChatPanelProps) => {
  const [showSettings, setShowSettings] = useState(false);
  const [openrouterKey, setOpenrouterKey] = useState(() => localStorage.getItem(LS_OPENROUTER_KEY) || '');
  const [openrouterKeyDraft, setOpenrouterKeyDraft] = useState(() => localStorage.getItem(LS_OPENROUTER_KEY) || '');
  const [geminiKey, setGeminiKey] = useState(() => localStorage.getItem(LS_GEMINI_KEY) || '');
  const [geminiKeyDraft, setGeminiKeyDraft] = useState(() => localStorage.getItem(LS_GEMINI_KEY) || '');
  const [ollamaHost, setOllamaHost] = useState(() => localStorage.getItem(LS_OLLAMA) || 'http://127.0.0.1:11434');
  const [ollamaHostDraft, setOllamaHostDraft] = useState(() => localStorage.getItem(LS_OLLAMA) || 'http://127.0.0.1:11434');
  const [backendUrl, setBackendUrl] = useState(() => localStorage.getItem(LS_BACKEND) || 'http://127.0.0.1:8001');
  const [backendUrlDraft, setBackendUrlDraft] = useState(() => localStorage.getItem(LS_BACKEND) || 'http://127.0.0.1:8001');
  const [isConnected, setIsConnected] = useState(true);
  const [input, setInput] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [messages, setMessages] = useState<{ role: string; content: string; model?: string; mode?: string; steps?: Step[]; changedFiles?: string[] }[]>([]);
  const stepsRef = useRef<Step[]>([]);
  const changedFilesRef = useRef<string[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [detectedMode, setDetectedMode] = useState<string>('agent');
  const [performanceMode, setPerformanceMode] = useState<'auto' | 'high' | 'low'>(
    () => (localStorage.getItem(LS_PERF_MODE) as 'auto' | 'high' | 'low') || 'auto'
  );
  const [routedModel, setRoutedModel] = useState<string | null>(null);
  const routedModelRef = useRef<string | null>(null);
  const [streamingSteps, setStreamingSteps] = useState<Step[]>([]);
  const [askStreamText, setAskStreamText] = useState('');
  const [explainText, setExplainText] = useState('');
  const [requestStartedAt, setRequestStartedAt] = useState<number | null>(null);
  const [requestElapsedMs, setRequestElapsedMs] = useState(0);
  const [pendingConfirm, setPendingConfirm] = useState<{ sessionId: string; confirm: { title: string; detail: string; risk: string }; tool: string } | null>(null);
  const pendingConfirmRef = useRef<{ sessionId: string; confirm: { title: string; detail: string; risk: string }; tool: string } | null>(null);
  const [persona, setPersona] = useState(localStorage.getItem(LS_PERSONA) || '');
  const [copiedId, setCopiedId] = useState<number | null>(null);
  const [waveformPath, setWaveformPath] = useState<string | null>(null);
  const [budget, setBudget] = useState<{ spent: number; remaining: number; limit: number } | null>(null);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesAreaRef = useRef<HTMLDivElement>(null);

  const handleMessagesKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'a') {
      e.preventDefault();
      e.stopPropagation();
      const el = messagesAreaRef.current;
      if (!el) return;
      const range = document.createRange();
      range.selectNodeContents(el);
      const sel = window.getSelection();
      sel?.removeAllRanges();
      sel?.addRange(range);
    }
  };

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, streamingSteps]);

  // Auto-resize textarea based on content
  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 220) + 'px';
  }, [input]);

  useEffect(() => {
    if (!isLoading || !requestStartedAt) return;
    const timer = window.setInterval(() => {
      setRequestElapsedMs(Date.now() - requestStartedAt);
    }, 300);
    return () => window.clearInterval(timer);
  }, [isLoading, requestStartedAt]);

  useEffect(() => {
    localStorage.setItem(LS_PERF_MODE, performanceMode);
  }, [performanceMode]);

  const fetchBudget = async () => {
    if (!openrouterKey) return;
    try {
      const r = await fetch(`${BASE_URL}/api/budget`);
      if (r.ok) {
        const d = await r.json();
        setBudget({ spent: d.spent_today, remaining: d.remaining, limit: d.daily_limit });
      }
    } catch { /* backend kapalıysa sessizce geç */ }
  };

  useEffect(() => {
    fetchBudget();
  }, [openrouterKey]);

  const handleSend = async (overrideInput?: string, overrideHistory?: any[]) => {
    const textToSend = overrideInput || input;
    if (!textToSend.trim()) return;

    if (!overrideInput) {
      setMessages((prev) => [...prev, { role: 'user', content: textToSend }]);
      setInput('');
      if (textareaRef.current) textareaRef.current.style.height = '45px';
    }

    setIsLoading(true);
    onAgentStart?.();
    setRequestStartedAt(Date.now());
    setRequestElapsedMs(0);
    setStreamingSteps([]);
    setAskStreamText('');
    setExplainText('');
    stepsRef.current = [];
    changedFilesRef.current = [];
    routedModelRef.current = null;
    setRoutedModel(null);

    const currentMessages = overrideHistory || messages;
    const history = currentMessages.filter((m) => m.role === 'user' || m.role === 'assistant').map((m) => ({ role: m.role, content: m.content }));

    const workspaceContext = [
      activeFile ? `Aktif dosya: ${activeFile}` : '',
      openFiles?.length ? `Açık dosyalar: ${openFiles.join(', ')}` : '',
      persona ? `Kullanıcı notu:\n${persona}` : '',
    ]
      .filter(Boolean)
      .join('\n');

    try {
      {
        const stream = api.agentStream(
          textToSend,
          history,
          workspaceContext,
          activeFile,
          openFiles,
          'auto',
          openrouterKey || undefined,
          performanceMode,
          geminiKey || undefined
        );
        const reader = stream.getReader();
        let buffer = '';
        let finalContent = '';
        let finalMode = detectedMode;
        let hasError = false;

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            buffer += value;
            const lines = buffer.split('\n');
            buffer = lines.pop() || '';

            for (const line of lines) {
              if (!line.startsWith('data: ')) continue;
              const data = line.slice(6).trim();
              if (data === '[DONE]') break;
              try {
                const event = JSON.parse(data);
                if (event.type === 'explain') {
                  setExplainText((prev) => prev + event.content);
                } else if (event.type === 'explain_done') {
                  // açıklama bitti, ajan adımları geliyor — explainText korunur
                } else if (event.type === 'done') {
                  finalContent = event.content;
                  setExplainText('');
                  if (event.mode) { finalMode = event.mode; setDetectedMode(event.mode); }
                } else if (event.type === 'model_routed') {
                  routedModelRef.current = event.model;
                  setRoutedModel(event.model);
                } else if (event.type === 'error') {
                  hasError = true;
                  onTerminalLog?.(`[error] ${event.content}`);
                  setMessages((prev) => [...prev, { role: 'assistant', content: `❌ Hata: ${event.content}`, mode: 'Error' }]);
                } else if (event.type === 'file_changed') {
                  onRefreshExplorer?.();
                } else if (event.type === 'confirm_request') {
                  const confirm = { sessionId: event.session_id, confirm: event.confirm ?? { title: event.question ?? event.tool, detail: '', risk: 'low' }, tool: event.tool };
                  pendingConfirmRef.current = confirm;
                  setPendingConfirm(confirm);
                } else {
                  if (event.type === 'tool_call') {
                    onTerminalLog?.(`> ${event.content}`);
                    if (event.tool && ['write_file','edit_file','delete_file','create_dir','rename_file'].includes(event.tool)) {
                      const m = event.content.match(/\(([^)]+)\)/);
                      if (m) {
                        const fname = normalizeFilePath(m[1].split(',')[0].replace(/['"]/g, '').trim());
                        if (fname && !changedFilesRef.current.includes(fname)) {
                          changedFilesRef.current = [...changedFilesRef.current, fname];
                        }
                      }
                    }
                  }
                  if (event.type === 'tool_result') onTerminalLog?.(event.content);
                  stepsRef.current = [...stepsRef.current, event];
                  setStreamingSteps((prev) => [...prev, event]);
                }
              } catch (e) {
                console.error('JSON parse error in stream:', e, data);
              }
            }
          }
        } catch (streamErr) {
          hasError = true;
          setMessages((prev) => [...prev, { role: 'assistant', content: '⚠️ Bağlantı koptu veya AI sunucusu yanıt vermeyi bıraktı.' }]);
        }

        setStreamingSteps([]);
        if (!hasError && finalContent) {
          const capturedSteps = stepsRef.current.length > 0 ? [...stepsRef.current] : undefined;
          const capturedFiles = changedFilesRef.current.length > 0 ? [...changedFilesRef.current] : undefined;
          const modeLabel = finalMode.charAt(0).toUpperCase() + finalMode.slice(1);
          setMessages((prev) => [...prev, { role: 'assistant', content: finalContent, model: routedModelRef.current ?? undefined, mode: modeLabel, steps: capturedSteps, changedFiles: capturedFiles }]);
        }
        onRefreshExplorer?.();
        fetchBudget();
      }
      setIsConnected(true);
    } catch (err) {
      setMessages((prev) => [...prev, { role: 'assistant', content: 'Backend sunucusuna bağlanılamadı veya Ollama kapalı.' }]);
      setIsConnected(false);
    } finally {
      // If waiting for user confirmation, keep isLoading=true so the confirm UI stays visible
      if (!pendingConfirmRef.current) {
        setIsLoading(false);
        setRequestStartedAt(null);
        setRequestElapsedMs(0);
        setStreamingSteps([]);
        setAskStreamText('');
      }
    }
  };

  const handleConfirm = async (accepted: boolean) => {
    const confirm = pendingConfirmRef.current;
    if (!confirm) return;
    pendingConfirmRef.current = null;
    setPendingConfirm(null);

    if (!accepted) {
      await api.agentReject(confirm.sessionId);
      setMessages((prev) => [...prev, { role: 'assistant', content: 'İşlem kullanıcı tarafından iptal edildi.', mode: 'Agent' }]);
      setIsLoading(false);
      setRequestStartedAt(null);
      setRequestElapsedMs(0);
      setStreamingSteps([]);
      return;
    }

    // Resume the stream after user accepted
    const stream = api.agentResume(confirm.sessionId);
    const reader = stream.getReader();
    let buffer = '';
    let finalContent = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += value;
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';
        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const data = line.slice(6).trim();
          if (data === '[DONE]') break;
          try {
            const event = JSON.parse(data);
            if (event.type === 'done') {
              finalContent = event.content;
            } else if (event.type === 'error') {
              setMessages((prev) => [...prev, { role: 'assistant', content: `❌ Hata: ${event.content}`, mode: 'Agent Error' }]);
            } else if (event.type === 'file_changed') {
              onRefreshExplorer?.();
            } else if (event.type === 'confirm_request') {
              const nextConfirm = { sessionId: event.session_id, confirm: event.confirm ?? { title: event.question ?? event.tool, detail: '', risk: 'low' }, tool: event.tool };
              pendingConfirmRef.current = nextConfirm;
              setPendingConfirm(nextConfirm);
              return; // keep isLoading true, wait for next confirm
            } else {
              if (event.type === 'tool_call') {
                onTerminalLog?.(`> ${event.content}`);
                if (event.tool && ['write_file','edit_file','delete_file','create_dir','rename_file'].includes(event.tool)) {
                  const m = event.content.match(/\(([^)]+)\)/);
                  if (m) {
                    const fname = m[1].split(',')[0].replace(/['"]/g, '').trim();
                    if (fname && !changedFilesRef.current.includes(fname)) {
                      changedFilesRef.current = [...changedFilesRef.current, fname];
                    }
                  }
                }
              }
              if (event.type === 'tool_result') onTerminalLog?.(event.content);
              stepsRef.current = [...stepsRef.current, event];
              setStreamingSteps((prev) => [...prev, event]);
            }
          } catch (e) {
            console.error('Resume stream parse:', e);
          }
        }
      }
    } catch {
      /* stream error */
    }

    if (finalContent) {
      const capturedSteps = stepsRef.current.length > 0 ? [...stepsRef.current] : undefined;
      const capturedFiles = changedFilesRef.current.length > 0 ? [...changedFilesRef.current] : undefined;
      setMessages((prev) => [...prev, { role: 'assistant', content: finalContent, model: routedModelRef.current ?? undefined, mode: 'Agent', steps: capturedSteps, changedFiles: capturedFiles }]);
    }
    onRefreshExplorer?.();
    setIsLoading(false);
    setRequestStartedAt(null);
    setRequestElapsedMs(0);
    setStreamingSteps([]);
  };

  const handleCopy = (content: string, id: number) => {
    navigator.clipboard.writeText(content);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const handleRegenerate = () => {
    const lastUserMsg = [...messages].reverse().find((m) => m.role === 'user');
    if (lastUserMsg) {
      let filteredMessages = [...messages];
      if (messages[messages.length - 1]?.role === 'assistant') {
        filteredMessages = filteredMessages.slice(0, -1);
      }
      setMessages(filteredMessages);
      handleSend(lastUserMsg.content, filteredMessages);
    }
  };

  useEffect(() => {
    localStorage.setItem(LS_PERSONA, persona);
  }, [persona]);

  const emptyTitle = 'AkyuzIDE';
  const emptySub = 'Komutunu yaz - mod otomatik algilanir (Agent / Ask / Plan).';

  const elapsedSec = (requestElapsedMs / 1000).toFixed(1);
  const lastStep = streamingSteps[streamingSteps.length - 1];
  const flowLabel =
    lastStep?.type === 'tool_call'
      ? 'Araç çağrısı çalışıyor'
      : lastStep?.type === 'tool_result'
        ? 'Araç çıktısı işleniyor'
        : lastStep?.type === 'env_status'
          ? 'Ortam doğrulanıyor'
          : detectedMode === 'ask'
            ? 'Yanıt üretiliyor'
            : 'Plan/agent akışı işleniyor';

  return (
    <div className="w-full min-w-0 min-h-0 bg-bg-main flex flex-col h-full overflow-hidden select-text">
      <div className="p-2 px-3 border-b border-border-ide flex justify-between items-center bg-bg-sidebar shrink-0 h-[35px] min-w-0">
        <div className="flex items-center gap-2">
          <div className={`w-1.5 h-1.5 rounded-full ${isConnected ? 'bg-[#32cd32]' : 'bg-red-500'} shadow-[0_0_8px_rgba(50,205,50,0.5)]`} />
          <span className="text-[10px] font-bold tracking-widest text-text-dim uppercase">AKYUZ AI</span>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowSettings((s) => !s)}
            title="AI Ayarları"
            className={`p-1 rounded transition-colors ${showSettings ? 'text-accent-ide bg-accent-ide/10' : 'text-[#858585] hover:text-white hover:bg-white/5'}`}
          >
            <Cpu size={13} />
          </button>
          <button
            onClick={onSave}
            disabled={isSaving}
            className="flex items-center gap-1.5 bg-accent-ide hover:bg-accent-ide/80 text-white px-2.5 py-1 rounded text-[10px] font-bold transition-all active:scale-90 disabled:opacity-50"
          >
            {isSaving ? <Loader2 size={11} className="animate-spin" /> : <Save size={11} />}
            Save
          </button>
          <button
            onClick={onRun}
            className="flex items-center gap-1.5 bg-[#2ea44f] hover:bg-[#238636] text-white px-2.5 py-1 rounded text-[10px] font-bold transition-all active:scale-95 shadow-[0_4px_10px_rgba(46,164,79,0.2)]"
          >
            <Play size={11} fill="currentColor" />
            Run
          </button>
        </div>
      </div>

      <AnimatePresence>
        {showSettings && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="border-b border-border-ide bg-[#1a1a1b] overflow-hidden shrink-0"
          >
            <div className="p-3 flex flex-col gap-2">
              {/* Ollama & Backend Hosts */}
              <div className="grid grid-cols-2 gap-2">
                <div className="flex flex-col gap-1">
                  <div className="text-[9px] text-white/50 font-semibold">Ollama Host (Port 11434)</div>
                  <input
                    type="text"
                    value={ollamaHostDraft}
                    onChange={(e) => setOllamaHostDraft(e.target.value)}
                    className="bg-[#2a2a2d] border border-border-ide rounded px-2 py-1.5 text-[10px] text-white font-mono"
                    placeholder="http://127.0.0.1:11434"
                  />
                </div>
                <div className="flex flex-col gap-1">
                  <div className="text-[9px] text-white/50 font-semibold">Backend Host (Opsiyonel)</div>
                  <input
                    type="text"
                    value={backendUrlDraft}
                    onChange={(e) => setBackendUrlDraft(e.target.value)}
                    className="bg-[#2a2a2d] border border-border-ide rounded px-2 py-1.5 text-[10px] text-white font-mono"
                    placeholder="Boşsa Ollama IP'si kullanılır"
                  />
                </div>
              </div>
              <button
                type="button"
                onClick={() => {
                  const oh = ollamaHostDraft.trim() || 'http://127.0.0.1:11434';
                  const bh = backendUrlDraft.trim() || 'http://127.0.0.1:8001';
                  setOllamaHost(oh);
                  setBackendUrl(bh);
                  localStorage.setItem(LS_OLLAMA, oh);
                  localStorage.setItem(LS_BACKEND, bh);
                  // Refreshing health or triggering a state change in api.ts is not strictly needed 
                  // because api.ts's BASE_URL is now dynamic via toString()
                }}
                className="w-full py-1.5 rounded bg-accent-ide/20 hover:bg-accent-ide/30 border border-accent-ide/40 text-accent-ide text-[10px] font-bold transition-colors"
              >
                Bağlantı Ayarlarını Kaydet
              </button>

              <div className="h-px bg-white/5 my-1" />

              {/* OpenRouter */}
              <div className="text-[10px] text-white/50 font-semibold pt-1">OpenRouter API Key</div>
              <div className="flex gap-2">
                <input
                  type="password"
                  value={openrouterKeyDraft}
                  onChange={(e) => setOpenrouterKeyDraft(e.target.value)}
                  className="flex-1 bg-[#2a2a2d] border border-border-ide rounded px-2 py-1.5 text-[11px] text-white font-mono"
                  placeholder="sk-or-..."
                />
                <button
                  type="button"
                  onClick={() => {
                    const k = openrouterKeyDraft.trim();
                    setOpenrouterKey(k);
                    localStorage.setItem(LS_OPENROUTER_KEY, k);
                  }}
                  className="px-3 py-1.5 rounded bg-accent-ide text-black text-[10px] font-bold shrink-0"
                >
                  Kaydet
                </button>
              </div>
              {openrouterKey && (
                <div className="flex flex-col gap-1.5">
                  <div className="flex items-center gap-1.5 text-[9px] text-emerald-400/80">
                    <span className="inline-block w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                    SmartRouter aktif — göreve göre otomatik model seçimi
                  </div>
                  {budget && (
                    <div className="bg-[#1a1a1c] rounded p-2 space-y-1">
                      <div className="flex justify-between text-[9px] text-white/50">
                        <span>Günlük bulut bütçesi</span>
                        <span className={budget.remaining < 0.30 ? 'text-amber-400' : 'text-white/40'}>
                          ${budget.spent.toFixed(4)} / ${budget.limit.toFixed(2)}
                        </span>
                      </div>
                      <div className="h-1 rounded-full bg-white/10 overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-all duration-500 ${
                            budget.remaining < 0.30 ? 'bg-amber-400' : 'bg-emerald-400'
                          }`}
                          style={{ width: `${Math.min((budget.spent / budget.limit) * 100, 100)}%` }}
                        />
                      </div>
                      <div className="text-[8px] text-white/30">
                        Kalan: ${budget.remaining.toFixed(4)}
                        {budget.remaining <= 0 && ' — Ollama\'ya geçildi'}
                      </div>
                    </div>
                  )}
                </div>
              )}
              <div className="h-px bg-white/5 my-1" />

              {/* Gemini API Key */}
              <div className="text-[10px] text-white/50 font-semibold pt-1">
                Google AI Studio Key
                <span className="ml-1 text-white/30 font-normal">(intent tespiti + açıklama)</span>
              </div>
              <div className="flex gap-2">
                <input
                  type="password"
                  value={geminiKeyDraft}
                  onChange={(e) => setGeminiKeyDraft(e.target.value)}
                  className="flex-1 bg-[#2a2a2d] border border-border-ide rounded px-2 py-1.5 text-[11px] text-white font-mono"
                  placeholder="AIza..."
                />
                <button
                  type="button"
                  onClick={() => {
                    const k = geminiKeyDraft.trim();
                    setGeminiKey(k);
                    localStorage.setItem(LS_GEMINI_KEY, k);
                  }}
                  className="px-3 py-1.5 rounded bg-accent-ide text-black text-[10px] font-bold shrink-0"
                >
                  Kaydet
                </button>
              </div>
              {geminiKey && (
                <div className="flex items-center gap-1.5 text-[9px] text-blue-400/80">
                  <span className="inline-block w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse" />
                  Gemini Flash aktif — ajan başlamadan önce size özet bilgi verilecek
                </div>
              )}
              {openrouterKeyDraft.startsWith('AIza') && (
                <div className="text-[9px] text-amber-400/80 bg-amber-400/10 rounded px-2 py-1">
                  Bu anahtar OpenRouter için değil, Google AI Studio formatında görünüyor. Yukarıdaki Gemini alanına kopyalayın.
                </div>
              )}

              <div className="text-[9px] text-white/35">İsteğe bağlı: sistem prompt / persona (tüm modlara eklenir)</div>
              <textarea
                value={persona}
                onChange={(e) => setPersona(e.target.value)}
                rows={2}
                className="w-full bg-[#2a2a2d] border border-border-ide rounded px-2 py-1 text-[10px] text-white/90 resize-none"
                placeholder="Örn: Basys3 üzerinde çalışıyorum; Chisel kullanma..."
              />
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <div
        className="flex-1 p-3 flex flex-col gap-2 overflow-y-auto bg-bg-main"
        tabIndex={0}
        onKeyDown={handleMessagesKeyDown}
        ref={messagesAreaRef}
      >
        {messages.length === 0 && (
          <div className="text-center my-10 animate-in fade-in zoom-in duration-500">
            <div className="flex justify-center mb-4">
              <div className="relative p-4 bg-accent-ide/5 rounded-full border border-accent-ide/20">
                <Bot size={40} className="text-accent-ide drop-shadow-glow" />
                {detectedMode === 'agent' && <Sparkles size={16} className="absolute top-2 right-2 text-accent-ide animate-bounce" />}
              </div>
            </div>
            <div className="font-bold text-[15px] text-white">{emptyTitle}</div>
            <div className="text-[11px] text-text-dim px-6 mt-2 leading-relaxed select-text">{emptySub}</div>
          </div>
        )}

        {messages.map((m, i) => (
          <div key={i} className="group py-1.5 border-b border-white/5 last:border-b-0 animate-in slide-in-from-bottom-2 duration-300">
            <div className="flex items-center justify-between gap-2 mb-1">
              <div className={`text-[10px] font-semibold tracking-wide ${m.role === 'user' ? 'text-accent-ide' : 'text-white/70'}`}>
                {m.role === 'user' ? 'SEN' : 'AKYUZ AI'}
                {m.mode && m.role === 'assistant' ? ` · ${m.mode}` : ''}
              </div>
              {m.model && (() => {
                const isCloud = m.model.includes('/');
                const label = isCloud ? m.model.split('/').pop() : m.model;
                return (
                  <div className={`flex items-center gap-1 text-[9px] truncate max-w-[60%] ${isCloud ? 'text-sky-400/60' : 'text-white/35'}`}>
                    <span>{isCloud ? '☁' : '🖥'}</span>
                    <span className="truncate">{label}</span>
                  </div>
                );
              })()}
            </div>
            {m.role === 'user'
              ? <div className="whitespace-pre-wrap text-[12.5px] leading-relaxed text-white/92 select-text">{m.content}</div>
              : <>
                  {m.steps && m.steps.length > 0 && <CollapsibleSteps steps={m.steps} />}
                  <MessageContent content={m.content} />
                  {/* VCD dalga görüntüleyici butonu */}
                  {m.role === 'assistant' && (() => {
                    const vcdMatch = m.content.match(/VCD dosyası oluşturuldu:\s*([^\n]+)/);
                    if (!vcdMatch) return null;
                    const vcdFile = vcdMatch[1].trim();
                    return (
                      <button
                        onClick={() => setWaveformPath(vcdFile)}
                        className="mt-2 flex items-center gap-1.5 px-2.5 py-1 rounded bg-accent-ide/10 border border-accent-ide/30 text-accent-ide text-[10px] hover:bg-accent-ide/20 transition-colors"
                      >
                        <Activity size={11} />
                        Dalga Formunu Göster
                      </button>
                    );
                  })()}
                  {m.changedFiles && m.changedFiles.length > 0 && (
                    <div className="mt-2 flex flex-col gap-0.5 font-mono text-[10.5px]">
                      {m.changedFiles.map((f, fi) => (
                        <div key={fi} className="flex items-center gap-1.5 text-white/50 min-w-0" title={f}>
                          <span className="text-emerald-400/60 shrink-0">M</span>
                          <span className="truncate">{f}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </>
            }
            {m.role === 'assistant' && (
              <div className="flex items-center gap-3 mt-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-150">
                <button
                  onClick={() => handleRegenerate()}
                  title="Yeniden Oluştur"
                  className="text-text-dim hover:text-white transition-colors cursor-pointer p-0.5 flex items-center gap-1"
                >
                  <RotateCcw size={12} />
                  <span className="text-[10px]">Re-run</span>
                </button>
                <button
                  onClick={() => handleCopy(m.content, i)}
                  title="Kopyala"
                  className="text-text-dim hover:text-white transition-colors cursor-pointer p-0.5 flex items-center gap-1"
                >
                  {copiedId === i ? <Check size={12} className="text-accent-ide" /> : <Copy size={12} />}
                  <span className="text-[10px]">{copiedId === i ? 'Copied' : 'Copy'}</span>
                </button>
              </div>
            )}
          </div>
        ))}
        {isLoading && detectedMode === 'ask' && (
          <div className="space-y-2 py-1">
            <div className="flex items-center gap-2 text-[10px] text-cyan-200/90">
              <Loader2 size={12} className="animate-spin" />
              <span>{flowLabel} · {elapsedSec}s</span>
            </div>
            {askStreamText ? (
              <div className="text-[11px] text-white/85 whitespace-pre-wrap leading-relaxed px-2 py-1.5 border-l-2 border-accent-ide/60 bg-accent-ide/5">
                {askStreamText}
              </div>
            ) : (
              <div className="flex items-center gap-2 text-text-dim text-[11px] font-medium px-2 py-1 border-l-2 border-accent-ide/60 self-start animate-pulse">
                <Loader2 size={14} className="animate-spin text-accent-ide" />
                <span>Yanıt akıyor… ({elapsedSec}s)</span>
              </div>
            )}
          </div>
        )}
        {/* Gemini Flash açıklaması — ajan adımları başlamadan önce gösterilir */}
        {isLoading && explainText && (
          <div className="flex flex-col gap-1 py-1">
            <div className="flex items-center gap-1.5 text-[9px] text-blue-400/70">
              <span className="inline-block w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse shrink-0" />
              <span>Gemini · Görev analizi</span>
            </div>
            <div className="text-[11px] text-white/75 whitespace-pre-wrap leading-relaxed px-2 py-1.5 border-l-2 border-blue-400/50 bg-blue-400/5 rounded-r">
              {explainText}
            </div>
          </div>
        )}

        {isLoading && (detectedMode === 'agent' || detectedMode === 'plan') && (
          <div className="flex flex-col py-1">
            {/* Canlı adım akışı */}
            {(() => {
              const pairs = groupSteps(streamingSteps);
              const lastIdx = pairs.length - 1;
              return pairs.map((p, pi) => (
                <LiveStepBlock
                  key={pi}
                  call={p.call}
                  result={p.result}
                  isRunning={pi === lastIdx && !p.result && !pendingConfirm}
                />
              ));
            })()}
            {/* Adım yokken başlangıç göstergesi */}
            {streamingSteps.filter(s => s.type === 'tool_call').length === 0 && !pendingConfirm && (
              <div className="flex items-center gap-2 text-[10px] text-white/35 py-1 font-mono">
                <Loader2 size={11} className="animate-spin shrink-0" />
                <span>{detectedMode === 'plan' ? 'Plan modu başlatılıyor' : 'Agent başlatılıyor'} · {elapsedSec}s</span>
              </div>
            )}
            {pendingConfirm ? (
              <div className="mt-1 border border-white/20 rounded-xl bg-[#161618] overflow-hidden shadow-2xl">
                {/* Header */}
                <div className={`px-3 py-2 flex items-center gap-2 border-b border-white/10 ${
                  pendingConfirm.confirm.risk === 'high' ? 'bg-red-500/10' :
                  pendingConfirm.confirm.risk === 'medium' ? 'bg-amber-500/10' :
                  'bg-accent-ide/10'
                }`}>
                  <span className={`text-[10px] font-bold tracking-wide ${
                    pendingConfirm.confirm.risk === 'high' ? 'text-red-400' :
                    pendingConfirm.confirm.risk === 'medium' ? 'text-amber-400' :
                    'text-accent-ide'
                  }`}>
                    {pendingConfirm.confirm.risk === 'high' ? '⚠ ' : ''}Akyuz AI izin istiyor
                  </span>
                </div>
                {/* Title */}
                <div className="px-3 pt-2.5 pb-1">
                  <div className="text-[12px] font-semibold text-white/90">{pendingConfirm.confirm.title}</div>
                </div>
                {/* Detail */}
                {pendingConfirm.confirm.detail && (
                  <div className="mx-3 mb-2 bg-[#0d0d0f] border border-white/8 rounded-lg px-2.5 py-2 font-mono text-[10px] text-white/60 whitespace-pre-wrap break-all max-h-[120px] overflow-y-auto">
                    {pendingConfirm.confirm.detail}
                  </div>
                )}
                {/* Buttons */}
                <div className="px-3 pb-3 flex gap-2">
                  <button
                    type="button"
                    onClick={() => handleConfirm(false)}
                    className="px-3 py-1.5 rounded-lg bg-[#2a2a2d] hover:bg-[#3a3a3d] border border-white/10 text-white/70 text-[10px] font-bold transition-colors"
                  >
                    İptal  <span className="text-white/30 font-normal">esc</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => handleConfirm(true)}
                    className={`flex-1 px-3 py-1.5 rounded-lg text-white text-[10px] font-bold transition-colors ${
                      pendingConfirm.confirm.risk === 'high'
                        ? 'bg-red-600 hover:bg-red-500'
                        : 'bg-accent-ide hover:bg-accent-ide/80'
                    }`}
                  >
                    İzin ver
                  </button>
                </div>
              </div>
            ) : streamingSteps.length === 0 ? (
              <div className="flex items-center gap-2 text-text-dim text-[11px] px-2 py-1 border-l-2 border-accent-ide/50 animate-pulse">
                <Loader2 size={13} className="animate-spin text-accent-ide" />
                <span>{detectedMode === 'plan' ? 'Plan modu çalışıyor…' : 'Agent başlatılıyor…'} ({elapsedSec}s)</span>
              </div>
            ) : null}
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      <div className="p-3 border-t border-border-ide bg-bg-main shrink-0 min-w-0">
        <div className="flex flex-col gap-2 mb-3 min-w-0">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1.5 min-w-0">
            {/* Auto-detected mode badge */}
            <div className="flex items-center gap-1.5 shrink-0">
              <div className={`flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-bold border ${
                detectedMode === 'agent'
                  ? 'bg-accent-ide/10 border-accent-ide/40 text-accent-ide'
                  : detectedMode === 'plan'
                    ? 'bg-violet-600/10 border-violet-500/40 text-violet-400'
                    : 'bg-accent-ide/10 border-accent-ide/40 text-accent-ide'
              }`}>
                {detectedMode === 'agent' && <span className="font-mono text-[11px] leading-none opacity-80">∞</span>}
                {detectedMode === 'plan' && <ListOrdered size={9} />}
                {detectedMode === 'ask' && <MessageSquare size={9} />}
                <span>{detectedMode === 'agent' ? 'Agent' : detectedMode === 'plan' ? 'Plan' : 'Ask'}</span>
              </div>
              <span className="text-[9px] text-white/25">· otomatik</span>
            </div>
          </div>

          {/* Performance Mode Selector */}
          <div className="flex items-center gap-1.5 w-full min-w-0">
            <Cpu size={10} className="text-accent-ide/60 shrink-0" />
            <span className="text-[9px] text-white/30 shrink-0">Performans:</span>
            {(['low', 'auto', 'high'] as const).map((mode) => (
              <button
                key={mode}
                type="button"
                onClick={() => setPerformanceMode(mode)}
                className={`px-2.5 py-1 rounded-md text-[10px] font-bold border transition-all ${
                  performanceMode === mode
                    ? 'bg-accent-ide text-black border-accent-ide'
                    : 'bg-[#2a2a2d] text-text-dim border-border-ide hover:text-white hover:bg-[#323235]'
                }`}
                title={
                  mode === 'low'
                    ? 'Düşük — llama3.1:8b (hızlı, basit görevler)'
                    : mode === 'auto'
                    ? 'Otomatik — mesajı analiz ederek model seçer'
                    : 'Yüksek — qwen3:latest (karmaşık mühendislik)'
                }
              >
                {mode === 'low' ? 'Düşük' : mode === 'auto' ? 'Otomatik' : 'Yüksek'}
              </button>
            ))}
            {routedModel && (() => {
              const isCloud = routedModel.includes('/');
              const label = isCloud ? routedModel.split('/').pop() : routedModel;
              return (
                <span className={`text-[9px] truncate ml-1 flex items-center gap-1 ${isCloud ? 'text-sky-400/50' : 'text-white/30'}`}>
                  → <span>{isCloud ? '☁' : '🖥'}</span> {label}
                </span>
              );
            })()}
            {openrouterKey && budget && (
              <span className={`text-[9px] ml-auto shrink-0 ${budget.remaining < 0.30 ? 'text-amber-400/70' : 'text-white/25'}`}>
                ${budget.spent.toFixed(3)} / ${budget.limit.toFixed(2)}
                {budget.remaining <= 0 && ' ⚠ Ollama'}
              </span>
            )}
          </div>
        </div>

        <div className="relative">
          <textarea
            ref={textareaRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && (e.preventDefault(), handleSend())}
            rows={1}
            placeholder="Komut yaz - mod otomatik algilanir..."
            className="w-full bg-[#2a2a2d] border border-border-ide p-3 pr-10 rounded-xl text-[13px] text-white/90 focus:outline-none focus:border-accent-ide transition-[border-color] resize-none placeholder:text-text-dim/50 overflow-hidden leading-relaxed"
            style={{ minHeight: '45px', maxHeight: '220px' }}
          />
          <button
            type="button"
            onClick={() => handleSend()}
            disabled={isLoading || !input.trim()}
            className="absolute right-3 bottom-3 p-1.5 bg-accent-ide text-black rounded-lg hover:brightness-110 disabled:opacity-20 transition-all shadow-lg active:scale-90"
          >
            <Send size={16} />
          </button>
        </div>
      </div>
      {/* Waveform Viewer Modal */}
      {waveformPath && (
        <WaveformViewer vcdPath={waveformPath} onClose={() => setWaveformPath(null)} />
      )}
    </div>
  );
};

export default ChatPanel;
