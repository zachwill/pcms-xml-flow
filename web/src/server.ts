import homepage from "./index.html";
import { RouteRegistry } from "./lib/server/router";
import { healthRouter } from "./api/routes/health";
import { salaryBookRouter } from "./api/routes/salary-book";

function parsePort(value: string | undefined, fallback: number) {
  if (value == null) return fallback;
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

export function createServer(opts: { port?: number } = {}) {
  const appRouter = new RouteRegistry();

  // API routes
  appRouter.merge(healthRouter, "/api/health");
  appRouter.merge(salaryBookRouter, "/api/salary-book");

  // Static/SPA routes
  appRouter.register("/favicon.ico", new Response(null, { status: 204 }));
  appRouter.register("/*", homepage);

  const port = opts.port ?? parsePort(process.env.PORT, 3002);

  return Bun.serve({
    port,
    hostname: "0.0.0.0",

    routes: appRouter.compile(),

    error(error) {
      console.error("Fatal Server Error:", error);
      return Response.json(
        {
          error: "Internal Server Error",
          message: error instanceof Error ? error.message : String(error),
        },
        { status: 500 }
      );
    },
  });
}

if (import.meta.main) {
  const server = createServer();
  console.log(`Server running at http://localhost:${server.port}`);
}
