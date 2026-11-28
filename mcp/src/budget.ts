// The budget logic, compiled from packages/budget_cloud (`npm run build:dart`).
import "./prelude.js";
import "./budget.dart.js";
import type { Env } from "./env";

declare global {
  // Set by the compiled Dart: one JSON request in, one JSON answer out.
  var budgetMcp: ((request: string) => Promise<string>) | undefined;
}

export interface McpTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations: { readOnlyHint: boolean; destructiveHint: boolean; openWorldHint: boolean };
}

function config(env: Env) {
  return {
    pairingCode: env.BUDGET_PAIRING_CODE ?? "",
    mode: env.MCP_MODE ?? "read-only",
    writeTools: env.MCP_WRITE_TOOLS ?? "",
  };
}

// No state is shared between requests: a Worker can't settle a promise made
// in one request from another, so a queue across calls would leave every
// later call in the isolate waiting forever once one request is cut off.
async function ask<T>(request: Record<string, unknown>): Promise<T> {
  const budgetMcp = globalThis.budgetMcp;
  if (!budgetMcp) throw new Error("The budget code isn't built: run npm run build:dart.");
  return JSON.parse(await budgetMcp(JSON.stringify(request))) as T;
}

export async function listTools(env: Env): Promise<McpTool[]> {
  const answer = await ask<{ tools?: McpTool[]; text?: string }>({ method: "list", config: config(env) });
  if (!answer.tools) throw new Error(answer.text ?? "The server's settings are wrong.");
  return answer.tools;
}

export async function callTool(
  env: Env,
  accessToken: string,
  name: string,
  args: Record<string, unknown>,
  client: string,
): Promise<{ text: string; isError: boolean }> {
  return ask({ method: "call", config: config(env), accessToken, name, arguments: args, client });
}

/** Reads raw order emails into the order offers the app matches (issue 4). */
export async function checkOrders(
  env: Env,
  accessToken: string,
  messages: string[],
): Promise<{ text: string; isError: boolean }> {
  return ask({ method: "orders", config: config(env), accessToken, messages });
}
