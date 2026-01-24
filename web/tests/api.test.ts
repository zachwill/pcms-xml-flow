import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { createServer } from "../src/server";

let server: ReturnType<typeof createServer>;
let baseUrl: string;

beforeAll(() => {
  // Use an ephemeral port so tests don't collide with a running dev server.
  server = createServer({ port: 0 });
  baseUrl = `http://localhost:${server.port}`;
});

afterAll(() => {
  server.stop(true);
});

describe("API", () => {
  test("GET /api/health returns ok", async () => {
    const response = await fetch(`${baseUrl}/api/health`);
    expect(response.status).toBe(200);

    const data = await response.json();
    expect(data.ok).toBe(true);
    expect(data.timestamp).toBeDefined();
  });
});
