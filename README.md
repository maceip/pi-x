<p align="center">
  <img width="313" alt="pi-x" src="https://github.com/user-attachments/assets/b09fe7eb-37ae-425b-849f-f2ed88a5c829" />
</p>

# pi-x
pi agent optimized for [mtplx](https://github.com/youssofal/MTPLX) local coding

---
<p align="center">
<img width="534" height="320" alt="lv_0_20260830213708" src="https://github.com/user-attachments/assets/b50ec69d-45c8-4775-a045-a3c4ce56546b" />
</p>

## Interactive Agent Session Decode Speed

Measured live on Apple Silicon (M5 Max 128GB) running real autonomous multi-turn `AgentSession` workflows with high-effort reasoning, tool calling (`read`, `write`, `bash`, `grep`), and full session memory:

| Turn | Task / Agent Action | Generated Tokens | TTFT | Decode Time | Observed Decode Speed |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Turn 1** | Workspace analysis & dependency audit (`read`, `bash`) | 623 tok | 19.00s | 13.01s | **47.9 tok/s** |
| **Turn 2** | TS vector module implementation & test run (`write`, `bash`) | 4,096 tok | 298.97s* | 91.23s | **44.9 tok/s** |

**Average Live Decode Throughput:** **~46.4 tok/s** *(sustained across active tool-calling session loops)*

*\*TTFT on Turn 2 includes autonomous multi-step tool execution cycles and local TypeScript syntax verification before emitting final output.*

---

## What We Added & Changed

- **Metal Acceleration & Turbo Runtime:** Configured the MTPLX 2.10.2 backend with Stage-1 `mx.compile`, double-buffered async token decode (`MTPLX_ASYNC_AR=1`), pipelined AR, proactive memory admission shedding, and optimal unified memory allocation for Apple Silicon.
- **High-Precision Single-Row Status Rail:** Added a custom TUI extension that renders live Wired RAM, context usage (65.5k cap), real-time generation speed (`tok/s`), and background thermal telemetry using Unicode fractional blocks without taking extra vertical screen space.
- **Autonomous Tooling & Keyless Web Search:** Integrated local filesystem tools (`read`, `write`, `edit`, `bash`, `grep`, `find`) with multi-provider web search (DuckDuckGo keyless scraper / Tavily / Brave) and token-budgeted HTML-to-Markdown web fetch.
- **Specialized Engineering Skills:** Added modular agent skills for strict TypeScript architecture, D3.js v7+ visualization pipelines (`selection.join`, transitions), and browser/Canvas application engineering.
- **Durability & Session Management:** Added single-instance process locking, unified `config.env` tuning, automatic 50MB log rotation, and session continuation/pruning flags (`-c`, `-r`, `--clean`, `--status`).

---

## Requirements

This harness is built for large unified-memory Apple Silicon machines:

- **More than 80GB total RAM** (the launcher exits politely below that)
- **mtplx 2.10.2+** (discovered from a homedir `uv` venv first, then from system Python)
- A **4-bit Qwen 3.8 Flash-Next** checkpoint, or the published speed fallback below

## Quick Start

Copy and paste this. It does not require a prior clone:

```bash
curl -fsSL https://raw.githubusercontent.com/maceip/pi-x/main/bootstrap.sh | bash
```

That command will:

1. Clone this repo to `~/pi-x` if you are not already inside a checkout
2. Refuse to continue on machines with 80GB of RAM or less
3. Find `uv` and look for `mtplx` in a homedir uv venv; otherwise use a system/python `mtplx`
4. Offer to install or upgrade `mtplx` if it is missing or older than **2.10.2**
5. Search for a local 4-bit Qwen 3.8 Flash-Next model
6. If none is found, offer to download [`Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed`](https://huggingface.co/Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed) with a progress bar
7. Start MTPLX with the discovered or downloaded model and drop you into the Pi TUI

Already cloned the repo? From the checkout:

```bash
./run_agent.sh
```

Override the clone destination with `PI_X_HOME=/somewhere/pi-x` if you do not want `~/pi-x`.

---

## Detailed Running & Usage Guide

### 1. Launching & Session Management

```bash
# Launch interactive agent session
./run_agent.sh

# Continue the most recent session
./run_agent.sh -c

# Open the interactive session picker
./run_agent.sh -r

# View live system status, active server PID, and model routing
./run_agent.sh --status

# Prune old conversation session files
./run_agent.sh --clean

# Run without loading skills (raw baseline)
./run_agent.sh --no-skills
```

### 2. Server Management & Diagnostics

```bash
# Manually start the background MTPLX server (with auto log rotation)
./start_mtplx.sh

# Restart the background MTPLX server
./run_agent.sh --restart

# Gracefully stop the MTPLX server
./stop_mtplx.sh

# Run the automated end-to-end test suite (API, Tools, Web Search, Skills)
./test_pi_setup.sh
```

---

## Architecture & Configuration

### Unified Configuration (`config.env`)
All server acceleration, context limits, reasoning effort, and agent bells can be configured centrally in `config.env`:

```bash
# Server & Model Routing
MTPLX_PORT=8000
MTPLX_CONTEXT_WINDOW=65536
MTPLX_PROFILE=turbo
MTPLX_MTP_DEPTH=3

# Reasoning
MTPLX_REASONING=on
MTPLX_REASONING_EFFORT=high

# Agent UX
PI_ENABLE_BELL=1
PI_BELL_THRESHOLD_S=15
PI_MAX_LOG_SIZE_MB=50
```

### Context Window & Decode Sizing
- **Configured Context Window**: **65,536 tokens** (`--context-window 65536`).
- **Rationale**: Keeps decoding in the peak **~45–48 tok/s** sweet spot of Qwen 3.8 Flash-Next, preventing long-context decode cliff degradation while providing ample context depth for complex multi-turn coding sessions.
- **Compaction**: Automatically triggers when approaching the context ceiling to preserve the last 24,000 tokens of conversational state.

### Active MTPLX Acceleration Knobs
| Environment Variable | Value | Purpose |
| :--- | :--- | :--- |
| `MTPLX_QWEN4EXP_COMPILE` | `1` | Stage-1 `mx.compile` GDN layer compilation |
| `MTPLX_COMPILED_GDN` | `1` | Graph compilation for GDN recurrent steps |
| `MTPLX_AR_PIPELINE` | `1` | Pipelined autoregressive lane |
| `MTPLX_SYNC_AR` | `0` | Double-buffered asynchronous token decode |
| `MTPLX_NGRAM_RESIDENT` | `0` | Stream 32GB n-gram tables from SSD sidecar to preserve unified memory |
| `MTPLX_QSA_PREFILL` | `1` | Flash / gathered QSA kernel execution |
| `MTPLX_FUSED_*` | `1` | Fused Gate+Up, GDN in-proj, ConvNorm, Step, HC v3, and QSA indexer |
| `MTPLX_ENGINE_RAM_FRACTION` | `0.90` | Allocate 90% of available memory envelope to engine |
| `MTPLX_MEMORY_LIMIT_BYTES` | 90% of RAM | Unified memory budget, scaled to the host |
| `MTPLX_WIRED_LIMIT_BYTES` | 85% of RAM | Metal wired memory ceiling, scaled to the host |

---

## Directory Layout

```
pi-x/
├── bootstrap.sh               # Copy-paste entry (clone-if-needed + launch)
├── run_agent.sh               # Main interactive TUI launcher with CLI shortcuts
├── start_mtplx.sh             # Background accelerated server daemon with log rotation
├── stop_mtplx.sh              # Clean process terminator
├── test_pi_setup.sh           # End-to-end verification suite
├── config.env                 # Centralized user-editable configuration
├── lib/preflight.sh           # RAM / uv / mtplx / model discovery & host scaling
├── pi                         # Portable Pi CLI wrapper
├── package.json               # Node workspace manifest
├── tsconfig.json              # TypeScript configuration
├── logs/
│   ├── mtplx.log              # Server logs (auto-rotated at 50MB)
│   ├── mtplx.pid              # Active server PID
│   └── agent.lock             # Single-instance process lock
└── .pi/
    ├── settings.json          # Agent settings (model, default tools, compaction, thinking)
    ├── models.json            # Model provider definitions (MTPLX endpoint & capabilities)
    ├── sessions/              # Persistent conversation history files
    ├── extensions/
    │   ├── status-bar.ts      # Status rail (RAM, CTX, tok/s, thermal warning, bell alert)
    │   └── web-tools.ts       # web_search & web_fetch extensions
    └── skills/
        ├── typescript-expert/ # TypeScript strict engineering skill
        ├── d3-visualization/  # D3.js v7+ data visualization skill
        └── browser-apps/      # Browser, DOM, Canvas & Web Worker skill
```
