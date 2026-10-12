# specgate

A spec-driven workflow for [Claude Code](https://code.claude.com), built to get reliable results on the **Pro plan's limited quota**.

Accuracy comes from **deterministic gates and human approval**, not from piling on critic agents.

## The problem

Multi-agent pipelines (planner, coder, tester, three reviewers, a supervisor...) are impressive and expensive. Every agent re-reads the repo, re-explains the task and burns tokens, and on a Pro plan a single feature can eat the whole window.

## The thesis

The "critique and send back" loops are worth keeping. But each critic should cost (almost) nothing:

| Critic | Cost |
| --- | --- |
| Build + tests + lint + coverage (`scripts/gate.sh`) | zero tokens, deterministic |
| Stop hook that refuses to finish while the gate is red | zero tokens |
| One `reviewer` subagent applying one checklist with six lenses | one cheap Sonnet call per round |
| You, approving the spec before any code is written | the only expensive thinking, done once, with Opus |

Opus is used once (writing the spec). Everything else runs on Sonnet, sequentially, touching only the files named in the spec.

## Flow

```
 /specgate:spec <ticket>                (Opus)
        |
        v
 specs/<id>.md  +  specs/.active
        |
        v
 [ HUMAN APPROVES / EDITS SPEC ]  <----------------------------+
        |                                                      |
   /clear  (the spec is the handoff)                           |
        |                                                      |
 /specgate:implement <id>               (Sonnet)               |
        |                                                      |
        v                                                      |
 A. test-writer subagent: tests from criteria (must fail)      |
        |                                                      |
        v                                                      |
 B. implement, only files listed in the spec                   |
        |            (needs another file? stop and ask) -------+
        v
 C. gate.sh  --red-->  fix from error output only --+
        |  ^                                         |
        |  +------------ sent back, max 3 ----------+
        |        (still red after 3: stop, report to human)
      green
        |
        v
 D. reviewer subagent (read-only, diff + spec)
        |  blocker?  --yes-->  fix, gate again, review again
        |                      (sent back, max 2 rounds)
        no
        v
 E. summary: criteria met (by number), findings, rounds used,
    open decisions.  Removes specs/.active.  NEVER commits.
```

A Stop hook backs up step C: while `specs/.active` and `specs/.implementing` exist, Claude cannot finish a turn with a red gate.

## Install

```
/plugin marketplace add MarcosAAlbanoJunior/specgate
/plugin install specgate@specgate
```

Then run `/reload-plugins` (or restart the session). Requirements: `bash`, and your project's own toolchain (Maven, Gradle, npm/pnpm or Go). `jq` is optional.

Recommended in the **target project**: add `specs/` to `.gitignore`. A spec lives and dies locally.

## Usage

Plugin commands are namespaced: `/specgate:spec` and `/specgate:implement`.

End to end example in a Maven project:

```
> /specgate:spec PROJ-42 add Calculator.divide(int, int); a zero divisor must throw IllegalArgumentException
```

Claude (Opus) reads the relevant files, writes `specs/PROJ-42.md` (context, affected files, numbered acceptance criteria, out of scope, risks), creates `specs/.active`, and stops. Open the spec, edit it, make sure the criteria are what you want. Then:

```
> /clear
> /specgate:implement PROJ-42
```

Claude (Sonnet) writes the tests, implements, runs the gate (fixing up to 3 times), calls the reviewer (up to 2 rounds) and prints a summary such as:

```
Acceptance criteria met: 1 (divideReturnsExactQuotient), 2 (divideTruncates...), 3 (divideByZero...)
Review findings: none (0 blocker, 0 major, 0 minor)
Rounds used: gate 1/3, review 1/2
Needs human decision: nothing
Nothing was committed, pushed or merged.
```

You review the working tree and commit yourself. `examples/demo-maven/` is a tiny project you can try this on (it needs a git repo with at least one commit, because the reviewer reads `git diff HEAD`).

## Gate configuration

`gate.sh` auto-detects the stack (first match wins): Maven (`pom.xml`), Gradle (`build.gradle[.kts]`), npm/pnpm (`package.json`, pnpm if `pnpm-lock.yaml`), Go (`go.mod`). It prefers `./mvnw` and `./gradlew` when present.

| Stack | Build/test | Lint |
| --- | --- | --- |
| Maven | `mvn -q -B verify` | none (set `LINT_CMD`) |
| Gradle | `gradle -q build` | none (set `LINT_CMD`) |
| npm/pnpm | `build` script (if any), `test` script | `lint` script (if any) |
| Go | `go build ./...`, `go test ./...` | `go vet ./...` |

Create `specgate.config` in the project root to override (see `examples/specgate.config.example`). It is a plain shell file, sourced by the gate:

```sh
GATE_CMD="./mvnw -q -B verify"      # replaces auto-detected build + test
LINT_CMD="./mvnw -q -B checkstyle:check"
COVERAGE_MIN=80                      # minimum line coverage, percent
```

`COVERAGE_MIN` reads a JaCoCo CSV (Maven/Gradle; the jacoco plugin must be configured), Go cover output, or `coverage/coverage-summary.json` (npm). If the report is missing, the gate fails with a clear message instead of passing silently.

On failure the gate exits non-zero and prints only the relevant error lines (capped at 40), so the fix loop stays cheap.

## Limitations

- **A command is an instruction, not a script.** `spec.md` and `implement.md` are prompts; the model can deviate. What must be enforced lives in code: the gate script and the Stop hook. The 3-attempt and 2-round limits, the "never commit" rule and the scope boundary are instructions, not guarantees.
- **The Stop hook is a safety net, not the main loop.** It blocks a red finish at most 3 times, then lets go and tells you, so a stuck run cannot loop forever (Claude Code also caps consecutive stop-hook continuations).
- **The hook arms only after `implement` starts.** It needs both `specs/.active` and `specs/.implementing`; otherwise the gate would fire right after `spec`, while the repo is legitimately red. Normal Claude Code use without those files is untouched.
- **`spec` is not forced into plan mode.** Commands cannot set a permission mode. The step stays read-only by instruction and writes only `specs/`. You can start the session in plan mode yourself if you want a harder guarantee, at the cost of extra approval prompts.
- **Tool grants are broad.** Scoped rules such as `Write(specs/**)` did not match in headless tests, so `spec` is granted plain `Write` and limited by instruction only.
- **Headless runs (`claude -p`)**: subagents must run in the foreground or the command's tool grants are lost when the turn resumes; the commands say so explicitly.
- `specgate.config` is sourced as shell, so it runs with your privileges. Only use configs you trust.
- Review sees only the diff and the spec, by design. It will not catch problems that need wider repo knowledge.

## License

MIT, see [LICENSE](LICENSE).
