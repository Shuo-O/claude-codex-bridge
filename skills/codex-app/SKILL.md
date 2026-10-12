---
name: codex-app
description: Delegate a coding task to the Codex desktop app (macOS) in the same project, then review its result. Use when the user asks to hand work to Codex, "let Codex do it", or wants Claude as reviewer and Codex as implementer. Starts a real thread in the Codex app (visible there immediately) and reads back only Codex's final message, so it costs few tokens.
---

# Delegate to the Codex app

`codex-app-send` opens a new thread in the Codex desktop app for a project
directory, submits a prompt, and can wait for the turn to finish, printing only
Codex's final message. `codex-app-result` reads that message later.

## Before sending

1. Check `command -v codex-app-send`. If missing, tell the user to install
   https://github.com/Shuo-O/claude-codex-bridge and stop.
2. Run `git status --short` in the project. Uncommitted changes will be seen
   (and possibly edited) by Codex, so mention them in the task.
3. Do not edit files yourself while Codex is working on the same checkout.

## Write the task

Put the task in a file in your scratchpad/temp directory, not in the project.
A good task is self-contained, since Codex does not see this conversation:

- Goal and acceptance criteria
- Files or areas to change, and what to leave alone
- Commands to verify (tests, lint, build)
- Constraints: e.g. do not commit or push unless asked
- Ask for a short final summary: files changed, commands run, results, open risks

## Send and wait

```bash
codex-app-send --wait 900 /abs/path/to/project @/path/to/task.md
```

Run it in the background when the task may take long. Output:

```
SENT <tag>
SESSION <path to rollout .jsonl>
----- FINAL -----
<Codex's final message>
```

Exit code 2 means the wait timed out; the thread keeps running in the app.
Later, read the result with:

```bash
codex-app-result --wait 600 <SESSION path>
```

Exit code 1 with an Accessibility message means macOS blocked the keystroke:
ask the user to allow the app running Claude Code under System Settings >
Privacy & Security > Accessibility. Do not try to change that setting yourself.

## Review

Do not trust the summary alone. Review `git diff` (and `git log` if Codex
committed), run the verification commands, and report findings to the user.
To send follow-up fixes, start a new thread with another `codex-app-send`
that states what to change and why.

## Token use

Never read the full rollout .jsonl; it contains Codex's whole transcript.
Use only the final message and the diff.
