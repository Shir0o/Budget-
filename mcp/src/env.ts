import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

/** The Worker's bindings, variables and secrets (see mcp/README.md). */
export interface Env {
  /** Grants, clients and tokens for the MCP clients you approve. */
  OAUTH_KV: KVNamespace;
  /**
   * Optional: the Worker's own address, like
   * https://budget-mcp.example.workers.dev. Left out, each request's own
   * origin is used.
   */
  PUBLIC_URL?: string;
  /** `read-only` (the default) or `read-write`. */
  MCP_MODE?: string;
  /** Write tools offered in read-write mode, comma-separated. */
  MCP_WRITE_TOOLS?: string;
  /** How many days back the daily order-email check looks: 1 to 30, 3 by default. */
  ORDER_EMAIL_DAYS?: string;

  /** Secret: the code from Encrypted sync › Pair a device in the app. */
  BUDGET_PAIRING_CODE: string;
  /** Secret: the password the consent page asks for. 20 characters or more. */
  MCP_ACCESS_PASSWORD: string;
  /** Secrets: a Google OAuth client in the app's Cloud project, and a refresh token for drive.appdata. */
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  GOOGLE_REFRESH_TOKEN: string;
  /**
   * Optional secret: a refresh token from the same Google client for
   * gmail.readonly. Set, the daily check reads new order emails.
   */
  GMAIL_REFRESH_TOKEN?: string;

  /** Set by OAuthProvider for the default handler. */
  OAUTH_PROVIDER: OAuthHelpers;
}

/** What a grant carries to every MCP request. */
export interface GrantProps {
  /** The MCP client's registered name, which becomes the Actor `mcp:<name>`. */
  clientName: string;
}

export const READ_SCOPE = "budget:read";
export const WRITE_SCOPE = "budget:write";

export function writesAllowed(env: Env): boolean {
  return (env.MCP_MODE ?? "").trim().toLowerCase().replace("readwrite", "read-write") === "read-write";
}
