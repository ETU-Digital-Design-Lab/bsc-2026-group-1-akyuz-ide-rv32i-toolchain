# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AkyuzIDE is an EDA-focused IDE for RISC-V/FPGA development with an integrated AI assistant (Ollama/OpenRouter), Monaco editor, Verilog simulation (Icarus), Vivado FPGA toolchain, and a RISC-V assembler. The system consists of a React/Vite frontend and a Python FastAPI backend.

## Commands

### Frontend (React + Vite)
```bash
npm install
npm run dev          # Dev server on :3001, proxies /api → :8001
npm run build        # TypeScript check + Vite build
npm run lint         # TypeScript type check only (tsc --noEmit)
npm run build:desktop  # Vite build + electron-builder → release/
```

### Backend (FastAPI)
```bash
cd server
pip install -r requirements.txt
uvicorn main:app --reload --port 8001
```

### Training Dataset
```bash
python training/riscv_agent_dataset/validate_dataset.py training/riscv_agent_dataset/train.seed.jsonl
python training/riscv_agent_dataset/build_train_full.py
python training/benchmark/release_gate.py
```

## Architecture

### Two-Process Model
The app always requires both processes running simultaneously:
- **Frontend** (Vite, `:3001`): In dev, `/api` requests are proxied to `:8001` via `vite.config.ts`. In Electron/production (file: protocol), `src/services/api.ts` hardcodes `http://127.0.0.1:8001` as the base URL.
- **Backend** (FastAPI, `:8001`): All business logic, tool execution, and AI calls live here.

### Backend Structure (`server/`)
- `main.py`: FastAPI app, all REST endpoints, CORS, workspace init.
- `services/agent/engine.py`: Active agent loop (streaming).
- `services/providers/`: LLM provider abstraction. `OllamaProvider` and `OpenRouterProvider` both implement `LLMProvider` base. Qwen3 models get special `think` flag handling (off in agent mode, on in ask/plan).
- `services/agent/mode_detector.py`: Auto-classifies each user message as `agent`, `ask`, or `plan` using Turkish+English keyword regex. Agent mode = tool calls; ask mode = pure text; plan mode = read-only tools only.
- `services/tools/`: Stateless async tool handlers imported into `engine.py` as `ALL_TOOLS` dict. File-mutating tools (`write_file`, `edit_file`, `delete_file`, `create_dir`, `rename_file`) are in `FILE_OP_TOOLS` and trigger a confirmation step via `_PENDING_SESSIONS` in `main.py`.

### Frontend Structure (`src/`)
- `services/api.ts`: Single source of truth for all backend calls. All fetch calls go through the `api` object. Two streaming patterns: `ReadableStream` (for agent/chat SSE) and `ReadableStreamDefaultReader` (for model pull progress).
- `App.tsx`: Top-level layout and state orchestration.
- `components/ChatPanel.tsx`: AI chat UI, handles both stream and non-stream responses, agent mode selection.
- `components/Editor.tsx`: Monaco editor wrapper with language detection.
- `components/Terminal.tsx`: Calls `/api/terminal` for shell command execution.
- `components/VivadoPanel.tsx` / `components/CCompilerPanel.tsx`: EDA-specific panels.
- `components/HardwareSidebar.tsx`: Serial port management, flash/compile actions.

### Electron (`electron/`)
- `main.ts`: Electron main process, spawns the Python backend as a child process.
- `preload.ts`: Context bridge for IPC.
- Electron is bundled via `vite-plugin-electron` in `vite.config.ts`. Electron entry is `dist-electron/main.js` after build.

## Key Configuration

`.env` (from `.env.example`):
```
GEMINI_API_KEY=        # Optional; for @google/genai usage
OLLAMA_HOST=http://127.0.0.1:11434   # Local Ollama
REMOTE_AI_HOST=http://127.0.0.1:11434
APP_URL=
```
Backend also reads `WORKSPACE_DIR` (defaults to `./workspace/`).

## Important Implementation Details

- **Path safety**: All backend file paths go through `_upath()` which applies NFC Unicode normalization — required for Turkish filenames (ş, ğ, ı, etc.) on some filesystems.
- **Agent confirmation flow**: File-mutating tool calls are intercepted before execution. The engine pauses, streams a `confirm_required` event to the frontend, and waits for `/api/agent/resume` or `/api/agent/reject` with the `session_id`.
- **Qwen3 think tokens**: `OllamaProvider` strips `<think>...</think>` blocks from Qwen3 responses before returning content. In agent mode, `think=False` is set to prevent malformed tool call output.
- **HMR**: Disabled when `DISABLE_HMR=true` env var is set (used in AI Studio embedded mode to prevent flickering during agent file edits).
- **Agent MAX_ITERATIONS**: Hard-capped at 30 in `engine.py` to prevent runaway loops.

## Training Module

`training/riscv_agent_dataset/` contains SFT training data for teaching the agent's `agent`/`ask`/`plan` behavior patterns. The JSONL format is documented in `schema.md`. After generating or modifying data, always validate with `validate_dataset.py` before feeding into a LoRA/QLoRA pipeline. The system's RTX 5070 Ti (16 GB VRAM) with CUDA 12.0 supports QLoRA fine-tuning via `transformers` + `peft`.
