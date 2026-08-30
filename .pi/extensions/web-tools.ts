/**
 * Web Tools Extension for Pi Agent
 *
 * Registers:
 * 1. web_search - Real-time web search with multi-provider fallback (DuckDuckGo keyless, Tavily, Brave)
 * 2. web_fetch  - High-fidelity webpage content extractor converting HTML into token-optimized Markdown
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// --- HTML Parsing & Markdown Conversion Helpers ---

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(parseInt(code, 10)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, code) => String.fromCharCode(parseInt(code, 16)));
}

function htmlToMarkdown(html: string): string {
  // Strip head, scripts, styles, svg, iframes, nav, header, footer
  let clean = html
    .replace(/<head[\s\S]*?<\/head>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<svg[\s\S]*?<\/svg>/gi, "")
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, "")
    .replace(/<iframe[\s\S]*?<\/iframe>/gi, "")
    .replace(/<nav[\s\S]*?<\/nav>/gi, "")
    .replace(/<footer[\s\S]*?<\/footer>/gi, "")
    .replace(/<!--[\s\S]*?-->/g, "");

  // Headings
  clean = clean.replace(/<h1[^>]*>([\s\S]*?)<\/h1>/gi, "\n# $1\n");
  clean = clean.replace(/<h2[^>]*>([\s\S]*?)<\/h2>/gi, "\n## $1\n");
  clean = clean.replace(/<h3[^>]*>([\s\S]*?)<\/h3>/gi, "\n### $1\n");
  clean = clean.replace(/<h4[^>]*>([\s\S]*?)<\/h4>/gi, "\n#### $1\n");
  clean = clean.replace(/<h5[^>]*>([\s\S]*?)<\/h5>/gi, "\n##### $1\n");
  clean = clean.replace(/<h6[^>]*>([\s\S]*?)<\/h6>/gi, "\n###### $1\n");

  // Code blocks and inline code
  clean = clean.replace(/<pre[^>]*><code[^>]*>([\s\S]*?)<\/code><\/pre>/gi, "\n```\n$1\n```\n");
  clean = clean.replace(/<code[^>]*>([\s\S]*?)<\/code>/gi, "`$1`");

  // Links
  clean = clean.replace(/<a\s+[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, "[$2]($1)");

  // Lists
  clean = clean.replace(/<li[^>]*>([\s\S]*?)<\/li>/gi, "\n- $1");

  // Paragraphs & Line breaks
  clean = clean.replace(/<p[^>]*>([\s\S]*?)<\/p>/gi, "\n\n$1\n\n");
  clean = clean.replace(/<br\s*\/?>/gi, "\n");
  clean = clean.replace(/<hr\s*\/?>/gi, "\n---\n");

  // Strip remaining HTML tags
  clean = clean.replace(/<[^>]+>/g, " ");

  // Decode entities
  clean = decodeHtmlEntities(clean);

  // Normalize whitespace and blank lines
  const lines = clean.split("\n").map(l => l.trim());
  const deduped: string[] = [];
  let prevBlank = false;
  for (const line of lines) {
    if (!line) {
      if (!prevBlank) deduped.push("");
      prevBlank = true;
    } else {
      deduped.push(line);
      prevBlank = false;
    }
  }

  return deduped.join("\n").trim();
}

// --- Search Engine Implementations ---

interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

async function searchDuckDuckGo(query: string, limit: number, signal?: AbortSignal): Promise<SearchResult[]> {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  const resp = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
    },
    signal,
  });

  if (!resp.ok) {
    throw new Error(`DuckDuckGo returned HTTP ${resp.status}`);
  }

  const html = await resp.text();
  const results: SearchResult[] = [];

  // Match result elements: <a class="result__url" href="...">, <a class="result__snippet" ...>
  const resultBlocks = html.split(/<div\s+class="[^"]*result\s+results_links[^"]*"[^>]*>/i).slice(1);

  for (const block of resultBlocks) {
    if (results.length >= limit) break;

    // Title & URL
    const titleMatch = block.match(/<a\s+class="result__snippet[^"]*"\s+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i) ||
                       block.match(/<a\s+class="result__url"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    const headingMatch = block.match(/<a\s+class="result__title"[^>]*>([\s\S]*?)<\/a>/i) ||
                         block.match(/<h2[^>]*class="result__title"[^>]*>[\s\S]*?<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);

    let resUrl = headingMatch ? (headingMatch[1] || "") : (titleMatch ? titleMatch[1] : "");
    let title = headingMatch ? (headingMatch[2] || headingMatch[1] || "") : "";
    
    // Unescape DDG redirect url e.g. //duckduckgo.com/l/?uddg=https%3A%2F%2F...
    if (resUrl.includes("uddg=")) {
      const match = resUrl.match(/uddg=([^&]+)/);
      if (match) {
        resUrl = decodeURIComponent(match[1]);
      }
    } else if (resUrl.startsWith("//")) {
      resUrl = "https:" + resUrl;
    }

    // Snippet
    const snippetMatch = block.match(/<a\s+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/i) ||
                         block.match(/<div\s+class="result__snippet"[^>]*>([\s\S]*?)<\/div>/i);
    let snippet = snippetMatch ? snippetMatch[1] : "";

    title = decodeHtmlEntities(title.replace(/<[^>]+>/g, "").trim());
    snippet = decodeHtmlEntities(snippet.replace(/<[^>]+>/g, "").trim());

    if (title && resUrl) {
      results.push({ title, url: resUrl, snippet });
    }
  }

  return results;
}

async function searchTavily(query: string, limit: number, apiKey: string, signal?: AbortSignal): Promise<SearchResult[]> {
  const resp = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      api_key: apiKey,
      query,
      max_results: limit,
      search_depth: "basic",
    }),
    signal,
  });

  if (!resp.ok) {
    throw new Error(`Tavily API HTTP ${resp.status}: ${await resp.text()}`);
  }

  const data = (await resp.json()) as any;
  return (data.results || []).map((r: any) => ({
    title: r.title || "Untitled",
    url: r.url || "",
    snippet: r.content || "",
  }));
}

async function searchBrave(query: string, limit: number, apiKey: string, signal?: AbortSignal): Promise<SearchResult[]> {
  const url = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=${limit}`;
  const resp = await fetch(url, {
    headers: {
      "Accept": "application/json",
      "X-Subscription-Token": apiKey,
    },
    signal,
  });

  if (!resp.ok) {
    throw new Error(`Brave API HTTP ${resp.status}: ${await resp.text()}`);
  }

  const data = (await resp.json()) as any;
  return (data.web?.results || []).map((r: any) => ({
    title: r.title || "Untitled",
    url: r.url || "",
    snippet: r.description || "",
  }));
}

// --- Extension Export ---

export default function webToolsExtension(pi: ExtensionAPI) {
  // 1. web_search tool
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description: "Search the web for up-to-date documentation, API signatures, libraries, tutorials, or error fixes.",
    promptSnippet: "Search the live web for technical documentation, library APIs, and references",
    promptGuidelines: [
      "Use web_search when you need current 2026 documentation, third-party library APIs, latest framework releases, or answers to external questions.",
    ],
    parameters: Type.Object({
      query: Type.String({ description: "Search terms or question (e.g. 'D3 v7 scaleBand TypeScript example')" }),
      limit: Type.Optional(Type.Number({ description: "Max results to return (default: 6, max: 15)" })),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
      const query = params.query.trim();
      const limit = Math.min(Math.max(params.limit || 6, 1), 15);

      if (!query) {
        return {
          content: [{ type: "text", text: "Error: Search query cannot be empty." }],
        };
      }

      let results: SearchResult[] = [];
      let providerUsed = "DuckDuckGo";

      const tavilyKey = process.env.TAVILY_API_KEY;
      const braveKey = process.env.BRAVE_API_KEY;

      try {
        if (tavilyKey) {
          providerUsed = "Tavily";
          results = await searchTavily(query, limit, tavilyKey, signal);
        } else if (braveKey) {
          providerUsed = "Brave";
          results = await searchBrave(query, limit, braveKey, signal);
        } else {
          providerUsed = "DuckDuckGo";
          results = await searchDuckDuckGo(query, limit, signal);
        }
      } catch (err: any) {
        // Fallback to DuckDuckGo if primary provider failed
        if (providerUsed !== "DuckDuckGo") {
          try {
            results = await searchDuckDuckGo(query, limit, signal);
            providerUsed = `DuckDuckGo (fallback after ${providerUsed} error: ${err.message})`;
          } catch (fallbackErr: any) {
            return {
              content: [{
                type: "text",
                text: `Web search error (${providerUsed}): ${err.message}\nFallback error: ${fallbackErr.message}`,
              }],
            };
          }
        } else {
          return {
            content: [{ type: "text", text: `Web search error (DuckDuckGo): ${err.message}` }],
          };
        }
      }

      if (results.length === 0) {
        return {
          content: [{ type: "text", text: `No search results found for query: "${query}" (provider: ${providerUsed})` }],
        };
      }

      const formatted = results.map((r, i) => (
        `### ${i + 1}. [${r.title}](${r.url})\n**URL:** ${r.url}\n${r.snippet}\n`
      )).join("\n---\n\n");

      return {
        content: [{
          type: "text",
          text: `Found ${results.length} results for "${query}" (via ${providerUsed}):\n\n${formatted}`,
        }],
        details: { query, resultsCount: results.length, provider: providerUsed },
      };
    },
  });

  // 2. web_fetch tool
  pi.registerTool({
    name: "web_fetch",
    label: "Web Fetch",
    description: "Fetch a webpage URL and extract clean Markdown content with headings, code blocks, and links.",
    promptSnippet: "Fetch and read the text/markdown content of a webpage URL",
    promptGuidelines: [
      "Use web_fetch to read documentation pages, GitHub files, API guides, or blog posts found via web_search.",
    ],
    parameters: Type.Object({
      url: Type.String({ description: "The full HTTP/HTTPS URL to fetch" }),
      maxChars: Type.Optional(Type.Number({ description: "Maximum characters to return (default: 20000)" })),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
      const targetUrl = params.url.trim();
      const maxChars = Math.min(Math.max(params.maxChars || 20000, 1000), 100000);

      if (!targetUrl.startsWith("http://") && !targetUrl.startsWith("https://")) {
        return {
          content: [{ type: "text", text: `Error: Invalid URL '${targetUrl}'. Must start with http:// or https://.` }],
        };
      }

      try {
        const resp = await fetch(targetUrl, {
          headers: {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,text/plain,*/*;q=0.8",
          },
          signal,
        });

        if (!resp.ok) {
          return {
            content: [{ type: "text", text: `HTTP error ${resp.status} (${resp.statusText}) fetching ${targetUrl}` }],
          };
        }

        const contentType = resp.headers.get("content-type") || "";
        const rawText = await resp.text();

        let markdown: string;
        if (contentType.includes("text/plain") || contentType.includes("application/json")) {
          markdown = rawText;
        } else {
          markdown = htmlToMarkdown(rawText);
        }

        const truncated = markdown.length > maxChars;
        const finalText = truncated
          ? markdown.slice(0, maxChars) + `\n\n... [Content truncated at ${maxChars} chars out of ${markdown.length} total chars]`
          : markdown;

        return {
          content: [{
            type: "text",
            text: `# Fetched: ${targetUrl}\n\n${finalText}`,
          }],
          details: { url: targetUrl, totalLength: markdown.length, returnedLength: finalText.length, truncated },
        };
      } catch (err: any) {
        return {
          content: [{ type: "text", text: `Failed to fetch URL ${targetUrl}: ${err.message}` }],
        };
      }
    },
  });
}
