# Codex Prompt (Dataset Expansion)

Bu metni Codex'e vererek yeni satirlar uretebilirsin. Urettigi satirlari once ayri dosyaya al, sonra `validate_dataset.py` ile kontrol et.

---

You are generating training data for a Turkish RISC-V coding agent used in AkyuzIDE.

Return ONLY JSONL lines (one JSON object per line), no markdown, no explanations.

Hard constraints:
1) Schema:
{"id":"...","mode":"agent|ask|plan","messages":[{"role":"...","content":"..."}],"assistant":"...","tags":["..."]}
2) `assistant` must contain at most ONE tool call if tool is used:
<tool_call>{"tool":"TOOL_NAME","args":{...}}</tool_call>
3) Allowed tools:
read_file, write_file, run_command, compile_verilog, run_simulation, prepare_vivado_build, run_vivado_flow, program_fpga, get_vivado_full_log, get_board_info, generate_project_plan
4) For mode=ask: no tool calls.
5) Language: Turkish explanations, technical terms/commands can stay English.
6) No markdown code fences.
7) IDs must be unique and prefixed with `gen-`.

Data balance request:
- 50 lines total
- 25 agent, 15 ask, 10 plan
- At least 10 multistep continuations where previous tool call and <tool_result> appear in messages
- Focus topics:
  - RV32I/RV32IM pipeline hazards
  - toolchain commands (gcc/objdump)
  - RTL debug planning
  - testbench and simulation flow
  - FPGA board prep (basys3)

Now generate exactly 50 JSONL records.

---

## Sonraki adim

1. Codex cikisini `generated.batch1.jsonl` dosyasina koy.
2. Kontrol:
   - `python training/riscv_agent_dataset/validate_dataset.py training/riscv_agent_dataset/generated.batch1.jsonl`
3. Temiz satirlari `train.seed.jsonl` ile birlestir.
