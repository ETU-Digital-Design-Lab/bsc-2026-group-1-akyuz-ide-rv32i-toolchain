from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

@dataclass
class ToolCall:
    name: str
    arguments: dict

@dataclass
class LLMResponse:
    content: Optional[str]
    tool_calls: list[ToolCall]  # empty list if none

class LLMProvider(ABC):
    @abstractmethod
    async def chat(self, messages: list[dict], tools: list[dict] | None = None) -> LLMResponse:
        """Send messages to LLM, get response with optional tool calls."""
        pass
