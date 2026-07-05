"""
server/services/ai_remote.py — AkyuzIDE Modernized AI Service
=============================================================
Interface for Ollama (local or remote via Tailscale).
"""

import os
import httpx
import json
from typing import List, Dict, Generator, Any

class AIService:
    def __init__(self, base_url: str = "http://localhost:11434", model: str = "qwen3:latest", api_key: str = None):
        # Default to localhost if base_url is empty
        self.api_key = api_key
        clean_url = (base_url or "http://localhost:11434").strip()
        
        # OpenRouter/OpenAI logic: if it's openrouter, use its specific base
        if "openrouter.ai" in clean_url or self.api_key:
            self.base_url = clean_url.rstrip('/')
        else:
            # Ensure base_url has a protocol for Ollama
            if not clean_url.startswith(('http://', 'https://')):
                self.base_url = f"http://{clean_url}".rstrip('/')
            else:
                self.base_url = clean_url.rstrip('/')
        
        self.model = model

    def _get_headers(self):
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
            headers["X-Title"] = "AkyuzIDE"
        if "ngrok" in self.base_url:
            headers["ngrok-skip-browser-warning"] = "true"
        return headers

    async def chat(self, messages: List[Dict[str, str]]) -> Dict[str, Any]:
        """
        Sends a chat request to Ollama or OpenRouter.
        """
        is_openai_compat = self.api_key or "v1" in self.base_url
        
        if is_openai_compat:
            url = f"{self.base_url}/chat/completions"
            payload = {
                "model": self.model,
                "messages": messages,
                "stream": False
            }
        else:
            url = f"{self.base_url}/api/chat"
            payload = {
                "model": self.model,
                "messages": messages,
                "stream": False
            }
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            try:
                response = await client.post(url, json=payload, headers=self._get_headers())
                response.raise_for_status()
                data = response.json()
                
                # Normalize response
                if is_openai_compat:
                    if "choices" in data and len(data["choices"]) > 0:
                        return {"message": data["choices"][0]["message"]}
                    return {"error": "Invalid OpenAI-compatible response", "raw": data}
                else:
                    return data
            except httpx.ConnectError:
                return {"error": f"Could not connect to AI service at {self.base_url}."}
            except Exception as e:
                return {"error": str(e)}

    async def chat_stream(self, messages: List[Dict[str, str]]) -> Generator[str, None, None]:
        """
        Streams chat responses. (Simplified normalization for now)
        """
        # (Omitted full stream implementation for OpenRouter for now as AgentEngine handles its own streaming)
        # We can expand this if basic chat streaming is needed in frontend.
        pass

    def update_config(self, base_url: str, model: str, api_key: str = None):
        if not base_url.startswith(('http://', 'https://')) and not api_key:
            self.base_url = f"http://{base_url}".rstrip('/')
        else:
            self.base_url = base_url.rstrip('/')
        self.model = model
        self.api_key = api_key

