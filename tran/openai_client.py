"""
openai_client.py

Unified OpenAI API client for all endpoints (Assistants, Completions, Files, Threads, Runs, Retrieval, etc.)

- Uses environment variables for API key and endpoint configuration.
- Supports python-dotenv for local development.
- All endpoint methods are documented with official OpenAI API reference URLs.
- Last updated: 2025-06-12
- Reference: https://platform.openai.com/docs/api-reference/overview
"""

import os
import datetime

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # dotenv is optional

import openai

# --- Provider Selection and Environment Setup ---
OPENAI_PROVIDER = os.getenv("OPENAI_PROVIDER", "azure").lower()  # 'azure' or 'openai'

# Azure OpenAI config from env only
AZURE_OPENAI_KEY = os.getenv("AZURE_OPENAI_KEY")
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT")
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION")

# OpenAI config from env only
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_ORG = os.getenv("OPENAI_ORG")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL")

# Select correct OpenAI client class
if OPENAI_PROVIDER == "azure":
    from openai import AzureOpenAI
    if not AZURE_OPENAI_KEY or not AZURE_OPENAI_ENDPOINT or not AZURE_OPENAI_API_VERSION:
        raise RuntimeError("[ERROR] Missing Azure OpenAI environment variables. Please check your .env file.")
    _client = AzureOpenAI(
        api_key=AZURE_OPENAI_KEY,
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_version=AZURE_OPENAI_API_VERSION,
    )
else:
    from openai import OpenAI
    if not OPENAI_API_KEY:
        raise RuntimeError("[ERROR] Missing OpenAI API key. Please check your .env file.")
    _client = OpenAI(
        api_key=OPENAI_API_KEY,
        base_url=OPENAI_BASE_URL or None,
        organization=OPENAI_ORG or None
    )

class OpenAIClient:
    """
    Unified OpenAI/Azure OpenAI API client for all endpoints.
    Provider is selected via OPENAI_PROVIDER env var (default: azure).
    See: https://platform.openai.com/docs/api-reference/overview and https://learn.microsoft.com/en-us/azure/ai-services/openai/reference
    Last updated: 2025-06-12
    """
    def __init__(self):
        self.provider = OPENAI_PROVIDER
        self.version = "2025-06-12"
        self.timestamp = datetime.datetime.now().isoformat()
        self._client = _client
        if self.provider == "azure":
            self.api_key = AZURE_OPENAI_KEY
            self.api_base = AZURE_OPENAI_ENDPOINT
            self.api_version = AZURE_OPENAI_API_VERSION
            self.deployment = AZURE_OPENAI_DEPLOYMENT
        else:
            self.api_key = OPENAI_API_KEY
            self.api_base = OPENAI_BASE_URL
            self.org = OPENAI_ORG

    # --- Chat Completions (auto-select endpoint) ---
    # https://platform.openai.com/docs/api-reference/chat/create
    def chat_completion(self, **kwargs):
        """
        Create a chat completion using the correct provider (Azure or OpenAI).
        For Azure, 'model' is the deployment name (see: https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#chat-completions)
        For OpenAI, use model name (see: https://platform.openai.com/docs/api-reference/chat/create)
        """
        if self.provider == "azure":
            # Azure expects 'model' to be the deployment name
            kwargs["model"] = self.deployment
            return self._client.chat.completions.create(**kwargs)
        else:
            return self._client.chat.completions.create(**kwargs)

    # --- File Upload (for RAG) ---
    # https://platform.openai.com/docs/api-reference/files
    def upload_file(self, file_path, purpose="assistants"):
        # Only allow valid purposes per OpenAI SDK, and cast to correct literal type
        from typing import cast, Literal
        valid_purposes = ["assistants", "batch", "fine-tune", "vision", "user_data", "evals"]
        if purpose not in valid_purposes:
            purpose = "assistants"
        # Cast to Literal for type checker compatibility
        file_purpose = cast(Literal["assistants", "batch", "fine-tune", "vision", "user_data", "evals"], purpose)
        with open(file_path, "rb") as f:
            return self._client.files.create(file=f, purpose=file_purpose)

    # --- Info Utility ---
    def info(self):
        key = self.api_key[:6] + "..." if self.api_key else None
        return {
            "provider": self.provider,
            "api_key": key,
            "api_base": self.api_base,
            "org": getattr(self, "org", None),
            "version": self.version,
            "timestamp": self.timestamp
        }

# Usage example (in other modules):
# from openai_client import OpenAIClient
# client = OpenAIClient()
# response = client.chat_completion(model="gpt-4o", messages=[...])
