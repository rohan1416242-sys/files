# MAX-TPS FCC for thinkingmachines/inkling

Patched **Free Claude Code v4.12.9** optimized for maximum throughput and aggressive token burning with the `thinkingmachines/inkling` model on NVIDIA NIM.

## Quick Install

### Windows (PowerShell)

1. Download `install-max-tps-fcc.ps1` and `free_claude_code-4.12.9-py3-none-any.whl` from this repo.
2. Put both files in the same folder.
3. Open PowerShell in that folder and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install-max-tps-fcc.ps1
```

Or with your NIM API key:

```powershell
.\install-max-tps-fcc.ps1 -ApiKey "nvapi-xxxxxxxxxxxxxxxxxxxx"
```

### macOS / Linux (bash)

1. Download `install-max-tps-fcc.sh` and `free_claude_code-4.12.9-py3-none-any.whl` from this repo.
2. Put both files in the same folder.
3. Run:

```bash
chmod +x install-max-tps-fcc.sh
NVIDIA_NIM_API_KEY=nvapi-xxxx ./install-max-tps-fcc.sh
```

## What's Patched (vs upstream FCC)

### NIM Provider Patches
1. **`reasoning_effort=max` sent as a top-level parameter** (instead of only `chat_template_kwargs.thinking=true`). Required by `thinkingmachines/inkling` on NIM.
2. **NIM 403 "Authorization failed" treated as retryable rate-limit** (not a hard permission denial).
3. **NIM 429 via generic `APIError` normalized to retryable** (NIM sometimes returns 429 wrong shape).
4. **Default model = `nvidia_nim/thinkingmachines/inkling`** across all 4 Claude tiers.

### FCC Retry Patches
5. **Max retry attempts: 5 → 10** — more chances to recover from NIM 429s.
6. **Base backoff: 2.0s → 1.0s** — first retry happens faster.
7. **Max backoff: 60s → 120s** — allow longer waits for NIM's rolling window.
8. **FCC rate limit: 40 req/60s → 15 req/60s** — gentler pace, fewer 429s.
9. **FCC max concurrency: 5 → 2** — NIM is single-threaded per key.

### Claude Code Aggressive Env Vars (NEW)
10. **`CLAUDE_CODE_AUTO_COMPACT_WINDOW=900000`** (was 190000) — uses inkling's full 1M context window before compacting. Eliminates the constant 30-60s compaction pauses that made Claude Code feel "lazy".
11. **`CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192`** — matches inkling's per-response cap. Prevents wasteful "exceeded 32000 token maximum" errors.
12. **`BASH_DEFAULT_TIMEOUT_MS=600000`** (10 min) — long bash commands don't get killed.
13. **`BASH_MAX_TIMEOUT_MS=1800000`** (30 min) — max bash timeout.
14. **`MCP_TIMEOUT=600000`** — 10 min MCP server startup.
15. **`MAX_MCP_OUTPUT_TOKENS=100000`** — more MCP output before truncation.
16. **`MAX_THINKING_TOKENS=8192`** — force max thinking tokens (no auto-reduce).
17. **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95`** — only compact at 95% (vs default 80%).
18. **`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1`** — prevent Claude from auto-reducing thinking depth.
19. **`DISABLE_BUG_COMMAND=1`** — skip the hidden bug-command API call.
20. **`HTTP_READ_TIMEOUT=0`** (None) — slow reasoning streams never get killed mid-thought.

## Measured Performance

| Metric | Value |
|---|---|
| Median sustained TPS (decode) | **78 tok/s** |
| Peak TPS | **116 tok/s** |
| Mean TPS | 79 tok/s |
| Median TTFT | 4.6s |
| Max context | 1M tokens |
| Max output per response | 8192 tokens |

## Files in This Repo

- `install-max-tps-fcc.ps1` — Windows PowerShell installer (one-shot)
- `install-max-tps-fcc.sh` — macOS/Linux bash installer
- `free_claude_code-4.12.9-py3-none-any.whl` — patched FCC wheel
- `burn_test_report.md` — full TPS analysis from the burn test
- `burn_test_charts.png` — TPS distribution + latency charts
- `README.md` — this file

## After Install

```bash
# Open a NEW terminal (so PATH updates take effect)

# Start the FCC proxy
fcc-server

# In another terminal, run Claude Code through FCC
fcc-claude
```

Admin UI: `http://127.0.0.1:8082/admin`

## Manual Uninstall

```bash
# Stop FCC
pkill -f "fcc-" 2>/dev/null

# Uninstall via uv
uv tool uninstall free-claude-code

# Remove config
rm -rf ~/.free-claude-code

# Remove Claude Code (optional)
npm uninstall -g @anthropic-ai/claude-code
```

## Notes

- **Rotate your NIM API key** if you've shared it anywhere.
- NIM has a rolling rate-limit that triggers 429/403 after sustained throughput (~7-15K tokens). The patched FCC retries up to 10 times with exponential backoff before failing.
- For truly unlimited throughput, upgrade to a paid NIM tier or use a different provider.
- `thinkingmachines/inkling` has 1M context but only 8192 max output tokens per response. The patches tune Claude Code to use the full context window without hitting the output cap.
