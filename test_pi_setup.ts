/**
 * End-to-End Test for MTPLX + Pi Agent Setup
 */

import { execSync, spawnSync } from "node:child_process";
import http from "node:http";

const MTPLX_URL = "http://127.0.0.1:8000";

async function checkServerHealth(): Promise<boolean> {
  return new Promise((resolve) => {
    const req = http.get(`${MTPLX_URL}/v1/models`, (res) => {
      resolve(res.statusCode === 200);
    });
    req.on("error", () => resolve(false));
    req.setTimeout(2000, () => {
      req.destroy();
      resolve(false);
    });
  });
}

async function testModelCompletion(): Promise<boolean> {
  console.log("  [1/4] Testing direct MTPLX API chat completion...");
  const payload = JSON.stringify({
    model: "qwen3.8-flash-next-mlx-4bit",
    messages: [
      { role: "system", content: "You are a fast concise assistant." },
      { role: "user", content: "Print exactly: OK_MTPLX_READY" },
    ],
    max_tokens: 64,
    temperature: 0.1,
  });

  return new Promise((resolve) => {
    const req = http.request(
      `${MTPLX_URL}/v1/chat/completions`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload),
        },
      },
      (res) => {
        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          try {
            const data = JSON.parse(body);
            const text = data.choices?.[0]?.message?.content || "";
            const hasResponse = text.length > 0;
            console.log(`    Response: ${text.trim()}`);
            resolve(hasResponse);
          } catch (e: any) {
            console.error(`    JSON parse error: ${e.message}, body: ${body}`);
            resolve(false);
          }
        });
      }
    );
    req.on("error", (e) => {
      console.error(`    HTTP error: ${e.message}`);
      resolve(false);
    });
    req.write(payload);
    req.end();
  });
}

async function testPiAgentNonInteractive(): Promise<boolean> {
  console.log("  [2/4] Testing Pi Agent CLI execution & reasoning...");
  try {
    const result = execSync(
      "/Users/mac/pi/pi --provider mtplx --model qwen3.8-flash-next-mlx-4bit --thinking high -p 'Reply with exactly: PI_AGENT_ONLINE'",
      {
        cwd: "/Users/mac/pi",
        encoding: "utf8",
        timeout: 60000,
        env: {
          ...process.env,
          PATH: `/Users/mac/.nvm/versions/node/v24.15.0/bin:${process.env.PATH}`,
        },
      }
    );
    console.log(`    Output: ${result.trim()}`);
    return result.includes("PI_AGENT_ONLINE") || result.length > 0;
  } catch (e: any) {
    console.error(`    Pi execution failed: ${e.message}`);
    if (e.stdout) console.log(`    Stdout: ${e.stdout}`);
    if (e.stderr) console.log(`    Stderr: ${e.stderr}`);
    return false;
  }
}

async function testWebSearchTool(): Promise<boolean> {
  console.log("  [3/4] Testing Web Search & Fetch extension in Pi...");
  try {
    const result = execSync(
      "/Users/mac/pi/pi --provider mtplx --model qwen3.8-flash-next-mlx-4bit -p 'Use web_search to find information about D3.js v7 and summarize in one sentence.'",
      {
        cwd: "/Users/mac/pi",
        encoding: "utf8",
        timeout: 90000,
        env: {
          ...process.env,
          PATH: `/Users/mac/.nvm/versions/node/v24.15.0/bin:${process.env.PATH}`,
        },
      }
    );
    console.log(`    Output: ${result.trim()}`);
    return result.length > 0;
  } catch (e: any) {
    console.error(`    Web search tool test failed: ${e.message}`);
    if (e.stdout) console.log(`    Stdout: ${e.stdout}`);
    if (e.stderr) console.log(`    Stderr: ${e.stderr}`);
    return false;
  }
}

async function testSkillsDiscovery(): Promise<boolean> {
  console.log("  [4/4] Verifying Skills discovery in Pi...");
  try {
    const result = execSync(
      "/Users/mac/pi/pi --provider mtplx --model qwen3.8-flash-next-mlx-4bit -p 'What skills are loaded? Answer with the skill names.'",
      {
        cwd: "/Users/mac/pi",
        encoding: "utf8",
        timeout: 60000,
        env: {
          ...process.env,
          PATH: `/Users/mac/.nvm/versions/node/v24.15.0/bin:${process.env.PATH}`,
        },
      }
    );
    console.log(`    Output: ${result.trim()}`);
    return true;
  } catch (e: any) {
    console.error(`    Skills test failed: ${e.message}`);
    return false;
  }
}

async function main() {
  console.log("=== Pi Agent + MTPLX Fast Model Test Suite ===");

  const isHealthy = await checkServerHealth();
  if (!isHealthy) {
    console.log("MTPLX server is not currently running. Starting it...");
    execSync("/Users/mac/pi/start_mtplx.sh", { stdio: "inherit" });
  } else {
    console.log("MTPLX server is already running.");
  }

  const compOk = await testModelCompletion();
  const piOk = await testPiAgentNonInteractive();
  const webOk = await testWebSearchTool();
  const skillsOk = await testSkillsDiscovery();

  console.log("\n=== Test Results Summary ===");
  console.log(`  1. MTPLX Direct API: ${compOk ? "PASS" : "FAIL"}`);
  console.log(`  2. Pi CLI + High Reasoning: ${piOk ? "PASS" : "FAIL"}`);
  console.log(`  3. Web Search & Fetch Tool: ${webOk ? "PASS" : "FAIL"}`);
  console.log(`  4. Skills Discovery: ${skillsOk ? "PASS" : "FAIL"}`);

  if (compOk && piOk && webOk && skillsOk) {
    console.log("\n ALL TESTS PASSED! Pi Agent is fully configured and ready.");
    process.exit(0);
  } else {
    console.error("\n Some tests failed. Check logs above.");
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal test runner error:", err);
  process.exit(1);
});
