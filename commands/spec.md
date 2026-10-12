---
description: Write a spec (context, affected files, numbered acceptance criteria, scope, risks) for a ticket or description, then stop for human approval. Implements nothing.
argument-hint: <ticket or description>
model: opus
allowed-tools: Read, Grep, Glob, Write
---

You are running the **spec** step of specgate. Input: `$ARGUMENTS`

## Quota rules (non-negotiable)

- This is the only step that uses Opus. Do all the thinking here so the next step can run on Sonnet.
- No subagents, nothing in parallel.
- Read only what the spec needs: the files directly related to the ticket plus their immediate tests. Do not survey the repo.
- You write exactly two things: `specs/<id>.md` and `specs/.active`. You do not touch any other file and you do not implement anything.

## Steps

1. Pick an `<id>`: the ticket key if the input contains one (e.g. `PROJ-123`), otherwise a kebab-case slug of at most 40 characters derived from the description. Use it for everything below.
2. If the input is too vague to write testable criteria, ask the human at most one short round of questions before writing.
3. Read the minimum needed from the repo.
4. Create `specs/` if missing and write `specs/<id>.md` with exactly these sections:
   - **Context**: what and why, in a few sentences.
   - **Affected files**: a list of real paths, each marked `modify` or `create`. This list is the implementation boundary.
   - **Acceptance criteria**: numbered (`1.`, `2.`, ...), each one a single observable, testable statement (input/state, action, expected result). No vague words like "properly" or "fast".
   - **Out of scope**: what will deliberately not be done.
   - **Risks**: security, data, compatibility and edge-case risks, and open questions.
5. Write `specs/.active` containing only `<id>`, then confirm both files exist before reporting them as ready.
6. If `specs/` is not in the project's `.gitignore`, tell the human to add it: the spec lives and dies locally.

## Stop here

End with a short summary of the spec and exactly this request:

> Spec `specs/<id>.md` is ready. Review and edit it, then approve. Suggested next steps: run `/clear`, then `/specgate:implement <id>`.

Then **stop and wait for the human**. Do not start implementing, do not write tests, do not edit source files.
