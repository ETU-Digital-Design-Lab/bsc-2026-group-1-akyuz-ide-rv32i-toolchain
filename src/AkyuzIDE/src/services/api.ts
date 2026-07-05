/** Geliştirmede boş = aynı origin (Vite proxy /api → :8001). Üretim/Electron dosya: 127.0.0.1:8001 */
function resolveApiBase(): string {
  const savedBackend = typeof window !== 'undefined' ? localStorage.getItem('akyuz_backend_url') : null;
  if (savedBackend && savedBackend.trim()) return savedBackend.replace(/\/$/, '');

  // Eğer Backend URL yoksa, Ollama Host'un IP'sini alıp 8001 portuna yönlendirelim
  const savedOllama = typeof window !== 'undefined' ? localStorage.getItem('akyuz_ollama_host') : null;
  if (savedOllama && savedOllama.trim()) {
    try {
      const url = new URL(savedOllama);
      // Ollama IP'sini al, portu 8001 yap
      return `${url.protocol}//${url.hostname}:8001`;
    } catch (e) {
      // Eğer URL formatı hatalıysa (sadece IP girilmişse vb.) manuel temizlik yapalım
      const host = savedOllama.replace(/^https?:\/\//, '').split(':')[0];
      return `http://${host}:8001`;
    }
  }

  if (typeof window === 'undefined') return 'http://127.0.0.1:8001';

  // Electron production (file://) veya browser hostname üzerinden devam et
  const h = window.location.hostname && window.location.hostname !== 'localhost' 
    ? window.location.hostname 
    : '127.0.0.1';
    
  return `http://${h}:8001`;
}

/** BASE_URL'i her seferinde yeniden hesaplayan bir yapıya geçiyoruz ki ayarlar değişince yansısın. */
const BASE_URL = {
  toString() { return resolveApiBase(); }
};

export interface FileInfo {
  name: string;
  path: string;
  type: 'file' | 'dir';
}

export const api = {
  getHealth: async () => {
    const res = await fetch(`${BASE_URL}/api/health`);
    if (!res.ok) throw new Error('Failed to fetch health');
    return res.json() as Promise<{ status: string; workspace?: string }>;
  },

  // --- Hardware ---
  getPorts: async () => {
    const res = await fetch(`${BASE_URL}/api/hardware/ports?t=${Date.now()}`);
    if (!res.ok) throw new Error('Failed to fetch ports');
    return res.json();
  },

  compileFile: async (filePath: string, outputName: string = 'program') => {
    const res = await fetch(`${BASE_URL}/api/hardware/compile`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ file_path: filePath, output_name: outputName }),
    });
    if (!res.ok) throw new Error('Compilation failed');
    return res.json();
  },

  uploadFile: async (port: string, filePath: string, baud: number = 115200) => {
    const res = await fetch(`${BASE_URL}/api/hardware/upload`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ port, file_path: filePath, baud }),
    });
    if (!res.ok) throw new Error('Upload failed');
    return res.json();
  },

  vivadoBuild: async (files: string[], topModule: string, part: string) => {
    const res = await fetch(`${BASE_URL}/api/vivado/build`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ files, top_module: topModule, part }),
    });
    return res.json();
  },

  vivadoProgram: async (bitstreamPath: string) => {
    const res = await fetch(`${BASE_URL}/api/vivado/program`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ bitstream_path: bitstreamPath }),
    });
    return res.json();
  },

  getVivadoFullLog: async (logPath: string) => {
    const res = await fetch(`${BASE_URL}/api/files/${encodeURIComponent(logPath)}`);
    if (!res.ok) throw new Error('Failed to fetch log');
    const data = await res.json();
    return data.content;
  },

  // --- Files ---
  getFiles: async () => {
    const res = await fetch(`${BASE_URL}/api/files?t=${Date.now()}`);
    if (!res.ok) throw new Error('Failed to fetch files');
    return res.json();
  },

  setWorkspace: async (path: string) => {
    const res = await fetch(`${BASE_URL}/api/workspace/set`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path }),
    });
    return res.json();
  },

  readFile: async (path: string) => {
    const res = await fetch(`${BASE_URL}/api/files/${encodeURIComponent(path)}`);
    if (!res.ok) throw new Error('Failed to read file');
    const data = await res.json();
    return data.content;
  },

  writeFile: async (path: string, content: string) => {
    const res = await fetch(`${BASE_URL}/api/files/${encodeURIComponent(path)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    });
    return res.json();
  },

  deleteFile: async (path: string) => {
    const res = await fetch(`${BASE_URL}/api/files/${encodeURIComponent(path)}`, {
      method: 'DELETE',
    });
    return res.json();
  },

  renameFile: async (oldPath: string, newPath: string) => {
    const res = await fetch(`${BASE_URL}/api/files/rename`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ old_path: oldPath, new_path: newPath }),
    });
    return res.json();
  },

  // --- Simulation ---
  runSimulationAuto: async () => {
    const res = await fetch(`${BASE_URL}/api/simulate/auto`, { method: 'POST' });
    return res.json();
  },

  runSimulation: async (files: string[], topModule: string = 'tb_top') => {
    const res = await fetch(`${BASE_URL}/api/simulate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ files, top_module: topModule }),
    });
    return res.json();
  },

  // --- Assembler ---
  assemble: async (source: string) => {
    const res = await fetch(`${BASE_URL}/api/assemble`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source }),
    });
    return res.json();
  },

  /** Ollama + Icarus (iverilog) + Vivado yolu — ayrıntılı JSON. */
  getEdaHealth: async (remoteHost?: string) => {
    const q = remoteHost ? `?host=${encodeURIComponent(remoteHost)}` : '';
    const res = await fetch(`${BASE_URL}/api/health/eda${q}`);
    if (!res.ok) throw new Error('EDA health check failed');
    return res.json();
  },

  // --- AI Chat ---
  chat: async (messages: any[], remoteHost?: string, model?: string, systemPrompt?: string) => {
    const res = await fetch(`${BASE_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        messages, 
        remote_host: remoteHost,
        model: model,
        system_prompt: systemPrompt
      }),
    });
    return res.json();
  },

  agentChat: async (
    message: string,
    remoteHost?: string,
    model?: string,
    systemPrompt?: string,
    activeFile?: string,
    openFiles?: string[],
    agentMode?: string
  ) => {
    const res = await fetch(`${BASE_URL}/api/agent/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        remote_host: remoteHost,
        model,
        system_prompt: systemPrompt,
        active_file: activeFile,
        open_files: openFiles,
        agent_mode: agentMode || 'auto',
      }),
    });
    return res.json();
  },

  agentStream: (
    message: string,
    history?: any[],
    systemPrompt?: string,
    activeFile?: string,
    openFiles?: string[],
    agentMode?: string,
    apiKey?: string,
    performanceMode?: string,
    geminiKey?: string
  ): ReadableStream => {
    return new ReadableStream({
      async start(controller) {
        const res = await fetch(`${BASE_URL}/api/agent/stream`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message,
            history: history || [],
            system_prompt: systemPrompt,
            active_file: activeFile,
            open_files: openFiles,
            agent_mode: agentMode || 'auto',
            api_key: apiKey || undefined,
            performance_mode: performanceMode || 'auto',
            gemini_key: geminiKey || undefined,
          }),
        });
        const reader = res.body!.getReader();
        const decoder = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          controller.enqueue(decoder.decode(value));
        }
        controller.close();
      },
    });
  },

  /** Ollama streaming; SSE lines same shape as agent (chunk / done / error). */
  chatStream: (messages: any[], remoteHost?: string, model?: string, systemPrompt?: string): ReadableStream => {
    return new ReadableStream({
      async start(controller) {
        const res = await fetch(`${BASE_URL}/api/chat/stream`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            messages,
            remote_host: remoteHost,
            model,
            system_prompt: systemPrompt,
          }),
        });
        const reader = res.body!.getReader();
        const decoder = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          controller.enqueue(decoder.decode(value));
        }
        controller.close();
      },
    });
  },

  runTerminalCommand: async (command: string) => {
    const res = await fetch(`${BASE_URL}/api/terminal`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command }),
    });
    return res.json();
  },

  getModels: async (ollamaHost?: string) => {
    const q = ollamaHost ? `?host=${encodeURIComponent(ollamaHost)}` : '';
    const res = await fetch(`${BASE_URL}/api/models${q}`);
    if (!res.ok) return { models: [] as string[], error: res.statusText };
    return res.json() as Promise<{ models: string[]; host?: string; error?: string }>;
  },

  pullModel: async (name: string, ollamaHost?: string) => {
    const res = await fetch(`${BASE_URL}/api/models/pull`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, host: ollamaHost || undefined }),
    });
    let data: unknown = {};
    try {
      data = await res.json();
    } catch {
      /* empty body */
    }
    if (!res.ok) {
      const detail =
        typeof data === 'object' && data !== null && 'detail' in data
          ? String((data as { detail: unknown }).detail)
          : res.statusText;
      throw new Error(detail || `HTTP ${res.status}`);
    }
    return data;
  },

  pullModelStream: (name: string, ollamaHost?: string): ReadableStreamDefaultReader<string> => {
    const ctrl = new AbortController();
    const stream = new ReadableStream<string>({
      async start(controller) {
        try {
          const res = await fetch(`${BASE_URL}/api/models/pull/stream`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, host: ollamaHost || undefined }),
            signal: ctrl.signal,
          });
          const reader = res.body!.getReader();
          const dec = new TextDecoder();
          let buf = '';
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            buf += dec.decode(value, { stream: true });
            const lines = buf.split('\n');
            buf = lines.pop() || '';
            for (const line of lines) {
              if (line.startsWith('data: ')) controller.enqueue(line.slice(6).trim());
            }
          }
        } catch (e) {
          controller.error(e);
        } finally {
          controller.close();
        }
      },
      cancel() { ctrl.abort(); },
    });
    return stream.getReader();
  },

  getProjectPlan: async () => {
    const res = await fetch(`${BASE_URL}/api/agent/plan`);
    if (!res.ok) throw new Error('Failed to fetch plan');
    return res.json();
  },

  agentResume: (sessionId: string): ReadableStream => {
    return new ReadableStream({
      async start(controller) {
        const res = await fetch(`${BASE_URL}/api/agent/resume`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ session_id: sessionId }),
        });
        const reader = res.body!.getReader();
        const decoder = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          controller.enqueue(decoder.decode(value));
        }
        controller.close();
      },
    });
  },

  agentReject: async (sessionId: string) => {
    const res = await fetch(`${BASE_URL}/api/agent/reject`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId }),
    });
    return res.json();
  },
};
