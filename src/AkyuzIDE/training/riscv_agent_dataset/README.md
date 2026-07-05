# RISC-V Agent Dataset (AkyuzIDE)

Bu klasor, AkyuzIDE'deki `Agent / Ask / Plan` davranisini ogretmek icin SFT odakli bir baslangic veri seti icerir.

## Dosyalar

- `schema.md`: JSONL satir formati ve kalite kurallari
- `train.seed.jsonl`: Baslangic egitim ornekleri
- `eval.seed.jsonl`: Egitime dahil edilmemesi gereken dogrulama seti
- `validate_dataset.py`: JSONL format ve tool-call dogrulama scripti
- `codex_generation_prompt.md`: Codex ile veri setini buyutme komutu

## Hedef Davranis

- `agent` modunda:
  - Tek adimda en fazla bir tool cagir
  - Tool JSON formati: `<tool_call>{"tool":"...","args":{...}}</tool_call>`
  - `tool_result` sonrasinda ya yeni tek tool cagir ya da final metin don
- `ask` modunda:
  - Tool cagrisi yok, teknik cevap ve aciklama var
- `plan` modunda:
  - Sadece readonly/safe davranis
  - Gerekirse `read_file` / `generate_project_plan` ile baglam topla

## Hemen Kullan

```bash
python training/riscv_agent_dataset/validate_dataset.py training/riscv_agent_dataset/train.seed.jsonl
python training/riscv_agent_dataset/validate_dataset.py training/riscv_agent_dataset/eval.seed.jsonl
```

Validation temizse dosyalari LoRA/QLoRA pipeline'ina ver.
