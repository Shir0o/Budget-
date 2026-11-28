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

// One call at a time per isolate. Each call holds the whole replayed budget
// in memory (a write of a few thousand transactions peaks near 70 MB), and
// requests that share an isolate share its 128 MB, so two writes at once
// could end with Cloudflare stopping the isolate and answering 502 or 503.
let queue: Promise<unknown> = Promise.resolve();

async function ask<T>(request: Record<string, unknown>): Promise<T> {
  const budgetMcp = globalThis.budgetMcp;
  if (!budgetMcp) throw new Error("The budget code isn't built: run npm run build:dart.");
  const answer = queue.then(() => budgetMcp(JSON.stringify(request)));
  queue = answer.catch(() => undefined);
  return JSON.parse(await answer) as T;
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
