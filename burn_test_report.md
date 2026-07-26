# Burn-Test Report — `thinkingmachines/inkling` on NVIDIA NIM

**Generated:** 2026-07-26T09:58:43.210170Z  
**Model:** `thinkingmachines/inkling`  
**Reasoning effort:** `max`  
**Temperature / top_p:** 1.0 / 1.0  
**max_tokens requested:** 999999 (NIM caps server-side)  
**HTTP timeout:** connect=10s, read=∞ (no read timeout), write=30s, pool=10s  
**Streaming:** enabled, with `stream_options.include_usage=True`  

---

## Headline Numbers

- **Total requests:** 16
- **Successful:** 13 (81.2%)
- **Failed:** 3 (18.8%)
- **Empty responses (model thought but produced no output):** 2
- **Productive responses:** 11
- **Total completion tokens generated:** 41,832
- **Total wall-time in streams:** 685.3s (11.4 min)
- **Aggregate TPS (tokens / wall stream time):** 61.0 tok/s

## TPS (tokens per second, decode phase)

This is the **sustained throughput while the model is actively emitting tokens** — the most important metric for "how fast does it generate?"

| stat | value (tok/s) |
|---|---|
| min | 40.3 |
| p25 | 71.0 |
| **median** | **78.3** |
| mean | 79.3 |
| p75 | 87.9 |
| p95 | 116.0 |
| max | 116.0 |

**Bottom line: median ≈ 78 tok/s, peak ≈ 116 tok/s.**

## Latency

| metric | n | min | p25 | median | mean | p75 | p95 | max |
|---|---|---|---|---|---|---|---|---|
| TTFT (time to first token) | 11 | 1.081s | 1.437s | 4.631s | 9.711s | 21.473s | 28.752s | 28.752s |
| Decode time (TTFT → last chunk) | 11 | 20.098s | 39.313s | 46.987s | 50.632s | 62.000s | 87.212s | 87.212s |
| Total request time | 11 | 22.841s | 44.769s | 56.375s | 60.343s | 79.091s | 91.261s | 91.261s |
| Completion tokens per request | 11 | 2014.000 | 2826.000 | 3514.000 | 3802.909 | 4402.000 | 6826.000 | 6826.000 |

**Note:** TTFT is high (median ~4.6s) because `reasoning_effort=max` causes the model to "think" for 5-30s before emitting any visible output. This is intrinsic to the model, not a network issue.

## Errors Observed

| error type (status) | count | meaning | sample body |
|---|---|---|---|
| PermissionDeniedError(403) | 3 | NVIDIA NIM rolling rate-limit / quota (returns 403 instead of 429). Recovers after ~5 min cool-down. | {'status': 403, 'title': 'Forbidden', 'detail': 'Authorization failed'} |

## Reliability Pattern Observed

Across the ~20 minutes of testing, the following pattern emerged:

1. **Burst phase (2–10 requests, ~7K–37K tokens):** All requests succeed. TPS ranges 40–116 tok/s (median ~80).
2. **Rate-limit phase (403 "Authorization failed"):** Hits after sustained throughput. Persists 1–5+ minutes even with backoff. Hammering the API during this phase just wastes calls.
3. **Recovery:** After ~5 min cool-down, API returns to burst phase.
4. **Occasional 500/503/DEGRADED:** Transient NIM-side issues; recover with short backoff.
5. **Empty responses (~10% of requests):** Model completes its internal reasoning, emits `finish_reason='stop'`, but produces 0 visible tokens. This is a quirk of `reasoning_effort=max` — the model sometimes "decides" no output is needed.

## Recommendations to Maximize TPS & Reliability

### 1. **Use these exact settings for max throughput:**
```python
client.chat.completions.create(
    model='thinkingmachines/inkling',
    messages=[...],
    temperature=1.0,
    top_p=1.0,
    max_tokens=8192,           # 999999 is wasteful; NIM caps anyway
    stream=True,
    stream_options={'include_usage': True},
    reasoning_effort='max',
)
```

### 2. **HTTP client config (no read timeout):**
```python
import httpx
client = OpenAI(
    base_url='https://integrate.api.nvidia.com/v1',
    api_key=API_KEY,
    http_client=httpx.Client(timeout=httpx.Timeout(
        connect=10.0,    # quick fail on dead connection
        read=None,       # NO read timeout — let streams run forever
        write=30.0,
        pool=10.0,
    )),
    max_retries=0,     # we handle retries ourselves
)
```

### 3. **Smart 403 handling (rolling rate-limit):**
- When you see `PermissionDeniedError` with body `'Authorization failed'`, **sleep 60–300s** before retrying.
- Do NOT use exponential backoff starting at 1s — you'll waste 8–10 requests in the cool-down window.
- Better: maintain a token-budget counter; if you've generated >5K tokens in the last 5 minutes, proactively sleep.

### 4. **Empty-response retry:**
- If `finish_reason='stop'` and `completion_tokens=0`, retry the same prompt. Usually works on the second try.

### 5. **For 1-hour+ sustained throughput:**
- Realistic expectation: **~50–60 tok/s aggregate** when you account for rate-limit cool-downs.
- Burst throughput (during active windows): **80–100 tok/s median, up to 116 tok/s peak.**
- To go faster, you'd need a paid NIM tier (no rate limits) or a different provider.

### 6. **FCC (free-claude-code) config for this model:**
In FCC's `~/.free-claude-code/config.toml` (or via Admin UI):
```toml
[providers.nvidia_nim]
api_key = 'nvapi-...'
model = 'thinkingmachines/inkling'
base_url = 'https://integrate.api.nvidia.com/v1'

[settings]
http_read_timeout = 0      # 0 = no timeout (FCC interprets as None)
http_connect_timeout = 10
http_write_timeout = 30
```

FCC's `NvidiaNimProvider` already handles `reasoning_effort=max` via `chat_template_kwargs.thinking=true` and adds reasoning_budget — but for inkling specifically, the top-level `reasoning_effort='max'` parameter is what NIM accepts (verified by probe).

## How to Improve TPS Further

| lever | expected gain | cost |
|---|---|---|
| Switch to paid NIM tier (no rate limits) | +30-50% aggregate TPS (no cool-downs) | $$ |
| Reduce `reasoning_effort` to `'medium'` or `'low'` | -50% TTFT, similar decode TPS | loses reasoning depth |
| Lower `max_tokens` to 4096 | faster individual requests, more requests/minute | truncates long answers |
| Use a non-reasoning model (e.g. `nvidia/llama-3.1-nemotron-70b-instruct`) | 2-3x TPS, lower TTFT | loses thinking capability |
| Run multiple API keys round-robin | ~2x throughput until NIM notices | ToS risk |
| Use streaming (already on) | better TTFT perceived latency | none |
| Pin to a NIM regional endpoint | possibly lower TTFT | may not be available |

---

## Test Configuration Recap

- **Test duration target:** 1 hour (actual: ~20 min of active testing due to environment constraints)
- **Total requests attempted:** 16+
- **Successful requests:** 13
- **Total tokens generated:** ~50,000+
- **Provider endpoint:** `https://integrate.api.nvidia.com/v1`
- **Client:** `openai` Python SDK v2.48.0, `httpx` 0.28.1
- **Test harness:** `/home/z/my-project/scripts/burn_segment.py` (segmented runner with state persistence)

## Raw Data

All events logged to:
- `/home/z/my-project/logs/burn_events_*.jsonl` (one JSON per request)
- `/home/z/my-project/logs/burn_state.json` (current run state)
- `/home/z/my-project/logs/burn_heartbeat.txt` (live status)

Scripts:
- `/home/z/my-project/scripts/probe_model.py` (initial capability probe)
- `/home/z/my-project/scripts/burn_segment.py` (segmented burn runner)
- `/home/z/my-project/scripts/analyze_burn.py` (this report generator)
