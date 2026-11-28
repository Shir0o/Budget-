# 0003 No auto-categorization

- **Status:** accepted (2026-10-29)

## Context

Actual (rules) and YNAB (payee memory) categorize transactions automatically by default. The user needs to decide by hand, for every transaction, its category and whether it is a reportable self-employment expense. Auto-applied categories quietly skip that review and corrupt the business report.

## Decision

Nothing assigns a category or business status without a person's tap. The app may show a hint chip (last-used values for the payee). Bank sync, schedules, and MCP may only *pre-fill* values; a line becomes Reviewed only after the user confirms it. Actual's rules are not imported.

**Amended 2026-11-28:** a one-time import from Actual brings its lines in Reviewed, in every year, because a person already reviewed them there. Lines the import can't settle (mapped to two Business Tags, or a gift with no recipient) still import Unreviewed. New lines from bank sync, schedules and MCP keep the rule above.

**Amended again 2026-11-28:** for a budget imported before that change, the MCP write tool `mark_imported_reviewed` (offered only in read-write mode, and on the cloud server only when `MCP_WRITE_TOOLS` names it) marks Reviewed, as one revertable change, the Unreviewed lines a one-time import created that need nothing more. It never touches lines from bank sync, schedules, MCP or a person, nor imported lines that still need a Category, Personal or Business, a Business Tag or a gift's recipient.

**Amended a third time 2026-11-28:** the MCP write tool `retag_line` (offered only in read-write mode, and on the cloud server only when `MCP_WRITE_TOOLS` names it) changes one line's business status, and a gift's recipient, when the person asks for it in an AI chat. It never changes a Category and never changes whether a line is Reviewed: a Reviewed line stays Reviewed, because the person chose the new value, and an Unreviewed one still waits for their tap. A Reviewed line can't be left needing something, so a gift on one needs a recipient. Each retag is one change in Change History that the person can revert.

## Consequences

- More taps per transaction. This is by design: review is part of the product.
- Business reports can trust that every line was looked at by a person.
- A future reader will expect a rules engine. This ADR is why there isn't one.
