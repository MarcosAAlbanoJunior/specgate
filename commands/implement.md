---
description: Implement an approved spec test-first, with a deterministic gate (max 3 fix attempts) and a single-reviewer loop (max 2 rounds). Never commits.
argument-hint: <spec id>
model: sonnet
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh:*), Bash(git diff HEAD > specs/.review.diff), Bash(git diff:*), Bash(git status:*), Bash(git ls-files:*), Bash(rm -f specs/.implementing:*), Bash(rm -f specs/.implementing specs/.active specs/.gate-fails specs/.review.diff)
---

You are running the **implement** step of specgate for spec id: `$ARGUMENTS`

## Quota rules (non-negotiable)

- Everything here runs on Sonnet. No Opus.
- Subagents run one at a time, never in parallel, always in the **foreground** (`run_in_background: false`): wait for each result before continuing.
- Never explore the repo beyond the files listed in the spec (plus what those files directly import or are tested by, when strictly needed).
- Gate failures: pass only the relevant error output forward, never whole logs.
- **Never run `git commit`, `git push`, `git merge`, `git add` or any other history/index-changing command.** Leave all changes in the working tree for the human.

## Step 0. Preconditions

1. If `specs/$ARGUMENTS.md` does not exist, **abort** with: `specs/$ARGUMENTS.md not found. Run /specgate:spec first.` Do nothing else.
2. Read the spec once. Its **Affected files** list is your boundary; its numbered **Acceptance criteria** are the contract.
3. Create the marker `specs/.implementing` (empty file) and make sure `specs/.active` contains `$ARGUMENTS`. The Stop hook enforces the gate only while both markers exist.

## Step A. Tests first

Launch the `test-writer` subagent (Sonnet) with the spec path. It writes tests from the acceptance criteria only. Do not write tests yourself. Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh` once: it is expected to be **red** (this run does not count toward the 3 attempts). If it is already green, the tests do not exercise anything new: tell the human before continuing. If the subagent reports an uncoverable criterion, note it for the final summary.

## Step B. Implementation (sequential)

Implement the criteria in order, touching only files listed in the spec (and the test files from step A). If you need to touch any other file, **stop and ask the human**, explaining why; continue only on approval.

## Step C. Gate (max 3 attempts)

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh`.

- Green (`GATE PASSED`): go to step D.
- Red: read only the printed error output, fix the cause, and run the gate again. Do not re-read the whole codebase, and do not weaken or delete tests to get green.
- After **3 failed gate runs in total**, stop. Report to the human the last error output, what you tried, and your best hypothesis. Run `rm -f specs/.implementing` so the Stop hook does not force more attempts, and leave `specs/.active` in place. Do not proceed to review.

## Step D. Review (only with a green gate; max 2 rounds)

For each round:

1. Save the change for the reviewer, as separate simple commands: run `git diff HEAD > specs/.review.diff`, then run `git ls-files --others --exclude-standard`. If that lists any new files (ignore anything under `specs/`), add one line `UNTRACKED (read these files in full): <paths>` at the end of `specs/.review.diff` using the Edit tool.
2. Launch the `reviewer` subagent (Sonnet, read-only) with the paths `specs/$ARGUMENTS.md` and `specs/.review.diff`.
3. If there is **no `blocker`**, the review is done. Keep the `major`/`minor` findings for the summary; do not fix them unless trivial and inside the spec's files.
4. If there is a `blocker`: fix it, run the gate again (same rules as step C; the 3-attempt budget is shared across the whole run), then start the next round.
5. After round 2, if a `blocker` remains, stop and leave it for the human.

## Step E. Final summary

Present:

- Acceptance criteria met, **by number**, with the test that proves each (and any criterion not met or not covered).
- Review findings (severity, `file:line`, status: fixed / open).
- Rounds used: gate attempts (of 3) and review rounds (of 2).
- What needs a human decision (open majors, scope questions, anything you were unsure about).

Then remove the markers and temp files: `rm -f specs/.implementing specs/.active specs/.gate-fails specs/.review.diff`. If you stopped early in step C or D because of a failure or an open blocker, remove only `specs/.implementing` and keep `specs/.active`.

End by reminding the human that nothing was committed, pushed or merged.
