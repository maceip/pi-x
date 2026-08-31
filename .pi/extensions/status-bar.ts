/**
 * Custom Single-Row Status Bar Extension for Pi Agent
 * Renders live RAM, CTX, decode tok/s (↯), thermal alerts (🔥THRM), and git branch.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execFile } from "node:child_process";
import * as os from "node:os";

const TOTAL_MEM_BYTES = os.totalmem() || 128 * 1024 * 1024 * 1024;
const PAGE_SIZE_BYTES = 16384;
const FRACTIONAL_BLOCKS = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"];

let cachedWiredBytes = 0;
let cachedThermalWarning = "";
let isPollingTelemetry = false;

function updateTelemetryAsync() {
  if (isPollingTelemetry) return;
  isPollingTelemetry = true;

  execFile("vm_stat", [], { timeout: 1500 }, (_, stdout) => {
    if (stdout) {
      const match = stdout.match(/Pages wired down:\s+(\d+)\./);
      if (match) cachedWiredBytes = parseInt(match[1], 10) * PAGE_SIZE_BYTES;
    }
    execFile("pmset", ["-g", "therm"], { timeout: 1500 }, (_, tStdout) => {
      isPollingTelemetry = false;
      if (tStdout) {
        const limitMatch = tStdout.match(/CPU_Speed_Limit\s*=\s*([0-9]+)/);
        if (limitMatch && parseInt(limitMatch[1], 10) < 90) {
          cachedThermalWarning = "🔥THRM";
          return;
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
updateTelemetryAsync();

function renderDetailedBar(ratio: number, width = 8, emptyChar = "░"): string {
  const totalEighths = Math.round(Math.max(0, Math.min(1, isNaN(ratio) ? 0 : ratio)) * width * 8);
  const fullBlocks = Math.floor(totalEighths / 8);
  const rem = totalEighths % 8;
  const bar = "█".repeat(fullBlocks) + (rem > 0 ? FRACTIONAL_BLOCKS[rem] : "");
  return bar + emptyChar.repeat(Math.max(0, width - fullBlocks - (rem > 0 ? 1 : 0)));
}

const fmtGB = (bytes: number) => `${(bytes / 1073741824).toFixed(1)}G`;
const fmtTokens = (tokens: number) => tokens < 1000 ? `${tokens}` : `${(tokens / 1000).toFixed(1)}k`;

export default function statusBarExtension(pi: ExtensionAPI) {
  let isGenerating = false, turnStartTime = 0, turnTokensGenerated = 0, currentLiveTokS = 0;
  let lastTurnAvgTokS: number | null = null, requestRenderFn: (() => void) | null = null;
  const enableBell = process.env.PI_ENABLE_BELL !== "0";
  const bellThresholdS = Number(process.env.PI_BELL_THRESHOLD_S || 15);

  const resetGen = () => { isGenerating = false; currentLiveTokS = 0; requestRenderFn?.(); };

  pi.on("turn_start", async () => {
    isGenerating = true; turnStartTime = Date.now(); turnTokensGenerated = 0; currentLiveTokS = 0;
    requestRenderFn?.();
  });

  pi.on("message_update", async (event) => {
    if (!isGenerating) { isGenerating = true; if (turnStartTime === 0) turnStartTime = Date.now(); }
    const evt = event.assistantMessageEvent;
    if (evt && (evt.type === "text_delta" || evt.type === "thinking_delta")) {
      turnTokensGenerated += Math.max(1, Math.round((evt.delta?.length || 0) / 3.8));
      const elapsedS = (Date.now() - turnStartTime) / 1000;
      if (elapsedS > 0.1) currentLiveTokS = turnTokensGenerated / elapsedS;
      requestRenderFn?.();
    }
  });

  pi.on("message_end", async (event) => {
    if (event.message.role === "assistant") {
      const actualTokens = (event.message as AssistantMessage).usage?.output || turnTokensGenerated;
      const elapsedS = (Date.now() - turnStartTime) / 1000;
      if (elapsedS > 0.1 && actualTokens > 0) lastTurnAvgTokS = actualTokens / elapsedS;
      else if (currentLiveTokS > 0) lastTurnAvgTokS = currentLiveTokS;
      if (enableBell && elapsedS >= bellThresholdS) process.stderr.write("\x07");
    }
    resetGen();
  });

  pi.on("turn_end", async () => resetGen());

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRenderFn = () => tui.requestRender();
      const unsub = footerData.onBranchChange(() => tui.requestRender());
      const timer = setInterval(() => { updateTelemetryAsync(); tui.requestRender(); }, 2500);

      return {
        dispose() { unsub(); clearInterval(timer); requestRenderFn = null; },
        invalidate() {},
        render(width: number): string[] {
          let promptTokens = 0, completionTokens = 0;
          const branch = ctx.sessionManager.getBranch();
          for (let i = branch.length - 1; i >= 0; i--) {
            if (branch[i].type === "message" && branch[i].message.role === "assistant") {
              const u = (branch[i].message as AssistantMessage).usage;
              if (u) { promptTokens = u.input || 0; completionTokens = u.output || 0; break; }
            }
          }

          const currentTokens = promptTokens + completionTokens + (isGenerating ? turnTokensGenerated : 0);
          const maxContext = ctx.model?.contextWindow || 65536;
          const ctxRatio = currentTokens / maxContext, ctxPct = Math.round(ctxRatio * 100);
          const memRatio = cachedWiredBytes / TOTAL_MEM_BYTES, memPct = Math.round(memRatio * 100);

          const getColored = (r: number, s: string) => r >= 0.88 ? theme.fg("error", s) : r >= 0.7 ? theme.fg("warning", s) : theme.fg("accent", s);

          const isCompact = width < 95, isUltra = width < 75;
          const barW = isUltra ? 4 : isCompact ? 6 : 8;

          const thrm = cachedThermalWarning ? " " + theme.fg("warning", cachedThermalWarning) : "";
          const ramDetails = isUltra ? `${memPct}%` : isCompact ? `${Math.round(cachedWiredBytes / 1073741824)}G (${memPct}%)${thrm}` : `${fmtGB(cachedWiredBytes)}/${fmtGB(TOTAL_MEM_BYTES)} (${memPct}%)${thrm}`;
          const ramText = theme.bold("RAM ") + getColored(memRatio, renderDetailedBar(memRatio, barW)) + " " + ramDetails;

          const ctxDetails = isUltra ? `${ctxPct}%` : isCompact ? `${fmtTokens(currentTokens)} (${ctxPct}%)` : `${fmtTokens(currentTokens)}/${fmtTokens(maxContext)} (${ctxPct}%)`;
          const ctxText = theme.bold("CTX ") + getColored(ctxRatio, renderDetailedBar(ctxRatio, barW)) + " " + ctxDetails;

          const speedStr = isGenerating
            ? theme.bold(theme.fg("accent", `↯ ${currentLiveTokS > 0 ? currentLiveTokS.toFixed(1) : "--.-"} t/s`))
            : lastTurnAvgTokS !== null && lastTurnAvgTokS > 0
              ? theme.bold(`↯ ${lastTurnAvgTokS.toFixed(1)} t/s`)
              : theme.fg("dim", `↯ --.- t/s`);

          const gitBranch = footerData.getGitBranch();
          const gitStr = !isCompact && gitBranch ? theme.fg("dim", ` (${gitBranch})`) : "";
          let modelLabel = isCompact ? "Flash-Next" : "Flash-Next (65k)";
          const rawId = ctx.model?.id || "";
          if (rawId && !rawId.includes("flash-next") && !rawId.includes("qwen")) {
            modelLabel = rawId.length > 14 ? `${rawId.slice(0, 12)}..` : rawId;
          }
          const modelStr = isUltra ? "" : theme.bold(modelLabel) + gitStr;
          const sep = theme.fg("dim", " │ ");
          const fullLine = modelStr ? `${ramText}${sep}${ctxText}${sep}${speedStr}${sep}${modelStr}` : `${ramText}${sep}${ctxText}${sep}${speedStr}`;

          const vW = visibleWidth(fullLine);
          return [truncateToWidth(vW < width ? fullLine + " ".repeat(width - vW) : fullLine, width)];
        },
      };
    });
  });
}
