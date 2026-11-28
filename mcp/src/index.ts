// The cloud MCP server (ADR 0004): OAuth in front, the budget tools behind.
import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { authorize } from "./authorize";
import { type Env, READ_SCOPE, WRITE_SCOPE } from "./env";
import { handleMcp, type McpContext } from "./mcp";
import { checkOrderEmails } from "./orders";

let provider: OAuthProvider<Env> | undefined;
let providerFor: string | undefined;

/** The Worker's origin: PUBLIC_URL when it is set, otherwise the request's. */
function originOf(request: Request, env: Env): string {
  return new URL(env.PUBLIC_URL?.trim() || request.url).origin;
}

function oauth(origin: string): OAuthProvider<Env> {
  if (provider && providerFor === origin) return provider;
  provider = new OAuthProvider<Env>({
    apiRoute: "/mcp",
    apiHandler: {
      fetch: (request, env, ctx) => handleMcp(request, env as Env, ctx as McpContext),
    },
    defaultHandler: {
      async fetch(request, env) {
        const url = new URL(request.url);
        if (url.pathname === "/authorize") return authorize(request, env as Env);
        if (url.pathname === "/") return new Response("Budget MCP server. Connect an MCP client to /mcp.");
        return new Response("Not found", { status: 404 });
      },
    },
    authorizeEndpoint: "/authorize",
    tokenEndpoint: "/token",
    clientRegistrationEndpoint: "/register",
    scopesSupported: [READ_SCOPE, WRITE_SCOPE],
    requiredScopes: [READ_SCOPE],
    resourceMetadata: {
      resource: `${origin}/mcp`,
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
      resource_name: "Budget",
    },
  });
  providerFor = origin;
  return provider;
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return oauth(originOf(request, env)).fetch(request, env, ctx);
  },
  // The daily order-email check (wrangler.jsonc's cron). It logs only its
  // one-line outcome, never an email.
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(
      checkOrderEmails(env).then(
        (outcome) => console.log(`order emails: ${outcome}`),
        (error) => console.error(`order emails: ${error instanceof Error ? error.message : "failed"}`),
      ),
    );
  },
} satisfies ExportedHandler<Env>;
