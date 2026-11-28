# 0004 Optional cloud MCP server as one more sync device

- **Status:** proposed (2026-11-27)
- **Amends:** [0002](0002-encrypted-google-drive-sync.md) (no server), [ticket 13](../wayfinder/tickets/13-mcp-tools-redaction.md) (stdio on the Mac only)

## Context

The MCP server of ticket 13 runs on the Mac over stdio, so AI apps on the phone or the web can't reach the budget, and it only answers while the Mac is on. The owner picked a cloud server: a Cloudflare Worker on their own Cloudflare account that any MCP client can reach over HTTPS.

The budget has no server of its own (ADR 0002). Its only shared copy is the encrypted segments in Google Drive's app data folder.

## Decision

An **opt-in** Cloudflare Worker (`mcp/`) that joins the budget's Drive sync as one more device, `cloud-mcp`:

- **Reads:** each call lists every device folder, opens the segments with the Budget Key and replays the Events. It keeps nothing between calls: no database, no cache of the budget.
- **Writes:** a write tool runs one Command as `mcp:<client>`, then uploads only its own new Events to its own folder (`<budgetId>/cloud-mcp/seg-*.bin`), as a phone or Mac would. If the upload fails, the change is dropped and the call says so.
- **Same tools and rules as ticket 13:** the budget logic is `budget_core`, `budget_sync` and `budget_mcp`'s tools compiled to JavaScript (`packages/budget_cloud`), not a rewrite. Redaction, the refusal of card and account numbers, and "only MCP's own changes can be reverted" carry over unchanged.
- **Read-only by default.** `MCP_MODE=read-write` adds only the write tools in `MCP_WRITE_TOOLS`, by default `suggest_review` (fill a line's Category and Personal/Business), `update_transaction` (payee, date, memo, cleared) and `revert_change`. There is still no tool that deletes anything. The one tool that marks lines Reviewed, `mark_imported_reviewed`, only touches lines a one-time import brought in and is offered only when `MCP_WRITE_TOOLS` names it (ADR 0003, amended). `retag_line` changes a line's business status on request, keeping it Reviewed, and `split_line` splits a line into parts the same way (ADR 0003, amended).
- **Access:** OAuth 2.1 (`@cloudflare/workers-oauth-provider`). Each MCP client is approved once on a consent page that asks for the owner's password (`MCP_ACCESS_PASSWORD`, 20+ characters). A connection may be approved read-only even when the server allows writes. GET on `/mcp` answers 405, so clients don't hold a stream open.
- **Secrets** live in the owner's Cloudflare account as Worker secrets: the pairing code (budget id and Budget Key), a Google OAuth client and refresh token limited to `drive.appdata` in the app's own Cloud project, and the consent password.

## Consequences

- The Budget Key leaves the owner's devices: a copy sits in Cloudflare's secret store, and the Worker sees plaintext while it runs. Anyone who controls the Cloudflare account can read the budget. This is the price of reaching the budget from anywhere; turning the Worker off and rotating the Budget Key (Recovery phrase screen) ends it.
- Answers are only as fresh as the last sync from the phone or Mac.
- Replaying the whole log on every call costs CPU: about 1.5 s for a made-up budget of 10,000 transactions, more for a write. That needs Workers Paid (the free plan allows 10 ms per request). Snapshots keep the number of files small.
- Two writes at the same moment can both upload a segment with the same number. Both are read and merged by Event id, so nothing is lost.
- `budget_sync`'s `dart:io` transport moved to its own file, and `budget_sync/core.dart` and `budget_mcp/tools.dart` export the parts that also compile to JavaScript.

## Alternatives rejected

- **The Mac's stdio server behind a tunnel:** free, but only answers while the Mac is awake, and only as fresh as the Mac's last sync.
- **Porting the tools to TypeScript:** two copies of the budget math to keep in step.
- **Keeping a decrypted copy in Cloudflare (D1 or KV):** faster, but a standing plaintext copy of the budget outside the owner's devices.
