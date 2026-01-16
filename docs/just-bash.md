# just-bash: Practical Guide (shareable with coding agents)

A concise “how to use” guide for **just-bash**, a TypeScript library that provides a **simulated bash shell** with a **virtual filesystem** (in-memory by default) designed for **safe, auditable agent execution**.

---

## 1) What just-bash is (and isn’t)

### What it is
- A **bash-like interpreter** (pipes, redirects, variables, loops, functions, etc.)
- A **virtual filesystem (VFS)** you control (in-memory, overlay-on-disk, or read-write-on-disk)
- A curated set of **built-in commands** (e.g. `ls`, `cat`, `grep`, `jq`, `find`, `sed`, `awk`, …)
- Optional **network access** via `curl` with allow-list protection
- A ready-made **AI SDK tool** (`createBashTool`) so agents can run bash safely

### What it isn’t
- Not a full OS/VM: **no native binaries**, no arbitrary executable support
- Not meant to be DOS-proof without OS isolation (it has execution limits, but still a script engine)

---

## 2) Core mental model (agents should internalize this)

### Execution model
- `bash.exec("...")` runs a command/script inside the sandbox and returns:
  - `stdout`, `stderr`, `exitCode`, and final `env`
- **Each `exec()` call is isolated**: environment variables, shell state, aliases, functions, and `cwd` do **not** persist between calls.
- **Filesystem persists** across calls (within the same `Bash` instance).

**Agent implication:**  
If you need state between steps, either:
1) Write to files (recommended), or  
2) Run multiple steps in a *single* script string (e.g. `cmd1; cmd2; cmd3`).

---

## 3) Quickstart (TypeScript)

```ts
import { Bash } from "just-bash";

const bash = new Bash({
  files: {
    "/data/users.json": '[{"name":"Alice"},{"name":"Bob"}]',
  },
});

const result = await bash.exec("cat /data/users.json | jq length");
console.log(result.stdout);   // "2
"
console.log(result.exitCode); // 0
```

---

## 4) Filesystem choices (pick the right sandbox)

just-bash supports three FS modes:

### A) InMemoryFs (default) — safest
- Everything is virtual; nothing touches disk.
- Best for most agent tasks.

```ts
const bash = new Bash(); // InMemoryFs
```

### B) OverlayFs — read real project, keep writes in memory (copy-on-write)
- Reads come from disk, writes stay in memory.
- Best for “explore a repo without modifying it”.

```ts
import { Bash } from "just-bash";
import { OverlayFs } from "just-bash/fs/overlay-fs";

const fs = new OverlayFs({ root: "/path/to/project" });
const bash = new Bash({ fs, cwd: fs.getMountPoint() });

// Reads from disk
await bash.exec("ls -la");

// Writes are virtual (do not change disk)
await bash.exec('echo "test" > README.md');
```

### C) ReadWriteFs — real disk writes (use carefully)
- For controlled sandboxes only.

```ts
import { ReadWriteFs } from "just-bash/fs/read-write-fs";

const fs = new ReadWriteFs({ root: "/path/to/sandbox-dir" });
const bash = new Bash({ fs });
```

**Agent rule of thumb:** default to **OverlayFs** for repo exploration, **InMemoryFs** for pure computation, **ReadWriteFs** only when explicitly required.

---

## 5) Built-in shell features agents can rely on

Supported patterns:
- Pipes: `cmd1 | cmd2`
- Redirects: `>`, `>>`, `2>`, `2>&1`, `<`
- Chaining: `&&`, `||`, `;`
- Variables: `$VAR`, `${VAR}`, `${VAR:-default}`
- Globs: `*`, `?`, `[...]`
- Control flow: `if/then/elif/else`, `for`, `while`, `until`
- Functions: `name() { ... }`
- Links: `ln`, `ln -s`

Commonly useful built-ins (non-exhaustive):
- File ops: `ls`, `cat`, `find`, `cp`, `mv`, `rm`, `mkdir`, `stat`, `tree`
- Text: `grep`, `sed`, `awk`, `jq`, `sort`, `uniq`, `head`, `tail`, `wc`, `cut`, `tr`, `diff`
- Env/nav: `cd`, `pwd`, `echo`, `export`, `env`

---

## 6) Custom commands (extend just-bash with TypeScript)

Use `defineCommand(name, handler)` to add domain-specific commands that feel native in pipelines.

### Minimal custom command example

```ts
import { Bash, defineCommand } from "just-bash";

const upper = defineCommand("upper", async (_args, ctx) => {
  return { stdout: ctx.stdin.toUpperCase(), stderr: "", exitCode: 0 };
});

const bash = new Bash({ customCommands: [upper] });

const r = await bash.exec("echo hello | upper");
console.log(r.stdout); // "HELLO
"
```

**Custom command handler receives `ctx`:**
- `ctx.stdin`, `ctx.cwd`, `ctx.env`
- `ctx.fs` (read/write files in the sandbox)
- `ctx.exec` (run subcommands safely from within a custom command)

**Agent guidance:** implement custom commands when you want:
- Stronger typing / safer IO than shell scripting
- Reusable, high-level primitives (e.g. “render-template”, “analyze-json”, “summarize-url”)

---

## 7) Network access (off by default)

`curl` only exists when network is enabled.

### Safe allow-list configuration

```ts
const bash = new Bash({
  network: {
    allowedUrlPrefixes: [
      "https://api.github.com/repos/myorg/",
      "https://example.com/data/",
    ],
    // allowedMethods defaults to ["GET", "HEAD"]
  },
});
```

### Full internet (discouraged unless you really mean it)

```ts
const bash = new Bash({
  network: { dangerouslyAllowFullInternetAccess: true },
});
```

**Agent rule:** prefer allow-lists; avoid POST unless explicitly required.

---

## 8) Execution limits (prevent runaway scripts)

Configure when running large loops or heavy `awk/sed`:

```ts
const bash = new Bash({
  executionLimits: {
    maxCallDepth: 100,
    maxCommandCount: 10000,
    maxLoopIterations: 20000,
    maxAwkIterations: 20000,
    maxSedIterations: 20000,
  },
});
```

**Agent guidance:** if a script fails with a limit error, increase only the specific limit you need.

---

## 9) Using just-bash as an AI tool (AI SDK integration)

`createBashTool` is the standard way to let an agent run commands.

```ts
import { createBashTool } from "just-bash/ai";
import { generateText } from "ai";

const bashTool = createBashTool({
  files: { "/data/users.json": '[{"name":"Alice"}]' },
  // Optional: fs, logger, network, extraInstructions, etc.
});

const result = await generateText({
  model: "anthropic/claude-haiku-4.5",
  tools: { bash: bashTool },
  prompt: "Count users in /data/users.json using jq.",
});
```

### Recommended “agent operating rules” to include in `extraInstructions`
Give agents a stable contract like:
- Where the project is mounted (e.g. `/home/user/project`)
- How to explore (`ls`, `find`, `grep -r`, `cat`, `tree`)
- What not to do (no assumptions about external binaries; minimize network; prefer read-only exploration when using OverlayFs)

---

## 10) CLI usage (human/operator workflows)

The `just-bash` CLI runs scripts using **OverlayFs**:
- Reads from real filesystem
- Writes are virtual/discarded

Examples:
```bash
just-bash -c 'ls -la && cat package.json | head -5'
just-bash -c 'grep -r "TODO" src/' --root /path/to/project
echo 'find . -name "*.ts" | wc -l' | just-bash
just-bash -c 'echo hello' --json
```

---

## 11) Recommended workflow patterns for coding agents

### Pattern A: Repo exploration (OverlayFs)
Use when an agent needs to inspect a real repo without modifying it.
Typical commands:
- `ls`, `tree`
- `find . -name "*.ts"`
- `grep -r "createBashTool" .`
- `cat README.md | head`
- `jq` to inspect JSON configs

### Pattern B: Multi-step transformations (persist via files)
Because `exec()` shell state doesn’t persist, store intermediate results:
- `cmd > /tmp/out.txt`
- then `cat /tmp/out.txt | ...`

### Pattern C: One-shot scripts (single exec call)
Bundle steps:
```bash
mkdir -p /tmp/work &&
cat /data/input.txt | tr -d '\r' > /tmp/work/clean.txt &&
wc /tmp/work/clean.txt
```

### Pattern D: Add a small custom command instead of complex shell
If the agent keeps writing fragile `awk/sed`:
- implement a custom TS command and reuse it in pipelines.

---

## 12) Troubleshooting checklist (agent-facing)

- **“command not found: curl”** → network not configured.
- **State “lost” between commands** → expected; put steps in one script or persist via files.
- **Need to read real project files** → use `OverlayFs` and set `cwd` to the mount point.
- **Need to actually edit files on disk** → use `ReadWriteFs` (explicit approval recommended).
- **Limit errors (loops/awk/sed)** → raise the corresponding `executionLimits`.

---

## 13) Minimal “agent handoff” snippet (drop-in template)

Use this as the standard scaffold when giving just-bash to an agent:

- FS mode: `OverlayFs` (safe repo read), or `InMemoryFs` (pure sandbox)
- `extraInstructions`: mount point + exploration commands + safety rules
- optional: a logger capturing every tool call
