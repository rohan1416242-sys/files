# FCC Source Patches

These are the patched FCC source files used to build `free_claude_code-4.12.9-py3-none-any.whl`.

To rebuild the wheel from upstream FCC + these patches:

```bash
git clone https://github.com/alishahryar1/free-claude-code.git
cd free-claude-code

# Copy these patched files over the upstream ones
cp /path/to/fcc-source-patches/cli/claude_env.py src/free_claude_code/cli/
cp /path/to/fcc-source-patches/nvidia_nim/client.py src/free_claude_code/providers/nvidia_nim/
cp /path/to/fcc-source-patches/nvidia_nim/request_options.py src/free_claude_code/providers/nvidia_nim/
cp /path/to/fcc-source-patches/config/settings.py src/free_claude_code/config/
cp /path/to/fcc-source-patches/providers/admission.py src/free_claude_code/providers/
cp /path/to/fcc-source-patches/providers/openai_chat/provider.py src/free_claude_code/providers/openai_chat/

# Build the wheel (requires uv + Python 3.14)
uv python install 3.14
uv build --wheel --python 3.14
```

The resulting wheel will be in `dist/free_claude_code-4.12.9-py3-none-any.whl`.

## Files Modified

- `cli/claude_env.py` — Added 10 aggressive Claude Code env vars (max output, bash timeouts, thinking tokens, etc.) + bumped auto-compact window to 900K.
- `providers/nvidia_nim/client.py` — Treat NIM 403 "Authorization failed" and 429 as retryable rate-limits.
- `providers/nvidia_nim/request_options.py` — Send `reasoning_effort=max` as a top-level parameter (required by thinkingmachines/inkling).
- `config/settings.py` — Default model is `nvidia_nim/thinkingmachines/inkling`. HTTP_READ_TIMEOUT default is 0 (None). Rate limit defaults: 15 req/60s, concurrency 2.
- `providers/admission.py` — Max retries 5→10, base backoff 2.0→1.0s, max backoff 60→120s.
- `providers/openai_chat/provider.py` — Convert `http_read_timeout=0` to `None` (no timeout) for httpx.
