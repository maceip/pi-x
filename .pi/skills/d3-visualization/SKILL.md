---
name: d3-visualization
description: Comprehensive D3.js (v7+) data visualization engineering, covering SVG/Canvas rendering, scale functions, data joins (selection.join), responsive coordinate systems, zoom/pan behaviors, hierarchical layouts (trees, treemaps, pack), force simulations, and interactive transitions. Use when creating, modifying, or debugging D3 charts and data graphics.
---

# D3.js (v7+) Data Visualization Skill

Modern, declarative, and performant D3.js implementation patterns for web and browser applications.

## Key Principles

1. **Modern Data Joins (`selection.join`)**: Never use obsolete `.enter().append() / .exit().remove()` boilerplate. Use `selection.selectAll(...).data(data, keyFn).join('tag')` or custom enter/update/exit callback hooks.
2. **Margin Convention & Responsive SVG ViewBox**:
   - Always define `const margin = { top: 20, right: 30, bottom: 40, left: 50 };`
   - Compute `innerWidth = width - margin.left - margin.right`, `innerHeight = height - margin.top - margin.bottom`.
   - Set SVG attributes `viewBox="0 0 ${width} ${height}"` and `preserveAspectRatio="xMidYMid meet"`.
3. **Correct Scale Selection**:
   - Continuous numerical data: `d3.scaleLinear()`, `d3.scaleLog()`, `d3.scalePow()`.
   - Time series: `d3.scaleUtc()`, `d3.scaleTime()`.
   - Categorical discrete data: `d3.scaleBand()`, `d3.scaleOrdinal()`.
   - Sequential / Diverging color ramps: `d3.scaleSequential(d3.interpolateViridis)`, `d3.scaleDiverging(d3.interpolateRdYlGn)`.
4. **SVG vs. Canvas Performance**:
   - Use SVG for interactive graphics with < 2,000 DOM nodes or vector crispness requirements.
   - Use HTML5 Canvas or WebGL via D3 paths (`d3.geoPath().context(ctx)`, `d3.line().context(ctx)`) for datasets exceeding 5,000 points.

## Standard D3 Component Template

```typescript
import * as d3 from "d3";

export interface DataPoint {
  date: Date;
  value: number;
  category: string;
}

export interface ChartOptions {
  width?: number;
  height?: number;
  margin?: { top: number; right: number; bottom: number; left: number };
}

export function renderLineChart(
  container: HTMLElement,
  data: DataPoint[],
  options: ChartOptions = {}
): () => void {
  const width = options.width ?? container.clientWidth ?? 800;
  const height = options.height ?? 400;
  const margin = options.margin ?? { top: 20, right: 30, bottom: 40, left: 50 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;

  // Clear previous content
  d3.select(container).selectAll("*").remove();

  const svg = d3
    .select(container)
    .append("svg")
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("width", "100%")
    .attr("height", "100%")
    .style("display", "block");

  const g = svg
    .append("g")
    .attr("transform", `translate(${margin.left},${margin.top})`);

  // Scales
  const x = d3
    .scaleTime()
    .domain(d3.extent(data, d => d.date) as [Date, Date])
    .range([0, innerWidth]);

  const y = d3
    .scaleLinear()
    .domain([0, (d3.max(data, d => d.value) ?? 100) * 1.1])
    .nice()
    .range([innerHeight, 0]);

  // Axes
  g.append("g")
    .attr("transform", `translate(0,${innerHeight})`)
    .call(d3.axisBottom(x).ticks(width / 80).tickSizeOuter(0));

  g.append("g")
    .call(d3.axisLeft(y).ticks(5))
    .call(g => g.select(".domain").remove())
    .call(g =>
      g
        .selectAll(".tick line")
        .clone()
        .attr("x2", innerWidth)
        .attr("stroke-opacity", 0.1)
    );

  // Line generator
  const line = d3
    .line<DataPoint>()
    .x(d => x(d.date))
    .y(d => y(d.value))
    .curve(d3.curveMonotoneX);

  // Path draw with animation
  const path = g
    .append("path")
    .datum(data)
    .attr("fill", "none")
    .attr("stroke", "#3b82f6")
    .attr("stroke-width", 2.5)
    .attr("d", line);

  // Cleanup handler
  return () => {
    svg.remove();
  };
}
```
