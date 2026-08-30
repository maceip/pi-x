---
name: browser-apps
description: Modern browser application architecture, DOM API lifecycle, Canvas 2D / WebGL rendering pipelines, CSS layout and animations, Web Workers, requestAnimationFrame timing, client-side routing, Vite/ESBuild bundling, and web performance profiling. Use when building interactive browser applications, dashboards, or frontend components.
---

# Browser Applications Skill

Modern web and browser application architecture guidelines for high-frame-rate, accessible, and responsive user interfaces.

## Architectural Directives

1. **DOM & Reactivity**:
   - Minimize DOM layout thrashing: Batch style reads (`getBoundingClientRect`, `offsetHeight`) before style writes.
   - Use CSS transforms (`translate3d`, `scale`) and `opacity` for 60fps/120fps animations to run exclusively on the GPU compositor thread.
   - Use `ResizeObserver`, `IntersectionObserver`, and `MutationObserver` rather than scroll/resize event polling.
2. **Animation Loops & Canvas/WebGL**:
   - Always decouple physics/simulation tick (`dt`) from frame rendering using `requestAnimationFrame(render)`.
   - Scale canvas backing store with `window.devicePixelRatio` to ensure sharp rendering on Retina displays:
     ```typescript
     const dpr = window.devicePixelRatio || 1;
     canvas.width = cssWidth * dpr;
     canvas.height = cssHeight * dpr;
     ctx.scale(dpr, dpr);
     ```
3. **Threading & Offscreen Work**:
   - Heavy data transformations, AST processing, or large numeric calculations must be delegated to Web Workers or `OffscreenCanvas`.
4. **Clean Component Lifecycle**:
   - Every mount/render function must return a clean `dispose()` or `unsubscribe()` teardown to eliminate memory leaks and event listener retention.

## Minimal High-Performance HTML/TypeScript Scaffold

```typescript
export class CanvasRenderer {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private rafId: number | null = null;
  private resizeObserver: ResizeObserver;

  constructor(private container: HTMLElement) {
    this.canvas = document.createElement("canvas");
    this.canvas.style.width = "100%";
    this.canvas.style.height = "100%";
    this.canvas.style.display = "block";
    this.container.appendChild(this.canvas);

    const context = this.canvas.getContext("2d", { alpha: false });
    if (!context) throw new Error("Could not acquire 2D context");
    this.ctx = context;

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.container);
    this.resize();
    this.startLoop();
  }

  private resize() {
    const dpr = window.devicePixelRatio || 1;
    const width = this.container.clientWidth;
    const height = this.container.clientHeight;
    this.canvas.width = Math.floor(width * dpr);
    this.canvas.height = Math.floor(height * dpr);
    this.ctx.resetTransform();
    this.ctx.scale(dpr, dpr);
  }

  private startLoop() {
    const loop = (timestamp: number) => {
      this.draw(timestamp);
      this.rafId = requestAnimationFrame(loop);
    };
    this.rafId = requestAnimationFrame(loop);
  }

  private draw(timestamp: number) {
    const width = this.container.clientWidth;
    const height = this.container.clientHeight;
    this.ctx.fillStyle = "#0f172a";
    this.ctx.fillRect(0, 0, width, height);

    // Render interactive scene elements here
  }

  public destroy() {
    if (this.rafId !== null) cancelAnimationFrame(this.rafId);
    this.resizeObserver.disconnect();
    this.canvas.remove();
  }
}
```
