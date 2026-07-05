import httpx
import json
from .base import LLMProvider, LLMResponse, ToolCall

class OllamaProvider(LLMProvider):
    def __init__(self, host: str, model: str, mode: str = "agent"):
        clean = (host or "127.0.0.1:11434").strip()
        if not clean.startswith(("http://", "https://")):
            clean = f"http://{clean}"
        self.base_url = clean.rstrip("/")
        self.model = model
        self.mode = mode  # "agent" | "ask" | "plan"

    async def chat(self, messages, tools=None):
        is_qwen3 = "qwen3" in self.model.lower()
        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": 0.1, "num_predict": 4096},
        }
        if is_qwen3:
            # agent modunda araç çağrısı formatı bozulmasın → think=False
            # ask ve plan modunda derin akıl yürütme açık → think=True
            use_thinking = self.mode in ("ask", "plan")
            payload["options"]["think"] = use_thinking
        if tools:
            payload["tools"] = tools

        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(f"{self.base_url}/api/chat", json=payload)
            resp.raise_for_status()
            data = resp.json()

        msg = data.get("message", {})
        raw_content = (msg.get("content") or "").strip()
        # Strip <think>...</think> blocks (Qwen3 thinking tokens) from visible content
        import re as _re
        content = _re.sub(r"<think>.*?</think>", "", raw_content, flags=_re.DOTALL).strip()
        raw_calls = msg.get("tool_calls") or []

        tool_calls = []
        for tc in raw_calls:
            fn = tc.get("function", {})
            args = fn.get("arguments", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            tool_calls.append(ToolCall(name=fn.get("name", ""), arguments=args))

        return LLMResponse(content=content, tool_calls=tool_calls)
