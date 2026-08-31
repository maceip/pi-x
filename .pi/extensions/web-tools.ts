/**
 * Web Tools Extension for Pi Agent
 * Registers web_search (DuckDuckGo keyless + Wikipedia fallback) & web_fetch (HTML to Markdown).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const decode = (s: string) => s.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-z]+);/gi, (m, c) => {
  if (c.startsWith("#x")) return String.fromCharCode(parseInt(c.slice(2), 16));
  if (c.startsWith("#")) return String.fromCharCode(parseInt(c.slice(1), 10));
  const map: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
  return map[c.toLowerCase()] || m;
});

function htmlToMarkdown(html: string): string {
  const clean = html
    .replace(/<(head|script|style|svg|noscript|iframe|nav|footer)[^>]*>[\s\S]*?<\/\1>/gi, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/gi, (_, lvl, t) => `\n${"#".repeat(Number(lvl))} ${t}\n`)
    .replace(/<pre[^>]*><code[^>]*>([\s\S]*?)<\/code><\/pre>/gi, "\n```\n$1\n```\n")
    .replace(/<code[^>]*>([\s\S]*?)<\/code>/gi, "`$1`")
    .replace(/<a\s+[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, "[$2]($1)")
    .replace(/<li[^>]*>([\s\S]*?)<\/li>/gi, "\n- $1")
    .replace(/<p[^>]*>([\s\S]*?)<\/p>/gi, "\n\n$1\n\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<hr\s*\/?>/gi, "\n---\n")
    .replace(/<[^>]+>/g, " ");

  return decode(clean).split("\n").map(l => l.trim()).filter((l, i, arr) => l !== "" || arr[i - 1] !== "").join("\n").trim();
}

interface SearchResult { title: string; url: string; snippet: string; }

async function searchDuckDuckGo(query: string, limit: number, signal?: AbortSignal): Promise<SearchResult[]> {
  const sig = signal ? AbortSignal.any([signal, AbortSignal.timeout(10000)]) : AbortSignal.timeout(10000);
  const resp = await fetch(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`, {
    headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/126.0.0.0 Safari/537.36" },
    signal: sig,
  });
  if (resp.status === 202 || resp.status === 403 || resp.status === 429) throw new Error("DDG rate limited");
  if (!resp.ok) throw new Error(`DDG HTTP ${resp.status}`);

  const html = await resp.text(), results: SearchResult[] = [];
  for (const block of html.split(/<div\s+class="[^"]*result\s+results_links[^"]*"[^>]*>/i).slice(1)) {
    if (results.length >= limit) break;
    const h = block.match(/<a\s+class="result__title"[^>]*>([\s\S]*?)<\/a>/i) || block.match(/<h2[^>]*class="result__title"[^>]*>[\s\S]*?<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    const s = block.match(/<a\s+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/i) || block.match(/<div\s+class="result__snippet"[^>]*>([\s\S]*?)<\/div>/i);
    let url = h ? h[1] : "";
    if (url.includes("uddg=")) url = decodeURIComponent(url.match(/uddg=([^&]+)/)?.[1] || url);
    else if (url.startsWith("//")) url = "https:" + url;
    const title = decode((h ? (h[2] || h[1]) : "").replace(/<[^>]+>/g, "").trim());
    const snippet = decode((s ? s[1] : "").replace(/<[^>]+>/g, "").trim());
    if (title && url) results.push({ title, url, snippet });
  }
  return results;
}

async function searchWikipediaFallback(query: string, limit: number, signal?: AbortSignal): Promise<SearchResult[]> {
  const resp = await fetch(`https://en.wikipedia.org/w/api.php?action=opensearch&search=${encodeURIComponent(query)}&limit=${limit}&format=json`, { signal: signal || AbortSignal.timeout(8000) });
  if (!resp.ok) return [];
  const data = (await resp.json()) as [string, string[], string[], string[]];
  return (data[1] || []).map((t, i) => ({ title: t, snippet: data[2]?.[i] || "", url: data[3]?.[i] || "" }));
}

export default function webToolsExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description: "Search the web for up-to-date documentation, API signatures, libraries, or tutorials.",
    parameters: Type.Object({
      query: Type.String({ description: "Search terms or question" }),
      limit: Type.Optional(Type.Number({ description: "Max results (default: 6, max: 15)" })),
    }),
    async execute(_id, params, signal) {
      const q = params.query.trim(), limit = Math.min(Math.max(params.limit || 6, 1), 15);
      if (!q) return { content: [{ type: "text", text: "Error: Query cannot be empty." }] };
      let results: SearchResult[] = [], provider = "DuckDuckGo";
      try { results = await searchDuckDuckGo(q, limit, signal); }
      catch (err: any) {
        try { results = await searchWikipediaFallback(q, limit, signal); provider = "Wikipedia Fallback"; } catch {}
        if (!results.length) return { content: [{ type: "text", text: `Search unavailable (${err.message}). Proceed using internal model knowledge or specific URLs with web_fetch.` }] };
      }
      if (!results.length) return { content: [{ type: "text", text: `No results found for "${q}".` }] };
      const text = `### Web Search Results (${provider}) for "${q}"\n\n` + results.map((r, i) => `**${i + 1}. [${r.title}](${r.url})**\n${r.snippet}\n`).join("\n");
      return { content: [{ type: "text", text }] };
    },
  });

  pi.registerTool({
    name: "web_fetch",
    label: "Web Fetch",
    description: "Fetch and extract clean Markdown content from a webpage URL.",
    parameters: Type.Object({
      url: Type.String({ description: "Full URL to fetch (https://...)" }),
      max_chars: Type.Optional(Type.Number({ description: "Max characters to return (default: 20000)" })),
    }),
    async execute(_id, params, signal) {
      const u = params.url.trim(), max = params.max_chars || 20000;
      if (!/^https?:\/\//i.test(u)) return { content: [{ type: "text", text: "Error: URL must begin with http:// or https://" }] };
      try {
        const sig = signal ? AbortSignal.any([signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000);
        const resp = await fetch(u, { headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/126.0.0.0 Safari/537.36" }, signal: sig });
        if (!resp.ok) return { content: [{ type: "text", text: `HTTP error ${resp.status}: ${resp.statusText}` }] };
        const md = htmlToMarkdown(await resp.text());
        return { content: [{ type: "text", text: `### Content from ${u}\n\n${md.length > max ? md.slice(0, max) + "\n\n*(Truncated...)*" : md}` }] };
      } catch (err: any) { return { content: [{ type: "text", text: `Fetch failed: ${err.message}` }] }; }
    },
  });
}
