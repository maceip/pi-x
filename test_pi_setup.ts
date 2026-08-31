/**
 * End-to-End Test Suite for MTPLX + Pi Agent Setup
 */

import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PI_BIN = path.join(ROOT, "pi");
const PI_MODEL = process.env.PI_MODEL || "mtplx-flash-next-optimized-speed";
const MTPLX_URL = process.env.MTPLX_BASE_URL || "http://127.0.0.1:8000";

async function isHealthy(): Promise<boolean> {
  try { return (await fetch(`${MTPLX_URL}/v1/models`, { signal: AbortSignal.timeout(2000) })).ok; } catch { return false; }
}

async function testModelCompletion(): Promise<boolean> {
  console.log("  [1/4] Testing direct MTPLX API chat completion...");
  try {
    const res = await fetch(`${MTPLX_URL}/v1/chat/completions`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: process.env.MTPLX_SERVED_MODEL || PI_MODEL,
        messages: [{ role: "system", content: "You are a concise assistant." }, { role: "user", content: "Print exactly: OK_MTPLX_READY" }],
        max_tokens: 64, temperature: 0.1,
      }),
      signal: AbortSignal.timeout(15000),
    });
    const data = (await res.json()) as any;
    const text = data.choices?.[0]?.message?.content || "";
    console.log(`    Response: ${text.trim()}`);
    return text.length > 0;
  } catch (e: any) { console.error(`    Direct API error: ${e.message}`); return false; }
}

function runPi(label: string, step: number, args: string, timeoutMs = 60000): boolean {
  console.log(`  [${step}/4] ${label}...`);
  try {
    const out = execSync(`${PI_BIN} --provider mtplx --model ${PI_MODEL} ${args}`, { cwd: ROOT, encoding: "utf8", timeout: timeoutMs, env: { ...process.env } }).trim();
    console.log(`    Output: ${out}`);
    return out.length > 0;
  } catch (e: any) { console.error(`    Test failed: ${e.message}`); return false; }
}

async function main() {
  console.log("=== Pi Agent + MTPLX Fast Model Test Suite ===");
  if (!(await isHealthy())) {
    console.log("MTPLX server is not currently running. Starting it...");
    execSync(path.join(ROOT, "start_mtplx.sh"), { stdio: "inherit", cwd: ROOT });
  } else { console.log("MTPLX server is already running."); }

  const results = [
    await testModelCompletion(),
    runPi("Testing Pi Agent CLI execution & reasoning", 2, "--thinking high -p 'Reply with exactly: PI_AGENT_ONLINE'"),
    runPi("Testing Web Search & Fetch extension in Pi", 3, "-p 'Use web_search to find information about D3.js v7 and summarize in one sentence.'", 90000),
    runPi("Verifying Skills discovery in Pi", 4, "-p 'What skills are loaded? Answer with the skill names.'"),
  ];

  const labels = ["MTPLX Direct API", "Pi CLI + High Reasoning", "Web Search & Fetch Tool", "Skills Discovery"];
  console.log("\n=== Test Results Summary ===");
  labels.forEach((l, i) => console.log(`  ${i + 1}. ${l}: ${results[i] ? "PASS" : "FAIL"}`));
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch(e => { console.error("Fatal test runner error:", e); process.exit(1); });
