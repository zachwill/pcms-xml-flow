import { RouteRegistry } from "@/lib/server/router";

export const healthRouter = new RouteRegistry();

// GET /api/health
healthRouter.get("/", async () => {
  return Response.json({ ok: true, timestamp: new Date().toISOString() });
});
