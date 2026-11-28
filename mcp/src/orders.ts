// The daily order-email check (issue 4): finds new Amazon, Walmart and
// AliExpress order emails with Gmail's API (read-only) and hands them to the
// budget code, which reads their orders with plain code and leaves them as
// offers in Drive. The app matches them to bank lines; a person applies
// each one. Nothing here uses AI or changes the budget.
import { checkOrders } from "./budget";
import type { Env } from "./env";
import { driveAccessToken, gmailAccessToken } from "./google";

const SENDERS = ["auto-confirm@amazon.com", "help@walmart.com", "transaction@notice.aliexpress.com"];

/** The search: order confirmations only, from the last few days. */
export function orderQuery(days: number): string {
  return `from:(${SENDERS.join(" OR ")}) newer_than:${days}d -subject:(shipped OR delivered OR canceled OR cancelled)`;
}

/** Gmail's base64url as one character per byte, the way an mbox is read. */
export function rawToText(raw: string): string {
  return atob(raw.replace(/-/g, "+").replace(/_/g, "/"));
}

export async function checkOrderEmails(env: Env): Promise<string> {
  if (!env.GMAIL_REFRESH_TOKEN?.trim()) return "Gmail isn't set up, so there's nothing to check.";
  const days = Math.min(Math.max(Number(env.ORDER_EMAIL_DAYS ?? "3") || 3, 1), 30);
  const gmail = await gmailAccessToken(env);
  const headers = { authorization: `Bearer ${gmail}` };
  const list = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=40&q=${encodeURIComponent(orderQuery(days))}`,
    { headers },
  );
  if (!list.ok) throw new Error(`Gmail search failed (${list.status}).`);
  const ids = (((await list.json()) as { messages?: { id: string }[] }).messages ?? []).map((m) => m.id);
  const messages: string[] = [];
  for (const id of ids) {
    const response = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${encodeURIComponent(id)}?format=raw`,
      { headers },
    );
    if (!response.ok) continue;
    const { raw } = (await response.json()) as { raw?: string };
    if (raw) messages.push(rawToText(raw));
  }
  const result = await checkOrders(env, await driveAccessToken(env), messages);
  if (result.isError) throw new Error(result.text);
  return result.text;
}
