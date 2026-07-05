"""
server/services/project_plan_manager.py — Adaptive Project Guidance
===================================================================
Tracks project progress and suggests the next appropriate steps.
"""

from typing import List, Dict, Any
import os

class ProjectStage:
    DESIGN = "Design"
    SYNTHESIS = "Synthesis"
    IMPLEMENTATION = "Implementation"
    BITSTREAM = "Bitstream"
    HARDWARE = "Hardware"

class ProjectPlanManager:
    def __init__(self, workspace_dir: str):
        self.workspace_dir = workspace_dir
        self.current_stage = ProjectStage.DESIGN

    def get_status(self) -> Dict[str, Any]:
        """Analyzes the workspace to determine the current project status."""
        status = {
            "stage": self.current_stage,
            "has_sources": False,
            "has_constraints": False,
            "has_bitstream": False,
            "next_actions": []
        }
        
        # Check files
        for root, dirs, files in os.walk(self.workspace_dir):
            for f in files:
                if f.endswith(('.v', '.sv')): status["has_sources"] = True
                if f.endswith('.xdc'): status["has_constraints"] = True
                if f.endswith('.bit'): status["has_bitstream"] = True

        # Determine stage logic
        if not status["has_sources"]:
            status["stage"] = ProjectStage.DESIGN
            status["next_actions"] = ["Write Verilog code", "Define Module IO"]
        elif not status["has_constraints"]:
            status["stage"] = ProjectStage.DESIGN
            status["next_actions"] = ["Generate XDC Constraints", "Verify Pin Map"]
        elif status["has_bitstream"]:
            status["stage"] = ProjectStage.BITSTREAM
            status["next_actions"] = ["Program Hardware", "Run Hardware Test"]
        else:
            status["stage"] = ProjectStage.SYNTHESIS
            status["next_actions"] = ["Run Vivado Synthesis", "Check Timing"]

        self.current_stage = status["stage"]
        return status

    def generate_plan_markdown(self) -> str:
        """Returns a formatted Markdown plan for the user to approve."""
        status = self.get_status()
        
        plan = f"## 🚀 Project Plan: {status['stage']} Stage\n\n"
        plan += "### Current Status\n"
        plan += f"- Source Files: {'✅' if status['has_sources'] else '❌'}\n"
        plan += f"- Constraints (XDC): {'✅' if status['has_constraints'] else '❌'}\n"
        plan += f"- Bitstream Ready: {'✅' if status['has_bitstream'] else '❌'}\n\n"
        
        plan += "### Proposed Next Steps\n"
        for i, action in enumerate(status["next_actions"], 1):
            plan += f"{i}. `[ ]` {action}\n"
            
        plan += "\n> [!TIP]\n> Adımları onaylıyorsan 'Onayla' diyebilirsin. Belirli adımları değiştirmek istersen bana söyle."
        
        return plan
