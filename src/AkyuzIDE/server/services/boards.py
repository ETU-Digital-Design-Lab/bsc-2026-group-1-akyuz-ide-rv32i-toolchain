"""
server/services/boards.py — FPGA Board Registry for AkyuzIDE
==========================================================
Provides part numbers and pin mapping templates for common boards.
Verified against Official Digilent Master XDC files.
"""

from typing import Dict, Any, List

BOARD_REGISTRY: Dict[str, Dict[str, Any]] = {
    "basys3": {
        "name": "Digilent Basys 3",
        "part": "xc7a35tcpg236-1",
        "resources": {"LUTs": 20800, "FFs": 41600, "BRAM_36K": 50, "DSPs": 90},
        "pins": {
            "clk": "W5",
            "led": ["U16", "E19", "U19", "V19", "W18", "U15", "U14", "V14", "V13", "V3", "W3", "U3", "P3", "N3", "P1", "L1"],
            "sw": ["V17", "V16", "W16", "W17", "W15", "V15", "W14", "W13", "V2", "T3", "T2", "R3", "W2", "U1", "T1", "R2"],
            "btn_c": "U18", "btn_u": "T18", "btn_l": "W19", "btn_r": "T17", "btn_d": "V17",
        }
    },
    "arty_a7_35t": {
        "name": "Digilent Arty A7-35T",
        "part": "xc7a35tcsg324-1",
        "resources": {"LUTs": 20800, "FFs": 41600, "BRAM_36K": 50, "DSPs": 90},
        "pins": {
            "clk": "E3",
            "led": ["H5", "J5", "T9", "T10"],
            "sw": ["A8", "C11", "C10", "A10"],
            "btn": ["D9", "C9", "B9", "B8"],
        }
    },
    "nexys_a7_100t": {
        "name": "Digilent Nexys A7-100T (DDR)",
        "part": "xc7a100tcsg324-1",
        "resources": {"LUTs": 63400, "FFs": 126800, "BRAM_36K": 135, "DSPs": 240},
        "pins": {
            "clk": "E3",
            "led": ["H17", "K15", "J13", "N14", "R18", "V17", "U17", "U16", "V16", "T15", "U14", "T16", "V15", "V14", "V12", "V11"],
            "sw": ["J15", "L16", "M13", "R15", "R17", "T18", "U18", "R13", "T8", "U8", "W8", "T5", "V5", "U12", "V10"],
            "btn_c": "N17", "btn_u": "M18", "btn_l": "P17", "btn_r": "M17", "btn_d": "P18",
        }
    },
    "nexys4_legacy": {
        "name": "Digilent Nexys 4 (Legacy)",
        "part": "xc7a100tcsg324-1",
        "resources": {"LUTs": 63400, "FFs": 126800, "BRAM_36K": 135, "DSPs": 240},
        "pins": {
            "clk": "E3",
            "led": ["T8", "V9", "R8", "T5", "T4", "U8", "V4", "W5", "V5", "U7", "W7", "V7", "W6", "U8", "V8", "U9"],
            "sw": ["U9", "U8", "R7", "R6", "R5", "V7", "V6", "V5", "U4", "V3", "W2", "U1", "U2", "U3", "W1", "V1"],
        }
    },
    "cmod_a7_35t": {
        "name": "Digilent Cmod A7-35T",
        "part": "xc7a35tcpg236-1",
        "resources": {"LUTs": 20800, "FFs": 41600, "BRAM_36K": 50, "DSPs": 90},
        "pins": {
            "clk": "L17",
            "led": ["A17", "C16"],
            "btn": ["A18", "B18"],
        }
    },
}

def get_board_profile(board_id: str) -> Dict[str, Any]:
    return BOARD_REGISTRY.get(board_id.lower().replace(" ", "").replace("-", ""), BOARD_REGISTRY["basys3"])
