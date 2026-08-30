/**
 * Custom Single-Row Status Bar Extension for Pi Agent
 *
 * Features:
 * - Clean high-resolution sub-character Unicode progress bars (8th-block steps: ▏▎▍▌▋▊▉█)
 * - No outline brackets / border enclosures for a sleek, modern, uncluttered look
 * - macOS System Wired Memory / Total Memory (accurate scaling & color coding)
 * - Context Length Used / Total Context Window (65,536 tokens)
 * - Live token decode speed (tok/s) with on-tick updates during generation & turn averages
 * - Model ID & active Git branch
 * - Strictly single-row height
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execFile } from "node:child_process";
import * as os from "node:os";

// System total memory
let TOTAL_MEM_BYTES = os.totalmem() || 128 * 1024 * 1024 * 1024;
let PAGE_SIZE_BYTES = 16384;

// Track wired memory asynchronously in background without blocking render loop
let cachedWiredBytes = 0;
let isPollingMemory = false;

function updateWiredMemoryAsync() {
  if (isPollingMemory) return;
  isPollingMemory = true;

  execFile("vm_stat", [], { timeout: 1500 }, (err, stdout) => {
    isPollingMemory = false;
    if (!err && stdout) {
      const match = stdout.match(/Pages wired down:\s+(\d+)\./);
      if (match) {
        const pages = parseInt(match[1], 10);
        cachedWiredBytes = pages * PAGE_SIZE_BYTES;
      }
    }
  });
}

// Initial async sample
updateWiredMemoryAsync();

const FRACTIONAL_BLOCKS = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"];

/**
 * Render a high-precision Unicode shaded bar with 8 sub-character steps per cell.
 * Width of 8 cells provides 64 distinct resolution steps.
 */
function renderDetailedBar(ratio: number, width = 8, emptyChar = "░"): string {
  const clamped = Math.max(0, Math.min(1, isNaN(ratio) ? 0 : ratio));
  const totalEighths = Math.round(clamped * width * 8);
  const fullBlocks = Math.floor(totalEighths / 8);
  const remainder = totalEighths % 8;

  let bar = "█".repeat(fullBlocks);
  if (remainder > 0) {
    bar += FRACTIONAL_BLOCKS[remainder];
  }
  const emptyCount = width - fullBlocks - (remainder > 0 ? 1 : 0);
  if (emptyCount > 0) {
    bar += emptyChar.repeat(emptyCount);
  }
  return bar;
}

function formatBytesGB(bytes: number): string {
  const gb = bytes / (1024 * 1024 * 1024);
  return `${gb.toFixed(1)}G`;
}

function formatTokens(tokens: number): string {
  if (tokens < 1000) return `${tokens}`;
  return `${(tokens / 1000).toFixed(1)}k`;
}

export default function statusBarExtension(pi: ExtensionAPI) {
  // Live Decode Speed Tracking State
  let isGenerating = false;
  let turnStartTime = 0;
  let turnTokensGenerated = 0;
  let currentLiveTokS = 0;
  let lastTurnAvgTokS: number | null = null;
  let requestRenderFn: (() => void) | null = null;

  pi.on("turn_start", async () => {
    isGenerating = true;
    turnStartTime = Date.now();
    turnTokensGenerated = 0;
    currentLiveTokS = 0;
    if (requestRenderFn) requestRenderFn();
  });

  pi.on("message_update", async (event) => {
    if (!isGenerating) {
      isGenerating = true;
      if (turnStartTime === 0) turnStartTime = Date.now();
    }

    const evt = event.assistantMessageEvent;
    if (evt) {
      if (evt.type === "text_delta" || evt.type === "thinking_delta") {
        const deltaChars = evt.delta?.length || 0;
        const estTokens = Math.max(1, Math.round(deltaChars / 3.8));
        turnTokensGenerated += estTokens;

        const elapsedS = (Date.now() - turnStartTime) / 1000;
        if (elapsedS > 0.1) {
          currentLiveTokS = turnTokensGenerated / elapsedS;
        }
        if (requestRenderFn) requestRenderFn();
      }
    }
  });

  pi.on("message_end", async (event) => {
    if (event.message.role === "assistant") {
      const m = event.message as AssistantMessage;
      const actualTokens = m.usage?.output || turnTokensGenerated;
      const elapsedS = (Date.now() - turnStartTime) / 1000;
      if (elapsedS > 0.1 && actualTokens > 0) {
        lastTurnAvgTokS = actualTokens / elapsedS;
      } else if (currentLiveTokS > 0) {
        lastTurnAvgTokS = currentLiveTokS;
      }
    }
    isGenerating = false;
    currentLiveTokS = 0;
    if (requestRenderFn) requestRenderFn();
  });

  pi.on("turn_end", async () => {
    isGenerating = false;
    currentLiveTokS = 0;
    if (requestRenderFn) requestRenderFn();
  });

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRenderFn = () => tui.requestRender();
      const unsubBranch = footerData.onBranchChange(() => tui.requestRender());

      // Periodic timer for live memory tracking (every 2.5s, non-blocking)
      const intervalTimer = setInterval(() => {
        updateWiredMemoryAsync();
        tui.requestRender();
      }, 2500);

      return {
        dispose() {
          unsubBranch();
          clearInterval(intervalTimer);
          requestRenderFn = null;
        },
        invalidate() {},
        render(width: number): string[] {
          // 1. Context Usage
          let promptTokens = 0;
          let completionTokens = 0;

          const branch = ctx.sessionManager.getBranch();
          for (let i = branch.length - 1; i >= 0; i--) {
            const entry = branch[i];
            if (entry.type === "message" && entry.message.role === "assistant") {
              const m = entry.message as AssistantMessage;
              if (m.usage) {
                promptTokens = m.usage.input || 0;
                completionTokens = m.usage.output || 0;
                break;
              }
            }
          }

          const currentTokens = promptTokens + completionTokens;
          const maxContext = ctx.model?.contextWindow || 65536;
          const ctxRatio = currentTokens / maxContext;
          const ctxPercent = Math.round(ctxRatio * 100);

          // 2. Wired Memory Usage (read from asynchronous cache)
          const wiredBytes = cachedWiredBytes;
          const memRatio = wiredBytes / TOTAL_MEM_BYTES;
          const memPercent = Math.round(memRatio * 100);

          // Color helper for progress bars
          const getBarColored = (ratio: number, barStr: string) => {
            if (ratio >= 0.88) return theme.fg("error", barStr);
            if (ratio >= 0.70) return theme.fg("warning", barStr);
            return theme.fg("accent", barStr);
          };

          // 3. Format RAM Segment (High contrast, bold label)
          const ramBar = getBarColored(memRatio, renderDetailedBar(memRatio, 8, "░"));
          const ramText = theme.bold("RAM ") + ramBar + " " + `${formatBytesGB(wiredBytes)}/${formatBytesGB(TOTAL_MEM_BYTES)} (${memPercent}%)`;

          // 4. Format CTX Segment (High contrast, bold label)
          const ctxBar = getBarColored(ctxRatio, renderDetailedBar(ctxRatio, 8, "░"));
          const ctxText = theme.bold("CTX ") + ctxBar + " " + `${formatTokens(currentTokens)}/${formatTokens(maxContext)} (${ctxPercent}%)`;

          // 5. Format Live / Average Decode Speed Segment using candidate #2 (↯)
          let speedStr = "";
          if (isGenerating) {
            const liveVal = currentLiveTokS > 0 ? currentLiveTokS.toFixed(1) : "--.-";
            speedStr = theme.bold(theme.fg("accent", `↯ ${liveVal} tok/s`));
          } else if (lastTurnAvgTokS !== null && lastTurnAvgTokS > 0) {
            speedStr = theme.bold(`↯ ${lastTurnAvgTokS.toFixed(1)} tok/s`);
          } else {
            speedStr = theme.fg("dim", `↯ --.- tok/s`);
          }

          // 6. Format Model & Git Segment (Concise, no overflow/truncation)
          const gitBranch = footerData.getGitBranch();
          const gitStr = gitBranch ? theme.fg("dim", ` (${gitBranch})`) : "";
          const rawModelId = ctx.model?.id || "";
          let modelLabel = "Flash-Next (65k)";
          if (rawModelId && !rawModelId.includes("flash-next") && !rawModelId.includes("qwen")) {
            modelLabel = rawModelId.length > 18 ? `${rawModelId.slice(0, 16)}..` : rawModelId;
          }
          const modelStr = theme.bold(modelLabel) + gitStr;

          const sep = theme.fg("dim", " │ ");

          // Compose Single Line
          const fullLine = `${ramText}${sep}${ctxText}${sep}${speedStr}${sep}${modelStr}`;

          // Pad or truncate to exact width, guaranteed 1 row height
          const vWidth = visibleWidth(fullLine);
          if (vWidth < width) {
            const pad = " ".repeat(width - vWidth);
            return [truncateToWidth(fullLine + pad, width)];
          }

          return [truncateToWidth(fullLine, width)];
        },
      };
    });
  });
}
