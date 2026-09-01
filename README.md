<p align="center">
  <img width="313" alt="pi-x" src="https://github.com/user-attachments/assets/b09fe7eb-37ae-425b-849f-f2ed88a5c829" />
</p>

# pi-x
pi agent optimized for [mtplx 2.10.2+](https://github.com/youssofal/MTPLX) local coding on Apple Silicon.

---

## Autonomous Multi-Turn Coding Benchmark

Measured on Apple Silicon (M5 Max 128GB) running Qwen 3.8 Flash-Next with MTPLX 2.10.2, SSD SessionBank prefix caching, Stage-1 compilation, and multi-threadgroup QSA indexing across a real 5-turn autonomous coding session:

| Turn | Real Agent Task | Total Context | Cached Prefix | TTFT | Effective Prefill | Decode Speed |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Turn 1** | Workspace analysis & `package.json` init | 676 tok | 0 | 0.055s | **12,374 tok/s** | **76.2 tok/s** |
| **Turn 2** | `tsconfig` & module dependency audit | 3,336 tok | 676 tok | 0.057s | **58,175 tok/s** | **71.4 tok/s** |
| **Turn 3** | Vector math implementation & AST edits | 14,277 tok | 3,336 tok | 0.058s | **246,195 tok/s** | **68.8 tok/s** |
| **Turn 4** | Test execution & compiler trace analysis | 26,517 tok | 14,277 tok | 0.070s | **381,288 tok/s** | **64.5 tok/s** |
| **Turn 5** | Module refactoring & full verification | 43,335 tok | 26,517 tok | 0.110s | **395,168 tok/s** | **58.2 tok/s** |

---

## What We Added & Changed

- **MTPLX 2.10.2 Engine Acceleration:** Stage-1 `mx.compile` GDN layer compilation, double-buffered async token decode (`MTPLX_ASYNC_AR=1`), and pipelined AR execution.
- **SSD SessionBank Prefix Caching:** Enabled `MTPLX_SSD_SESSION_CACHE="on"` to cache prompt state across turns, scaling effective prefill throughput past **395k tok/s** with sub-100ms TTFT.
- **Deep-Context QSA Indexing & Quantization:** Fused block-sparse FlashAttention prefill (`MTPLX_QSA_FLASH=1`), 8-bit quantized pooled keys (`MTPLX_QSA_POOLED_BITS=8`), and adaptive MTP window caps to sustain 58–76 tok/s decode past 43k+ tokens.
- **Multimodal Vision & Caching:** Full image input support (OpenAI `image_url` and Anthropic base64 formats) backed by content-keyed surrogate session caching (`MTPLX_VISION_SESSION_CACHE=1`).
- **Memory Admission & Shedding:** Proactive eviction of stale session entries (`MTPLX_PREFILL_ADMISSION_SHED=1`) to eliminate memory wall stalls.
- **High-Precision Single-Row Status Rail:** Live Wired RAM, context meter (65.5k cap), real-time `tok/s`, thermal warnings, and completion bells without consuming vertical terminal lines.
- **Autonomous Tooling & Skills:** Built-in filesystem tools (`read`, `write`, `edit`, `bash`, `grep`, `find`), keyless web search/fetch, and engineering skills (TypeScript, D3.js v7, Browser/Canvas).

---

## Quick Start

**Requirements:** Apple Silicon Mac with >80GB unified RAM, `mtplx >= 2.10.2`, and a 4-bit Qwen 3.8 Flash-Next model.

```bash
# 1. One-line bootstrap (clones, checks RAM/Python, discovers models, launches Pi):
curl -fsSL https://raw.githubusercontent.com/maceip/pi-x/main/bootstrap.sh | bash

# 2. Or run directly from checkout:
./run_agent.sh
```

---

## CLI Cheatsheet

```bash
./run_agent.sh          # Launch interactive TUI session
./run_agent.sh -c       # Continue most recent session
./run_agent.sh -r       # Interactive session picker
./run_agent.sh --status # Show running server PID, port, and model
./run_agent.sh --clean  # Prune old session files
./start_mtplx.sh        # Start background MTPLX server with auto log rotation
./stop_mtplx.sh         # Gracefully terminate MTPLX daemon
./test_pi_setup.sh      # Run end-to-end test suite (API, Vision, Tools, Web Search, Skills)
```

---

## Configuration (`config.env`)

Centralized tuning for MTPLX acceleration, context limits, and agent behavior:

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `MTPLX_CONTEXT_WINDOW` | `65536` | Active context cap (optimal decode sweet spot) |
| `MTPLX_SSD_SESSION_CACHE` | `on` | Cache multi-turn prompt prefixes to SSD SessionBank |
| `MTPLX_QSA_FLASH` | `1` | Block-sparse QSA FlashAttention prefill kernel |
| `MTPLX_QSA_POOLED_BITS`| `8` | 8-bit quantized pooled key mirror for indexer scoring |
| `MTPLX_ASYNC_AR` | `1` | Double-buffered asynchronous GPU token decode |
| `MTPLX_PREFILL_ADMISSION_SHED` | `1` | Proactively shed stale session KV on large prompts |
| `MTPLX_VISION_SESSION_CACHE` | `1` | Content-keyed surrogate caching for image inputs |
| `PI_THINKING` | `off` | Toggle reasoning channel (`off` / `low` / `medium` / `high`) |
| `PI_ENABLE_BELL` | `1` | Terminal bell alert on long turns (>15s) |
