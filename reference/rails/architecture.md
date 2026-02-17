# Rails Architecture — Tacit Knowledge

> Durable mental models for building serious Rails systems.
> These principles survive version churn. They apply to Rails 8 and beyond.

---

## The core insight

Rails makes it easy to start.
Long-term success depends on how you handle complexity boundaries.

Two schools of thought exist (strip Rails down vs. extend Rails idiomatically).
They disagree on tactics but agree on the structural problem:

> Rails does not protect you from architectural entropy.
> It protects you from boilerplate — not from poor boundaries.

---

## 1. The Hidden Cost Curve: "0 → 1" Is Not "1 → N"

Rails optimizes **initial velocity**. Maintenance cost compounds. Growth exposes structural weaknesses.

Modern Rails (authentication generator, Kamal, Solid Queue, etc.) doubles down on 0→1. But the structural problem remains:

- Business logic leaks.
- Models grow.
- Views query data.
- Tests slow down.
- Abstractions pile up.

Nothing in Rails stops that. You must.

---

## 2. Active Record's Real Problem Isn't N+1 — It's Implicitness

The danger isn't SQL. The danger is invisible behavior.

Calling `tickets` looks like Ruby. But it's not Ruby — it's a database boundary crossing.

**Any implicit I/O inside normal-looking Ruby creates architectural blindness.**

This applies beyond AR:

- HTTP calls hidden in helpers
- Redis calls in callbacks
- Side effects inside validations
- Mailers triggered in model hooks

Rails makes I/O feel like method calls. That's power — and risk.

Tools like Bullet treat symptoms. The structural risk remains.

---

## 3. Views Should Be Pure Render Functions

Rendering should never trigger new data loading.

A view should be a pure function of already-fetched data.

Rails *allows* view-layer queries. That doesn't mean you should allow them.

If rendering can cause I/O, your performance and correctness become non-local problems. That's architectural fragility.

---

## 4. The Real Enemy: Layer Collapse

Complexity becomes unmanageable when layers leak upward.

Examples of layer violations:

- Wizard state inside models
- Complex query builders inside AR models
- Session logic inside controllers
- Domain decisions inside callbacks

Layer violation is what creates "monster Rails apps." Not lack of patterns. Not lack of gems. Layer collapse.

---

## 5. Don't Import Architecture — Extract It

**❌ Don't start with patterns.**
**✅ Start with pressure.**

Abstraction should emerge from:

- duplicated logic
- complexity hotspots
- readability breakdown
- test pain

Not from:

- a conference talk
- a "clean architecture" diagram
- a gem trending on GitHub

Most Rails monstrosities are caused by premature architectural imports.

---

## 6. "Rails-Like" Matters More Than "Clean"

If your abstraction doesn't behave like Rails, doesn't use familiar patterns, doesn't integrate with helpers, or breaks conventions — you're increasing team complexity.

**Abstractions must lower cognitive load, not increase it.**

A "clean" abstraction that feels foreign to Rails is worse than an imperfect Rails-ish one.

This is where many rom-rb / dry-rb / service-heavy architectures fail in practice: they technically isolate concerns but violate Rails ergonomics. That cost is real.

---

## 7. Separation of Responsibility ≠ Separation of Complexity

You can separate concerns and still make the codebase harder.

Example: introduce monads in one model, functional patterns in one query object, a DSL in one subsystem. Now junior devs are afraid of those files.

**Separate *advanced complexity* away from common code paths.**

Keep:

- models readable
- controllers boring
- abstractions isolated

Let advanced technique live in isolated files that nobody has to mentally parse daily.

---

## 8. State Machines Are Architectural Boundaries

Multi-step forms feel like a UI problem. But they introduce **state transitions**.

State is not model data. State is process logic. That belongs in:

- workflow objects
- state machines
- transaction pipelines

Not inside AR models.

Generalized rule: whenever you detect conditional flow logic, "if step == X," or transitional behavior — you probably need a new abstraction layer.

---

## 9. Transactions > Callbacks

Hidden lifecycle hooks create non-determinism.

Callbacks feel magical. Transactions feel explicit.

Explicit flows:

- are testable
- are readable
- don't surprise future you

Callbacks are implicit pipelines. Transactions are declared pipelines.

As systems grow, explicit orchestration wins.

---

## 10. Rails Is an Assembly Line

Request → workstations → response.

**Scaling a Rails app means adding workstations, not stuffing more into the existing ones.**

Bad scaling:

- fatter models
- fatter controllers
- more helpers
- more callbacks

Good scaling:

- new abstraction layer
- clear data flow
- strict boundaries

---

## 11. The Real Rails Way (Summary)

1. Master Rails before escaping it.
2. Respect conventions.
3. Keep I/O boundaries explicit.
4. Introduce layers deliberately.
5. Extract abstractions from pressure.
6. Keep developer ergonomics Rails-like.
7. Protect readability for average team members.
8. Prefer explicit workflows over magic callbacks.
9. Treat views as pure rendering.
10. Don't let models become gravity wells.

---

## 12. Extending vs. Replacing

The stronger long-term strategy:

- Use Rails' building blocks.
- Extend consciously.
- Avoid replacing the core unless you truly need to.

Full AR removal is high-cost and rarely necessary. But treat Active Record like a loaded weapon.

---

## How this applies to this project

| Principle | Our application |
|-----------|-----------------|
| SQL does the math | Cap/trade/CBA logic lives in Postgres (`pcms.fn_*`, warehouses). Don't reimplement in Ruby. |
| Views are pure render | ERB partials receive pre-fetched data from controllers. No queries in views. |
| Explicit I/O boundaries | Database calls happen in controllers/query objects, not in helpers or partials. |
| Extract from pressure | Don't add service objects or patterns until real pain demands it. |
| Rails-like ergonomics | Abstractions follow Rails conventions (see `web/AGENTS.md` hard rules). |
| Controllers stay boring | Controllers fetch data and render. Business logic lives in SQL or dedicated objects. |

See also:
- `web/AGENTS.md` — Rails + Datastar hard rules and decision trees
- `web/docs/design_guide.md` — Visual patterns and shell templates
- `reference/blueprints/mental-models-and-design-principles.md` — Analyst workflow mental models
