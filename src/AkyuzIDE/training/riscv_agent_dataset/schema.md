# JSONL Schema

Her satir bagimsiz bir JSON nesnesidir.

```json
{
  "id": "agent-read-001",
  "mode": "agent",
  "messages": [
    { "role": "system", "content": "optional mode/system hint" },
    { "role": "user", "content": "kullanici mesaji" }
  ],
  "assistant": "<tool_call>{\"tool\":\"read_file\",\"args\":{\"path\":\"cpu/core.v\"}}</tool_call>",
  "tags": ["riscv", "tool_call", "single_step"]
}
```

## Alanlar

- `id` (zorunlu, string): benzersiz satir kimligi
- `mode` (zorunlu, enum): `agent | ask | plan`
- `messages` (zorunlu, array): sohbet baglami
- `assistant` (zorunlu, string): modelin bu turda verecegi cikti
- `tags` (opsiyonel, array[string]): siniflandirma/filtreleme

## Kalite Kurallari

1. `agent` kayitlarinda:
   - Tool cagrisi varsa yalnizca bir adet olmali.
   - JSON parse edilebilir olmali.
   - Tool ismi su whitelist'te olmali:
     - `read_file`
     - `write_file`
     - `run_command`
     - `compile_verilog`
     - `run_simulation`
     - `prepare_vivado_build`
     - `run_vivado_flow`
     - `program_fpga`
     - `get_vivado_full_log`
     - `get_board_info`
     - `generate_project_plan`
2. `ask` kayitlarinda tool cagrisi olmamali.
3. `plan` kayitlarinda file-write veya shell-riskli adimlar yerine plan odagi korunmali.
4. `assistant` alaninda markdown code fence kullanmamaya calis (` ``` `).
5. Turkiye Turkcesi aciklama + kod/komutlarda English terimler birlikte kullanilabilir.

## Multistep Ornek

Multistep davranis, bir onceki adimin sonucu `messages` icinde `user` rolunde `<tool_result>...</tool_result>` olarak verilir:

```json
{
  "id": "agent-multistep-002",
  "mode": "agent",
  "messages": [
    { "role": "user", "content": "main.c derlenmiyor, duzelt." },
    { "role": "assistant", "content": "<tool_call>{\"tool\":\"run_command\",\"args\":{\"command\":\"riscv-none-elf-gcc -Wall -Werror main.c -o main.elf\"}}</tool_call>" },
    { "role": "user", "content": "<tool_result>\nmain.c:12: error: ...\n</tool_result>" }
  ],
  "assistant": "<tool_call>{\"tool\":\"read_file\",\"args\":{\"path\":\"main.c\"}}</tool_call>"
}
```
