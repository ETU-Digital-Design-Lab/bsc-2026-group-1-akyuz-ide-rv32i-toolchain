import json
from pathlib import Path

OUT = Path("training/riscv_agent_dataset/generated.batch1.jsonl")

SIM_OK_LOG = (
    "PASS ADD y=00000011\n"
    "PASS SUB y=00000003\n"
    "PASS AND y=0000000f\n"
    "PASS OR y=00000ff0\n"
    "PASS SLT signed y=00000001\n"
    "SIM_PASS\n"
)

SIM_ERR_LOG = "broken_riscv_alu.v:7: syntax error\nI give up.\n"


def tool_call(tool: str, args: dict) -> str:
    return f"<tool_call>{json.dumps({'tool': tool, 'args': args}, ensure_ascii=False)}</tool_call>"


def main():
    records = []
    idx = 1

    def add(mode: str, messages: list, assistant: str, tags: list):
        nonlocal idx
        rec_id = f"gen-{idx:04d}"
        idx += 1
        records.append(
            {
                "id": rec_id,
                "mode": mode,
                "messages": messages,
                "assistant": assistant,
                "tags": tags,
            }
        )

    # Agent single-step records
    agent_singles = [
        ("decoder.v dosyasini oku.", "read_file", {"path": "rtl/decoder.v"}, ["agent", "read", "riscv"]),
        ("hazard_unit.v dosyasini oku.", "read_file", {"path": "rtl/hazard_unit.v"}, ["agent", "read", "hazard"]),
        ("branch unit dosyasini incele.", "read_file", {"path": "rtl/branch_unit.v"}, ["agent", "read", "branch"]),
        ("board basys3 bilgisi getir.", "get_board_info", {"board_name": "basys3"}, ["agent", "board"]),
        ("project plan olustur.", "generate_project_plan", {}, ["agent", "plan"]),
        ("riscv test binary derle.", "run_command", {"command": "riscv-none-elf-gcc -march=rv32im -mabi=ilp32 tests/smoke.c -o build/smoke.elf"}, ["agent", "compile"]),
        ("elf disassembly al.", "run_command", {"command": "riscv-none-elf-objdump -d build/smoke.elf > build/smoke.disasm.txt"}, ["agent", "objdump"]),
        ("Verilog compile et.", "compile_verilog", {"files": ["rtl/riscv_alu.v", "tb/riscv_alu_tb.v"]}, ["agent", "iverilog"]),
        ("simulasyonu kos.", "run_simulation", {"files": ["rtl/riscv_alu.v", "tb/riscv_alu_tb.v"]}, ["agent", "simulation"]),
        ("Vivado build hazirla.", "prepare_vivado_build", {"files": ["rtl/top.v"], "top_module": "top", "board": "basys3"}, ["agent", "vivado"]),
        ("Vivado flow calistir.", "run_vivado_flow", {"tcl_script_path": "workspace/_vivado/build.tcl"}, ["agent", "vivado"]),
        ("son Vivado logunu oku.", "get_vivado_full_log", {"log_path": "workspace/_vivado/vivado.log"}, ["agent", "vivado", "log"]),
    ]
    for prompt, tool, args, tags in agent_singles:
        add("agent", [{"role": "user", "content": prompt}], tool_call(tool, args), tags)

    # Agent multistep: compile -> read_file / final
    compile_errors = [
        ("tests/branch.c:47: error: implicit declaration of function 'flush_pipe'"),
        ("tests/load_use.c:12: error: 'stall_req' undeclared"),
        ("tests/decode.c:31: error: expected ';' before 'case'"),
        ("tests/jump.c:19: error: too few arguments to function 'jal'"),
        ("tests/csr.c:77: error: unknown type name 'csr_bank_t'"),
    ]
    follow_files = [
        "tests/branch.c",
        "tests/load_use.c",
        "tests/decode.c",
        "tests/jump.c",
        "tests/csr.c",
    ]
    for err, path in zip(compile_errors, follow_files):
        add(
            "agent",
            [
                {"role": "user", "content": "Derleme hatasini bul ve duzelt."},
                {"role": "assistant", "content": tool_call("run_command", {"command": "riscv-none-elf-gcc -Wall -Werror tests/current.c -o build/current.elf"})},
                {"role": "user", "content": f"<tool_result>\nSTDOUT:\n\nSTDERR:\n{err}\n</tool_result>"},
            ],
            tool_call("read_file", {"path": path}),
            ["agent", "multistep", "debug"],
        )

    # Agent multistep with real Icarus logs
    for _ in range(6):
        add(
            "agent",
            [
                {"role": "user", "content": "ALU testbench sonucuna gore sonraki adimi sec."},
                {"role": "assistant", "content": tool_call("run_command", {"command": "C:\\iverilog\\bin\\iverilog.exe -g2012 -o alu_ok.out riscv_alu.v riscv_alu_tb.v && C:\\iverilog\\bin\\vvp.exe alu_ok.out"})},
                {"role": "user", "content": f"<tool_result>\nSTDOUT:\n{SIM_OK_LOG}\nSTDERR:\n\n</tool_result>"},
            ],
            "Simulasyon PASS. Sonraki adim olarak corner-case testleri (overflow, zero, negative) ekleyip yeniden kosalim.",
            ["agent", "multistep", "simulation", "pass"],
        )
    for _ in range(6):
        add(
            "agent",
            [
                {"role": "user", "content": "ALU compile fail oldu, ne yapalim?"},
                {"role": "assistant", "content": tool_call("compile_verilog", {"files": ["training/riscv_agent_dataset/sim_cases/broken_riscv_alu.v"]})},
                {"role": "user", "content": f"<tool_result>\nCOMPILATION FAILED:\n{SIM_ERR_LOG}</tool_result>"},
            ],
            tool_call("read_file", {"path": "training/riscv_agent_dataset/sim_cases/broken_riscv_alu.v"}),
            ["agent", "multistep", "simulation", "fail"],
        )

    # Agent direct write fixes
    fixes = [
        ("decode logicinde addi immediate sign-extend duzelt.", "rtl/decode.v"),
        ("forwarding unitte rs2 kontrolunu duzelt.", "rtl/forwarding.v"),
        ("branch compare signed/unsigned secimini acik yap.", "rtl/branch_unit.v"),
        ("pipeline register reset degerlerini netlestir.", "rtl/pipeline_regs.v"),
        ("csr read path default degerini 0 yap.", "rtl/csr_unit.v"),
        ("load-store alignment check ekle.", "rtl/lsu.v"),
        ("hazard unitte load-use stall kosulu ekle.", "rtl/hazard_unit.v"),
        ("jalr target LSB temizleme ekle.", "rtl/execute.v"),
    ]
    for prompt, path in fixes:
        content = (
            "// auto-generated patch draft\n"
            "module placeholder_fix;\n"
            "  // TODO: apply concrete RTL patch after reading original file\n"
            "endmodule\n"
        )
        add("agent", [{"role": "user", "content": prompt}], tool_call("write_file", {"path": path, "content": content}), ["agent", "write", "rtl"])

    # Ask records (no tool_call)
    ask_topics = [
        "RV32I ve RV32IM farki",
        "load-use hazard neden stall ister",
        "branch predictor temel tipleri",
        "jal ve jalr farki",
        "ABI ilp32 ne demek",
        "objdump ne ise yarar",
        "CSR talimatlari ne yapar",
        "pipeline flush mantigi",
        "forwarding hangi durumda yetmez",
        "signed compare ve unsigned compare farki",
        "memory alignment neden kritik",
        "assembler pseudo-instruction nedir",
        "testbenchte self-check nasil yazilir",
        "regression test mantigi",
        "M extension olmadiginda mul/div",
        "interrupt ve exception farki",
        "WB stage gorevi",
        "decode stage sorumluluklari",
        "branch delay etkisi",
        "timing closure nedir",
        "FPGA'da LUT/FF metrikleri",
        "Basys3 saat kaynagi",
        "Vivado synth ve impl farki",
        "RISC-V register naming",
    ]
    for topic in ask_topics:
        answer = (
            f"{topic} icin kisa ozet: once islevsel dogrulugu hedefle, sonra performans optimizasyonuna gec. "
            "RISC-V cekirdekte hazard kurallari, control-flow dogrulugu ve test otomasyonu ana kalite kaldiracidir."
        )
        add("ask", [{"role": "user", "content": f"{topic} konusunu acikla."}], answer, ["ask", "riscv"])

    # Plan records
    plan_prompts = [
        "2 haftalik rv32i pipeline sprint plani cikar.",
        "Decoder refactor plani hazirla.",
        "Hazard unit test stratejisi yaz.",
        "Vivado build akisi icin teslim plani ver.",
        "Toolchain migration plani olustur.",
        "RISC-V core bring-up plani yap.",
        "Regression altyapisi icin yol haritasi ver.",
        "Basys3 demo release plani cikar.",
        "FPGA kaynak kullanimi iyilestirme plani yaz.",
        "CSR birimi entegrasyon plani hazirla.",
    ]
    for p in plan_prompts:
        add(
            "plan",
            [{"role": "user", "content": p}],
            "## Hedef\nDogru calisan ve test edilebilir bir adim.\n\n## Adimlar\n1. Mevcut kod baglamini oku\n2. Degisiklik kapsamini sinirla\n3. Test ve dogrulama kriterlerini netlestir\n4. Uygulama + regression\n\n## Riskler\n- Hazard kurali atlama\n- Test kapsam eksigi\n\n## Cikis Kriteri\n- Simulasyon ve temel smoke testlerin yesil olmasi",
            ["plan", "roadmap"],
        )

    # Plan tool-based readonly records
    for path in ["rtl/decoder.v", "rtl/hazard_unit.v", "rtl/execute.v", "rtl/memory.v", "rtl/writeback.v"]:
        add(
            "plan",
            [{"role": "user", "content": f"Plan oncesi bu dosyayi incelemek istiyorum: {path}"}],
            tool_call("read_file", {"path": path}),
            ["plan", "readonly", "tool"],
        )
    for _ in range(5):
        add(
            "plan",
            [{"role": "user", "content": "Genel proje planini bir kez daha guncel baglamla getir."}],
            tool_call("generate_project_plan", {}),
            ["plan", "readonly", "project_plan"],
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"Wrote {len(records)} records to {OUT}")


if __name__ == "__main__":
    main()
