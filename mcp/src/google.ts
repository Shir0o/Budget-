import type { Env } from "./env";

// Access tokens for Drive's app data folder and, when it is set up, Gmail
// read-only, each refreshed from its refresh token a few minutes before it
// expires. Kept in memory only.
const cached = new Map<string, { token: string; expires: number }>();

async function accessToken(env: Env, refreshToken: string, name: string): Promise<string> {
  const hit = cached.get(name);
  if (hit && hit.expires > Date.now() + 120_000) return hit.token;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: env.GOOGLE_CLIENT_ID.trim(),
      client_secret: env.GOOGLE_CLIENT_SECRET.trim(),
      refresh_token: refreshToken.trim(),
    }),
  });
  if (!response.ok) {
    // Never log the body: it can echo the request.
    throw new Error(`Google sign-in for ${name} failed (${response.status}). Check the Google secrets.`);
  }
  const body = (await response.json()) as { access_token: string; expires_in: number };
  cached.set(name, { token: body.access_token, expires: Date.now() + body.expires_in * 1000 });
  return body.access_token;
}

export function driveAccessToken(env: Env): Promise<string> {
  return accessToken(env, env.GOOGLE_REFRESH_TOKEN, "Drive");
}

export function gmailAccessToken(env: Env): Promise<string> {
  return accessToken(env, env.GMAIL_REFRESH_TOKEN ?? "", "Gmail");
}
