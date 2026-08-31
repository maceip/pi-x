/**
 * Custom Single-Row Status Bar Extension for Pi Agent
 * Live RAM, CTX, decode speed (↯), thermal alerts (🔥THRM), and git branch.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execFile } from "node:child_process";
import * as os from "node:os";

const TOTAL_MEM = os.totalmem() || 128 * 1073741824;
const BLOCKS = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"];
let cachedWired = 0, cachedThrm = "", isPolling = false;

function updateTelemetry() {
  if (isPolling) return;
  isPolling = true;
  execFile("vm_stat", [], { timeout: 1500 }, (_, out) => {
    if (out) { const m = out.match(/Pages wired down:\s+(\d+)\./); if (m) cachedWired = parseInt(m[1], 10) * 16384; }
    execFile("pmset", ["-g", "therm"], { timeout: 1500 }, (_, t) => {
      isPolling = false;
      if (t) {
        const lim = t.match(/CPU_Speed_Limit\s*=\s*([0-9]+)/);
        if (lim && parseInt(lim[1], 10) < 90) { cachedThrm = "🔥THRM"; return; }
        if (/Thermal_Warning_Level\s*=\s*(Moderate|Heavy|Critical)/i.test(t)) { cachedThrm = "🔥HOT"; return; }
      }
      cachedThrm = "";
    });
  });
}
updateTelemetry();

function renderBar(ratio: number, width = 8): string {
  const eighths = Math.round(Math.max(0, Math.min(1, isNaN(ratio) ? 0 : ratio)) * width * 8);
  const full = Math.floor(eighths / 8), rem = eighths % 8;
  return "█".repeat(full) + (rem > 0 ? BLOCKS[rem] : "") + "░".repeat(Math.max(0, width - full - (rem > 0 ? 1 : 0)));
}

const fmtGB = (b: number) => `${(b / 1073741824).toFixed(1)}G`;
const fmtTok = (t: number) => t < 1000 ? `${t}` : `${(t / 1000).toFixed(1)}k`;

export default function statusBarExtension(pi: ExtensionAPI) {
  let isGen = false, tStart = 0, tTok = 0, liveTokS = 0, lastAvgTokS: number | null = null, rerender: (() => void) | null = null;
  const bell = process.env.PI_ENABLE_BELL !== "0", bellThresh = Number(process.env.PI_BELL_THRESHOLD_S || 15);
  const reset = () => { isGen = false; liveTokS = 0; rerender?.(); };

  pi.on("turn_start", async () => { isGen = true; tStart = Date.now(); tTok = 0; liveTokS = 0; rerender?.(); });
  pi.on("message_update", async (e) => {
    if (!isGen) { isGen = true; if (!tStart) tStart = Date.now(); }
    const ev = e.assistantMessageEvent;
    if (ev && (ev.type === "text_delta" || ev.type === "thinking_delta")) {
      tTok += Math.max(1, Math.round((ev.delta?.length || 0) / 3.8));
      const s = (Date.now() - tStart) / 1000;
      if (s > 0.1) liveTokS = tTok / s;
      rerender?.();
    }
  });
  pi.on("message_end", async (e) => {
    if (e.message.role === "assistant") {
      const act = (e.message as AssistantMessage).usage?.output || tTok;
      const s = (Date.now() - tStart) / 1000;
      if (s > 0.1 && act > 0) lastAvgTokS = act / s;
      else if (liveTokS > 0) lastAvgTokS = liveTokS;
      if (bell && s >= bellThresh) process.stderr.write("\x07");
    }
    reset();
  });
  pi.on("turn_end", async () => reset());

  pi.on("session_start", async (_, ctx) => {
    ctx.ui.setFooter((tui, theme, footer) => {
      rerender = () => tui.requestRender();
      let unsub = () => {};
      try { if (typeof footer?.onBranchChange === "function") unsub = footer.onBranchChange(() => tui.requestRender()); } catch {}
      const timer = setInterval(() => { updateTelemetry(); tui.requestRender(); }, 2500);

      return {
        dispose() { unsub(); clearInterval(timer); rerender = null; },
        invalidate() {},
        render(w: number): string[] {
          if (!w || w < 25) return [truncateToWidth(theme.bold("pi-x"), Math.max(1, w))];

          let pTok = 0, cTok = 0;
          try {
            const branch = ctx.sessionManager?.getBranch?.() || [];
            for (let i = branch.length - 1; i >= 0; i--) {
              if (branch[i].type === "message" && branch[i].message.role === "assistant") {
                const u = (branch[i].message as AssistantMessage).usage;
                if (u) { pTok = u.input || 0; cTok = u.output || 0; break; }
              }
            }
          } catch {}

          const curTok = pTok + cTok + (isGen ? tTok : 0);
          const maxCtx = ctx.model?.contextWindow || 65536;
          const cRatio = curTok / maxCtx, cPct = Math.round(cRatio * 100);
          const mRatio = cachedWired / TOTAL_MEM, mPct = Math.round(mRatio * 100);
          const color = (r: number, s: string) => r >= 0.88 ? theme.fg("error", s) : r >= 0.7 ? theme.fg("warning", s) : theme.fg("accent", s);

          const isCompact = w < 95, isUltra = w < 75, isTiny = w < 50;
          const barW = isTiny ? 3 : isUltra ? 4 : isCompact ? 6 : 8;
          const thrm = cachedThrm ? " " + theme.fg("warning", cachedThrm) : "";

          const ramVal = isTiny ? `${mPct}%` : isUltra ? `${mPct}%${thrm}` : isCompact ? `${Math.round(cachedWired / 1073741824)}G (${mPct}%)${thrm}` : `${fmtGB(cachedWired)}/${fmtGB(TOTAL_MEM)} (${mPct}%)${thrm}`;
          const ram = theme.bold("RAM ") + color(mRatio, renderBar(mRatio, barW)) + " " + ramVal;

          const ctxVal = isTiny ? `${cPct}%` : isUltra ? `${cPct}%` : isCompact ? `${fmtTok(curTok)} (${cPct}%)` : `${fmtTok(curTok)}/${fmtTok(maxCtx)} (${cPct}%)`;
          const ctxt = theme.bold("CTX ") + color(cRatio, renderBar(cRatio, barW)) + " " + ctxVal;

          const spd = isGen ? liveTokS : (lastAvgTokS || 0);
          const spdStr = isGen
            ? theme.bold(theme.fg("accent", `↯ ${spd > 0 ? spd.toFixed(1) : "--.-"} t/s`))
            : spd > 0 ? theme.bold(`↯ ${spd.toFixed(1)} t/s`) : theme.fg("dim", `↯ --.- t/s`);

          let git = "";
          try { const b = footer?.getGitBranch?.(); if (!isCompact && b) git = theme.fg("dim", ` (${b})`); } catch {}

          let mdl = isCompact ? "Flash-Next" : "Flash-Next (65k)";
          const id = ctx.model?.id || "";
          if (id && !id.includes("flash-next") && !id.includes("qwen")) mdl = id.length > 14 ? `${id.slice(0, 12)}..` : id;
          const mdlStr = isUltra ? "" : theme.bold(mdl) + git;
          const sep = theme.fg("dim", " │ ");

          const line = isTiny ? `${ram}${sep}${ctxt}` : mdlStr ? `${ram}${sep}${ctxt}${sep}${spdStr}${sep}${mdlStr}` : `${ram}${sep}${ctxt}${sep}${spdStr}`;
          const vW = visibleWidth(line);
          return [truncateToWidth(vW < w ? line + " ".repeat(w - vW) : line, w)];
        },
      };
    });
  });
}
