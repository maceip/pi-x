/**
 * Custom Single-Row Status Bar Extension for Pi Agent
 *
 * Features:
 * - Clean high-resolution sub-character Unicode progress bars (8th-block steps: ▏▎▍▌▋▊▉█)
 * - macOS System Wired Memory / Total Memory (accurate scaling & color coding)
 * - Context Length Used / Total Context Window (65,536 tokens) with live streaming updates
 * - Live token decode speed (↯ tok/s) with on-tick updates during generation & turn averages
 * - Background thermal pressure polling & warning indicator (🔥THRM)
 * - Long-turn completion terminal bell alert (>15s by default, configurable)
 * - Model ID, active Git branch, and responsive terminal width compaction
 * - Strictly single-row height
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execFile } from "node:child_process";
import * as os from "node:os";

// System total memory & page size
let TOTAL_MEM_BYTES = os.totalmem() || 128 * 1024 * 1024 * 1024;
let PAGE_SIZE_BYTES = 16384;

// Track wired memory and thermal status asynchronously in background
let cachedWiredBytes = 0;
let cachedThermalWarning = "";
let isPollingTelemetry = false;

function updateTelemetryAsync() {
  if (isPollingTelemetry) return;
  isPollingTelemetry = true;

  // 1. Poll wired memory pages
  execFile("vm_stat", [], { timeout: 1500 }, (err, stdout) => {
    if (!err && stdout) {
      const match = stdout.match(/Pages wired down:\s+(\d+)\./);
      if (match) {
        const pages = parseInt(match[1], 10);
        cachedWiredBytes = pages * PAGE_SIZE_BYTES;
      }
    }

    // 2. Poll macOS thermal state
    execFile("pmset", ["-g", "therm"], { timeout: 1500 }, (tErr, tStdout) => {
      isPollingTelemetry = false;
      if (!tErr && tStdout) {
        if (/CPU_Speed_Limit\s*=\s*([0-9]+)/.test(tStdout)) {
          const limit = parseInt(tStdout.match(/CPU_Speed_Limit\s*=\s*([0-9]+)/)![1], 10);
          if (limit < 90) {
            cachedThermalWarning = "🔥THRM";
            return;
          }
        }
        if (/Thermal_Warning_Level\s*=\s*(Moderate|Heavy|Critical)/i.test(tStdout)) {
          cachedThermalWarning = "🔥HOT";
          return;
        }
      }
      cachedThermalWarning = "";
    });
  });
}

// Initial async telemetry sample
updateTelemetryAsync();

const FRACTIONAL_BLOCKS = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"];

/**
 * Render a high-precision Unicode shaded bar with 8 sub-character steps per cell.
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
  // Live Decode Speed & Turn Duration Tracking State
  let isGenerating = false;
  let turnStartTime = 0;
  let turnTokensGenerated = 0;
  let currentLiveTokS = 0;
  let lastTurnAvgTokS: number | null = null;
  let requestRenderFn: (() => void) | null = null;

  // Bell Alert Settings
  const enableBell = process.env.PI_ENABLE_BELL !== "0";
  const bellThresholdS = Number(process.env.PI_BELL_THRESHOLD_S || 15);

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

      // Terminal bell notification for long turns (>15s)
      if (enableBell && elapsedS >= bellThresholdS) {
        process.stderr.write("\x07");
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

      // Periodic timer for live telemetry tracking (every 2.5s, non-blocking)
      const intervalTimer = setInterval(() => {
        updateTelemetryAsync();
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

          const currentTokens = promptTokens + completionTokens + (isGenerating ? turnTokensGenerated : 0);
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

          // Dynamic sizing based on terminal column width
          const isCompact = width < 95;
          const isUltraCompact = width < 75;
          const barWidth = isUltraCompact ? 4 : isCompact ? 6 : 8;

          // 3. Format RAM Segment (with optional thermal warning tag)
          const ramBar = getBarColored(memRatio, renderDetailedBar(memRatio, barWidth, "░"));
          const thrmTag = cachedThermalWarning ? " " + theme.fg("warning", cachedThermalWarning) : "";
          const ramDetails = isUltraCompact
            ? `${memPercent}%`
            : isCompact
              ? `${Math.round(wiredBytes / (1024 * 1024 * 1024))}G (${memPercent}%)${thrmTag}`
              : `${formatBytesGB(wiredBytes)}/${formatBytesGB(TOTAL_MEM_BYTES)} (${memPercent}%)${thrmTag}`;
          const ramText = theme.bold("RAM ") + ramBar + " " + ramDetails;

          // 4. Format CTX Segment
          const ctxBar = getBarColored(ctxRatio, renderDetailedBar(ctxRatio, barWidth, "░"));
          const ctxDetails = isUltraCompact
            ? `${ctxPercent}%`
            : isCompact
              ? `${formatTokens(currentTokens)} (${ctxPercent}%)`
              : `${formatTokens(currentTokens)}/${formatTokens(maxContext)} (${ctxPercent}%)`;
          const ctxText = theme.bold("CTX ") + ctxBar + " " + ctxDetails;

          // 5. Format Live / Average Decode Speed Segment using ↯
          let speedStr = "";
          if (isGenerating) {
            const liveVal = currentLiveTokS > 0 ? currentLiveTokS.toFixed(1) : "--.-";
            speedStr = theme.bold(theme.fg("accent", `↯ ${liveVal} t/s`));
          } else if (lastTurnAvgTokS !== null && lastTurnAvgTokS > 0) {
            speedStr = theme.bold(`↯ ${lastTurnAvgTokS.toFixed(1)} t/s`);
          } else {
            speedStr = theme.fg("dim", `↯ --.- t/s`);
          }

          // 6. Format Model & Git Segment (Responsive: adapts to remaining width)
          const gitBranch = footerData.getGitBranch();
          const gitStr = !isCompact && gitBranch ? theme.fg("dim", ` (${gitBranch})`) : "";
          const rawModelId = ctx.model?.id || "";
          let modelLabel = isCompact ? "Flash-Next" : "Flash-Next (65k)";
          if (rawModelId && !rawModelId.includes("flash-next") && !rawModelId.includes("qwen")) {
            modelLabel = rawModelId.length > 14 ? `${rawModelId.slice(0, 12)}..` : rawModelId;
          }
          const modelStr = isUltraCompact ? "" : theme.bold(modelLabel) + gitStr;

          const sep = theme.fg("dim", " │ ");

          // Compose Single Line
          const fullLine = modelStr
            ? `${ramText}${sep}${ctxText}${sep}${speedStr}${sep}${modelStr}`
            : `${ramText}${sep}${ctxText}${sep}${speedStr}`;

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
