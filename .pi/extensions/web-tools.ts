/**
 * Web Tools Extension for Pi Agent
 * Registers web_search (DuckDuckGo keyless, Tavily, Brave, Wikipedia) & web_fetch (HTML to Markdown).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

function decodeEntities(s: string): string {
  const map: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
  return s
    .replace(/&(#x[0-9a-fA-F]+|#\d+|[a-z]+);/gi, (match, code) => {
      if (code.startsWith("#x")) return String.fromCharCode(parseInt(code.slice(2), 16));
      if (code.startsWith("#")) return String.fromCharCode(parseInt(code.slice(1), 10));
      return map[code.toLowerCase()] || match;
    });
}

function htmlToMarkdown(html: string): string {
  let clean = html
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

  return decodeEntities(clean)
    .split("\n")
    .map(l => l.trim())
    .filter((l, i, arr) => l !== "" || arr[i - 1] !== "")
    .join("\n")
    .trim();
}

interface SearchResult { title: string; url: string; snippet: string; }

async function searchDuckDuckGo(query: string, limit: number, signal?: AbortSignal): Promise<SearchResult[]> {
  const timeoutSig = AbortSignal.timeout(10000);
  const combinedSignal = signal ? AbortSignal.any([signal, timeoutSig]) : timeoutSig;

  const resp = await fetch(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
    },
    signal: combinedSignal,
  });

  if (resp.status === 202 || resp.status === 403 || resp.status === 429) {
    throw new Error("DuckDuckGo rate limit or anti-bot challenge encountered");
  }
  if (!resp.ok) throw new Error(`DuckDuckGo HTTP ${resp.status}`);

  const html = await resp.text();
  const results: SearchResult[] = [];
  const blocks = html.split(/<div\s+class="[^"]*result\s+results_links[^"]*"[^>]*>/i).slice(1);

  for (const block of blocks) {
    if (results.length >= limit) break;
    const hMatch = block.match(/<a\s+class="result__title"[^>]*>([\s\S]*?)<\/a>/i) ||
                  block.match(/<h2[^>]*class="result__title"[^>]*>[\s\S]*?<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    const sMatch = block.match(/<a\s+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/i) ||
                  block.match(/<div\s+class="result__snippet"[^>]*>([\s\S]*?)<\/div>/i);
    let url = hMatch ? hMatch[1] : "";
    if (url.includes("uddg=")) url = decodeURIComponent(url.match(/uddg=([^&]+)/)?.[1] || url);
    else if (url.startsWith("//")) url = "https:" + url;

    const title = decodeEntities((hMatch ? (hMatch[2] || hMatch[1]) : "").replace(/<[^>]+>/g, "").trim());
    const snippet = decodeEntities((sMatch ? sMatch[1] : "").replace(/<[^>]+>/g, "").trim());
    if (title && url) results.push({ title, url, snippet });
  }
  return results;
}

async function searchWikipediaFallback(query: string, limit: number, signal?: AbortSignal): Promise<SearchResult[]> {
  const url = `https://en.wikipedia.org/w/api.php?action=opensearch&search=${encodeURIComponent(query)}&limit=${limit}&namespace=0&format=json`;
  const resp = await fetch(url, { signal: signal || AbortSignal.timeout(8000) });
  if (!resp.ok) return [];
  const data = (await resp.json()) as [string, string[], string[], string[]];
  const titles = data[1] || [], snippets = data[2] || [], urls = data[3] || [];
  return titles.map((title, i) => ({ title, snippet: snippets[i] || "", url: urls[i] || "" }));
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
      const query = params.query.trim();
      const limit = Math.min(Math.max(params.limit || 6, 1), 15);
      if (!query) return { content: [{ type: "text", text: "Error: Query cannot be empty." }] };

      let results: SearchResult[] = [];
      let provider = "DuckDuckGo";

      try {
        results = await searchDuckDuckGo(query, limit, signal);
      } catch (err: any) {
        try {
          results = await searchWikipediaFallback(query, limit, signal);
          provider = "Wikipedia Fallback";
        } catch { /* ignore fallback error */ }

        if (results.length === 0) {
          return { content: [{ type: "text", text: `Search unavailable (${err.message}). Proceed using internal model knowledge or specific URLs with web_fetch.` }] };
        }
      }

      if (results.length === 0) return { content: [{ type: "text", text: `No results found for "${query}".` }] };

      const text = `### Web Search Results (${provider}) for "${query}"\n\n` + results.map((r, i) =>
        `**${i + 1}. [${r.title}](${r.url})**\n${r.snippet}\n`
      ).join("\n");
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
      const targetUrl = params.url.trim();
      const maxChars = params.max_chars || 20000;
      if (!/^https?:\/\//i.test(targetUrl)) return { content: [{ type: "text", text: "Error: URL must begin with http:// or https://" }] };

      try {
        const timeoutSig = AbortSignal.timeout(15000);
        const combinedSignal = signal ? AbortSignal.any([signal, timeoutSig]) : timeoutSig;

        const resp = await fetch(targetUrl, {
          headers: {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          },
          signal: combinedSignal,
        });
        if (!resp.ok) return { content: [{ type: "text", text: `HTTP error ${resp.status}: ${resp.statusText}` }] };
        const md = htmlToMarkdown(await resp.text());
        const truncated = md.length > maxChars ? md.slice(0, maxChars) + "\n\n*(Content truncated...)*" : md;
        return { content: [{ type: "text", text: `### Content from ${targetUrl}\n\n${truncated}` }] };
      } catch (err: any) {
        return { content: [{ type: "text", text: `Fetch failed: ${err.message}` }] };
      }
    },
  });
}
