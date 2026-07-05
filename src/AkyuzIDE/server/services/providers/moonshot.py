import httpx
import json
from .base import LLMProvider, LLMResponse, ToolCall

MOONSHOT_MODELS = [
    "kimi-latest",
    "kimi-k2",
    "kimi-k2-0725",
    "kimi-v1-8k",
    "kimi-v1-32k",
    "kimi-v1-128k",
    "kimi-v2-6",
]

class MoonshotProvider(LLMProvider):
    def __init__(self, api_key: str, model: str = "kimi-latest"):
        self.api_key = api_key
        self.model = model
        self.base_url = "https://api.moonshot.cn/v1"

    async def chat(self, messages, tools=None):
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 4096,
        }
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"

        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(f"{self.base_url}/chat/completions", headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()

        choice = (data.get("choices") or [{}])[0]
        msg = choice.get("message", {})
        content = (msg.get("content") or "").strip()
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
            tool_calls.append(ToolCall(name=fn.get("name", ""), arguments=args or {}))

        return LLMResponse(content=content, tool_calls=tool_calls)
