# Real-data test run (issue 5)

A one-time, end-to-end run of the migration on a real Android phone with your real Actual
export, before switching from Actual. Ticket 18 checked the importer against real exports on a
computer; this run checks the whole flow on the phone.

**Your data stays with you.** Keep the exports in `private/` (ignored by git) or only on the
phone. Never paste real payees, amounts, account names or screenshots into an issue, a PR or a
chat. When something breaks, file it with the
[real-data run bug form](../../.github/ISSUE_TEMPLATE/real-data-run-bug.yml) and describe it
with made-up numbers.

Keep using Actual during the run. Nothing here changes your Actual budget.

## Before you start

- [ ] A fresh Actual export (`Settings › Export` in Actual) and, for the comparison, a fresh
      YNAB export. Note the date you took them: balances are compared as of that day.
- [ ] Your SimpleFIN setup token or access URL at hand (SimpleFIN Bridge account page).
- [ ] The Mac with the latest release (`budget-macos.dmg` on the GitHub Release).
- [ ] About an hour for steps 1 to 4. Step 5 runs over a week.

## 1. Install the internal-testing build

- [ ] On the phone, open the Play internal-testing link and install the newest build. Check
      that the version in Android's app info matches the latest GitHub Release.
- [ ] If an older test budget is on the phone, export a backup first
      (`Settings › Export & backup`), then start a new Budget so the run starts clean.

**Pass:** the app opens to an empty Budget.

## 2. Import from Actual, then compare with YNAB

- [ ] `Settings › Import from Actual`, choose the Actual export zip. Note how long it takes.
- [ ] `Settings › Import & compare`, choose the YNAB export zip. Pair any names the screen
      can't pair, and decide each YNAB-only item (pull in or skip).

**Pass:** the import finishes without an error; the four checks of ticket 14 show only the
expected, labelled differences; current-year lines are Unreviewed and earlier years Reviewed
(ticket 09).

**Write down (counts only):** number of accounts, categories and transactions imported; number
of unexpected differences in each comparison check.

## 3. Balances and Available for the current month

For each account, and each category, compare Budget with Actual for the export date.

- [ ] Every account balance matches Actual's balance on the export date.
- [ ] Every category's **Available** for the current month matches Actual.
- [ ] Ready to Assign matches Actual's "To Budget" (or the difference is explained by an
      expected difference from step 2).

**Pass:** no unexplained difference. For a bug, give the size and sign of the gap with a
made-up base, e.g. "Groceries shows 10.00 more than Actual, and the difference equals one
split line from last month".

## 4. Bank sync with SimpleFIN

- [ ] `Settings › Bank sync`, link SimpleFIN, map each SimpleFIN account to its Budget account.
- [ ] Run a fetch. Then run a second fetch right away.
- [ ] Open Review. Check possible matches with imported lines, and possible transfers between
      your own accounts (card payments, savings moves).

**Pass:** no transaction appears twice after either fetch; lines already imported from Actual
are offered as matches, not added again; nothing is marked Reviewed or categorized without a
tap; linked transfers spend the card's Card Payment Category.

**Write down (counts only):** lines fetched, matches offered, duplicates seen.

## 5. A week of Review

Use Budget for new spending for about a week, alongside Actual.

- [ ] Review every new line: categories, a few splits, a few Business Tags (with a recipient on
      a gift line).
- [ ] Try the hint chip, edit a reviewed line, and revert one change from history.
- [ ] Optional: try `Settings › Store item names` with an Amazon, Walmart or AliExpress order export, or a Gmail Takeout .mbox of order emails.
- [ ] At the end of the week, compare account balances and Available with Actual again (step 3).

**Pass:** the Review queue empties by hand only; balances still match Actual after the week.

## 6. Encrypted Drive sync and the Mac

- [ ] On the phone: `Settings › Encrypted sync`, sign in to Google, turn it on. Write the
      Recovery phrase down on paper (`Settings › Recovery phrase`); never photograph it.
- [ ] On the phone: `Settings › Encrypted sync › Pair a device` shows a pairing code.
- [ ] On the Mac: install the latest release, choose `Join a device's budget` (or the welcome
      screen's join option) and paste the pairing code from the phone.
- [ ] Make one change on each device and check it shows on the other after a sync.

**Pass:** the Mac shows the same balances and Available as the phone; changes go both ways;
nothing doubles.

## 7. File what broke

- [ ] One issue per problem, with the bug form, made-up numbers only.
- [ ] Tick the matching box on issue 5 when a step passes, or link the bug when it doesn't.

When every step passes, the switch from Actual can go ahead.
