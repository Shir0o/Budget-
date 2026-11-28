# Cloud MCP server

A Cloudflare Worker that lets AI apps (Claude on the web, phone or desktop, or any MCP client) read your budget from anywhere, and in read-write mode make the few safe changes listed below. It joins your encrypted Google Drive sync as one more device, `cloud-mcp`, and keeps no copy of the budget between calls. Why it works this way: [ADR 0004](../docs/adr/0004-cloud-mcp-server.md).

> **Before you start:** the server reads what your phone or Mac has synced to Drive, so Drive sync has to be running in the app first. The Worker's Google client must live in the **same Google Cloud project** as the app's, because each project gets its own hidden app folder.

## What it can do

- **Read:** every read tool of [ticket 13](../docs/wayfinder/tickets/13-mcp-tools-redaction.md), with the same redaction of card and account numbers.
- **Write (only with `MCP_MODE=read-write`):** by default `suggest_review` (fills a line's Category and Personal/Business; the line stays Unreviewed until you confirm it in the app), `update_transaction` (payee, date, memo, cleared) and `revert_change` (undoes a change made through MCP). Change `MCP_WRITE_TOOLS` to offer fewer, or other tools from ticket 13.
- **Retag a Reviewed line:** `retag_line` changes a line's Personal or Business status and Business Tag (and a gift's recipient) when you ask for it in an AI chat, for example to move a meal from Other business expense to Meals. The line stays Reviewed and keeps its Category. It's in the `MCP_WRITE_TOOLS` this repo ships; take it out to turn it off.
- **Split a line:** `split_line` splits one line into two or more parts when you ask for it in an AI chat, for example a gift for two people, each part with its own amount, Personal or Business status and recipient. The parts keep the line's Category, and a Reviewed line's parts stay Reviewed. It's in the `MCP_WRITE_TOOLS` this repo ships; take it out to turn it off.
- **Clear an old import from Review (opt-in):** add `mark_imported_reviewed` to `MCP_WRITE_TOOLS` to let an AI app mark Reviewed, as one change you can revert, the Unreviewed lines an Actual import brought in before imports arrived Reviewed. It only touches imported lines that already have a Category and Personal or Business (and a recipient for a gift). Take it out of the list again once you've used it.
- **Never:** delete anything, mark a line Reviewed that you entered, bank sync fetched or an AI app added, or touch sync, keys or bank connections.

Every change shows in the app's Change History as `Cloud · mcp:<client name>` and can be reverted there.

## Costs and limits

- **Workers Paid** (US$5 a month at the time of writing) is needed: each call replays the whole history, which takes about 1.5 s of CPU for a made-up budget of 10,000 transactions and about 3 s for a write. The free plan allows 10 ms.
- Answers are as fresh as the last sync from your phone or Mac.

## Set up

You need Node 20 or newer and the Dart SDK (the build compiles the budget logic from `packages/budget_cloud` to JavaScript).

1. **Install and sign in.**
   ```sh
   cd mcp
   npm ci
   npx wrangler login
   ```
2. **Nothing to do for the key-value store** that holds the approvals for your MCP clients: the first deploy makes it and keeps the Worker linked to it. If Wrangler writes its id into `wrangler.jsonc` afterwards, you don't need to commit that line.
3. **Make a Google OAuth client** for the Worker. In the Google Cloud console, open the project the app's Google sign-in uses, then *APIs & Services › Credentials › Create credentials › OAuth client ID*, type *Web application*, with `https://developers.google.com/oauthplayground` as an authorized redirect URI.
4. **Get a refresh token** for that client, limited to the app folder. In the [OAuth 2.0 Playground](https://developers.google.com/oauthplayground), open the gear, tick *Use your own OAuth credentials* and enter the client id and secret. Authorize only `https://www.googleapis.com/auth/drive.appdata`, sign in with the Google account the app syncs to, then *Exchange authorization code for tokens* and copy the refresh token. If the project's consent screen is still in *Testing*, Google expires the token after 7 days, so publish it to *In production*. Google may then show an "unverified app" warning when you sign in, which is expected for an app only you use.
5. **Store the secrets.** Each command asks for the value; nothing goes in the repo.
   ```sh
   npx wrangler secret put BUDGET_PAIRING_CODE    # app: Encrypted sync › Pair a device › copy the code
   npx wrangler secret put MCP_ACCESS_PASSWORD    # a new password, 20 characters or more
   npx wrangler secret put GOOGLE_CLIENT_ID
   npx wrangler secret put GOOGLE_CLIENT_SECRET
   npx wrangler secret put GOOGLE_REFRESH_TOKEN
   ```
   The pairing code holds the Budget Key, so anyone with access to this Cloudflare account can read the budget.
6. **Deploy.** Note the address it prints, `https://<your worker>`.
   ```sh
   npm run deploy
   ```
   The Worker works out its own address from each request. To pin it, for example on a custom domain, add `"PUBLIC_URL": "https://<your address>"` under `vars` in `wrangler.jsonc`.
7. **Connect an AI app.** Add a custom connector (in Claude: *Settings › Connectors › Add custom connector*) with the address `https://<your worker>/mcp`. It opens a page on your Worker that asks for `MCP_ACCESS_PASSWORD`. If the server is in read-write mode, that page also asks whether this app may make changes.

## Read-write mode

Set `"MCP_MODE": "read-write"` in `wrangler.jsonc` and deploy. AI apps you approved before stay read-only until you connect them again and tick *Allow changes*.

## Turn it off

- **Stop the AI apps:** remove the connector in each app. To cut every approved app off at once, make a new key-value store with `npx wrangler kv namespace create OAUTH_KV`, put the id it prints into the `OAUTH_KV` entry of `wrangler.jsonc` as `"id"`, and deploy; each app then has to be approved again.
- **Stop the server:** `npx wrangler delete`. Then make a new Budget Key in the app (Recovery phrase screen) so the copy in Cloudflare no longer opens the budget, and revoke the refresh token at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

## Develop

```sh
npm run check   # TypeScript
npm run smoke   # builds the Dart code and runs the tools against a fake Drive with made-up data
npm run dev     # local Worker; put the secrets in mcp/.dev.vars (ignored by git)
```
