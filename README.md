<p align="center">
  <img width="313" alt="pi-x" src="https://github.com/user-attachments/assets/b09fe7eb-37ae-425b-849f-f2ed88a5c829" />
</p>

# pi-x
pi agent optimized for [mtplx](https://github.com/youssofal/MTPLX) local coding

---

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

- **Metal Acceleration & Turbo Runtime:** Configured the MTPLX backend with Stage-1 `mx.compile`, double-buffered async token decode (`MTPLX_SYNC_AR=0`), pipelined AR, and optimal unified memory allocation for Apple Silicon.
- **High-Precision Single-Row Status Rail:** Added a custom TUI extension that renders live Wired RAM, context usage (65.5k cap), and real-time generation speed (`tok/s`) using Unicode fractional blocks without taking extra vertical screen space.
- **Autonomous Tooling & Keyless Web Search:** Integrated local filesystem tools (`read`, `write`, `edit`, `bash`, `grep`, `find`) with multi-provider web search (DuckDuckGo keyless scraper / Tavily / Brave) and token-budgeted HTML-to-Markdown web fetch.
- **Specialized Engineering Skills:** Added modular agent skills for strict TypeScript architecture, D3.js v7+ visualization pipelines (`selection.join`, transitions), and browser/Canvas application engineering.

---

## Quick Start

Copy and paste this into your terminal to start the Pi coding agent:

```bash
cd /Users/mac/pi && ./run_agent.sh
```

*The launcher automatically verifies or starts the background MTPLX server with all acceleration flags, verifies port 8000 health, and drops you straight into the interactive agent TUI.*

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

# Run without loading skills (raw baseline)
./run_agent.sh --no-skills
```

### 2. Server Management & Diagnostics

```bash
# Manually start or restart the background MTPLX server
./start_mtplx.sh

# Gracefully stop the MTPLX server
./stop_mtplx.sh

# Run the automated end-to-end test suite (API, Tools, Web Search, Skills)
./test_pi_setup.sh
```

---

## Architecture & Configuration

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
| `MTPLX_MEMORY_LIMIT_BYTES` | `118G` | Allocate up to 118GB unified memory budget |
| `MTPLX_WIRED_LIMIT_BYTES` | `110G` | Metal wired memory ceiling |

---

## Directory Layout

```
/Users/mac/pi/
├── run_agent.sh               # Main interactive TUI launcher
├── start_mtplx.sh             # Background accelerated server daemon
├── stop_mtplx.sh              # Clean process terminator
├── test_pi_setup.sh           # End-to-end verification suite
├── pi                         # Executable Pi CLI wrapper
├── package.json               # Node workspace manifest
├── tsconfig.json              # TypeScript configuration
├── logs/
│   ├── mtplx.log              # Server logs
│   └── mtplx.pid              # Active server PID
└── .pi/
    ├── settings.json          # Agent settings (model, default tools, compaction, thinking)
    ├── models.json            # Model provider definitions (MTPLX endpoint & capabilities)
    ├── sessions/              # Persistent conversation history files
    ├── extensions/
    │   ├── status-bar.ts      # Single-row high-precision Unicode status rail (RAM, CTX, tok/s)
    │   └── web-tools.ts       # web_search & web_fetch extensions
    └── skills/
        ├── typescript-expert/ # TypeScript strict engineering skill
        ├── d3-visualization/  # D3.js v7+ data visualization skill
        └── browser-apps/      # Browser, DOM, Canvas & Web Worker skill
```
