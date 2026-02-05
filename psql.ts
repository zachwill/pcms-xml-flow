#!/usr/bin/env bun

import { sql } from "bun";

const query = process.argv[2];

if (!query) {
  console.error("Usage: ./psql.ts 'SELECT ...'");
  process.exit(1);
}

try {
  const rows = await sql.unsafe(query);
  if (rows.length === 0) {
    console.log("(0 rows)");
  } else {
    console.table(rows);
  }
} catch (err) {
  console.error(err);
  process.exit(1);
} finally {
  await sql.close();
}
