#!/usr/bin/env bun
import { loop, work } from "./core";

/**
 * design.ts — nonstop UI convergence loop for non-Salary-Book surfaces.
 *
 * Intent:
 * - No supervisor.
 * - No TODO queue.
 * - Keep looping forever, picking random index routes each iteration.
 */

const INDEX_ROUTES = [
  "/players",
  "/agents",
  "/teams",
  "/agencies",
  "/drafts",
  "/draft-selections",
  "/trades",
  "/transactions",
  "/system-values",
] as const;

function extractRoute(text: string | null | undefined): string | null {
  if (!text) return null;
  const match = text.match(/\/(?:[a-z0-9-]+)(?:\/:?[a-z0-9_-]+)?/i);
  return match?.[0] ?? null;
}

function chooseRoute(context: string | null): (typeof INDEX_ROUTES)[number] {
  const contextRoute = extractRoute(context);
  if (contextRoute && INDEX_ROUTES.includes(contextRoute as (typeof INDEX_ROUTES)[number])) {
    return contextRoute as (typeof INDEX_ROUTES)[number];
  }

  return INDEX_ROUTES[Math.floor(Math.random() * INDEX_ROUTES.length)];
}

function promptFor(route: string): string {
  return `
Read the following:

1. web/AGENTS.md

2. There's only two well designed parts of web/ right now: Salary Book and Noah

3. Fix the following to look much more like them (including the command bar, the main canvas, the sidebar, etc)

Your task: fix ${route}

- The command bar is a disaster
- The main canvas should be edge-to-edge and should feel like Salary Book or Noah
- The sidebar behavior should feel like the same product system
- Don't spend time on tests unless they directly block shipping the route improvement

Execution requirements:
1) Use agent-browser and inspect references first:
   - http://localhost:3000/
   - http://localhost:3000/ripcity/noah
2) Inspect target route:
   - http://localhost:3000${route}
3) Implement improvements in web/.
4) Commit when done:
   - git add -A && git commit -m "design: improve ${route}"
`.trim();
}

loop({
  name: "design",
  // Required by loop API, but intentionally unused as a TODO queue.
  taskFile: ".ralph/DESIGN_LOOP.md",
  timeout: "15m",
  pushEvery: 4,
  maxIterations: 500,
  maxConsecutiveTimeouts: 0,
  continuous: true,

  run(state) {
    const route = chooseRoute(state.context);

    return work(promptFor(route), {
      provider: "openai-codex",
      model: "gpt-5.3-codex",
      thinking: "high",
      timeout: "12m",
    });
  },
});
