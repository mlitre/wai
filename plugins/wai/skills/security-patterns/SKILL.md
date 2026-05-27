---
name: security-patterns
description: Reference list of high-signal security patterns to warn on (or block) when editing files. Use when reviewing code, writing a security hook, drafting `CLAUDE.md` security rules, or hunting for unsafe constructs. Pairs with `writing-native-hooks` (install as a `PreToolUse` hook) and the `code-reviewer` / `silent-failure-hunter` agents.
inspired-by: anthropic/security-guidance
---

# Security Patterns

Pattern reference distilled from Anthropic's `security-guidance` plugin. wai does not vendor the enforcement engine (Python). Two ways to use these:

1. **Manual review**, keep this list handy when reviewing PRs, or feed it to `code-reviewer` / `silent-failure-hunter`.
2. **Native hook install**, wire each pattern as a `PreToolUse` hook in `settings.json` using `writing-native-hooks`. The bottom of this doc gives a ready-to-paste recipe.

Each pattern has: the substring or path trigger, why it matters, the safe alternative, and the message to surface.

## Patterns

### 1. GitHub Actions workflow injection

**Trigger:** edits under `.github/workflows/*.{yml,yaml}`.

**Why:** untrusted GitHub event fields (issue titles, PR descriptions, commit messages) interpolated into `run:` blocks become shell injection.

**Unsafe:**

```yaml
run: echo "${{ github.event.issue.title }}"
```

**Safe:**

```yaml
env:
  TITLE: ${{ github.event.issue.title }}
run: echo "$TITLE"
```

**Risky fields to watch for** (any of these going into `run:` directly is a red flag):

- `github.event.issue.body`, `github.event.issue.title`
- `github.event.pull_request.title`, `github.event.pull_request.body`
- `github.event.pull_request.head.ref`, `.head.label`, `.head.repo.default_branch`
- `github.event.comment.body`, `github.event.review.body`, `github.event.review_comment.body`
- `github.event.commits.*.message`, `github.event.head_commit.message`
- `github.event.head_commit.author.email`, `.author.name`
- `github.event.commits.*.author.email`, `.author.name`
- `github.event.pages.*.page_name`
- `github.head_ref`

**Reference:** [GitHub blog: workflow injection](https://github.blog/security/vulnerability-research/how-to-catch-github-actions-workflow-injections-before-attackers-do/).

### 2. Node child-process shell execution

**Trigger:** substrings `child_process.exec`, `execSync(`, and any bare exec call with shell-templated input.

**Why:** shell injection, concatenating user input into the command string.

**Unsafe:**

```js
exec(`run ${userInput}`)
```

**Safe:**

```js
import { execFile } from 'node:child_process'
execFile('run', [userInput])
```

Prefer `execFile` over `exec`. It bypasses the shell entirely. Many projects ship a helper (`execFileNoThrow`, `safeExec`), use it if one exists.

### 3. Dynamic Function constructor

**Trigger:** substring `new Function`.

**Why:** runtime code construction from strings, equivalent to dynamic-eval for injection purposes.

**Safe alternative:** specific parsers (`JSON.parse`), data-driven dispatch tables, or static lookup maps. Only justified when arbitrary code evaluation is genuinely the requirement (sandboxes, scripting hosts).

### 4. eval()

**Trigger:** substring `eval(`.

**Why:** arbitrary code execution from a string, top-tier injection risk.

**Safe:** `JSON.parse` for data, dispatch tables for logic. Only justified when arbitrary code execution is the actual feature.

### 5. React dangerouslySetInnerHTML

**Trigger:** substring `dangerouslySetInnerHTML`.

**Why:** XSS if the content isn't sanitized.

**Safe:** sanitize via DOMPurify (or equivalent) before passing in. Better: render via JSX where possible.

### 6. document.write

**Trigger:** substring `document.write`.

**Why:** XSS vector and a perf hazard. Modern browsers actively warn on it.

**Safe:** DOM manipulation, `createElement` + `appendChild`, or framework rendering.

### 7. .innerHTML assignment

**Trigger:** substrings `.innerHTML =`, `.innerHTML=`.

**Why:** XSS if content is untrusted.

**Safe:** `textContent` for plain text. If HTML is genuinely needed, sanitize via DOMPurify first.

### 8. Python pickle on untrusted data

**Trigger:** substring `pickle`.

**Why:** `pickle.loads` on untrusted bytes is arbitrary-code execution by design.

**Safe:** JSON or `msgpack` for cross-trust serialization. Use `pickle` only for explicitly trusted, internal-only data.

### 9. os.system

**Trigger:** substrings `os.system`, `from os import system`.

**Why:** shell injection, same class as Node's `exec`.

**Safe:** `subprocess.run([...], shell=False)` with a list of arguments. Never interpolate user input into the command string.

## Wiring as a native PreToolUse hook

Add this to `~/.claude/settings.json` (or `.claude/settings.json` for project scope). Single hook script reads stdin, checks every pattern, prints a reminder + exit 2 to block.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/security-patterns.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Then `~/.claude/hooks/security-patterns.sh`:

```sh
#!/usr/bin/env bash
# Read tool input from stdin, surface a security warning if any pattern matches,
# exit 2 to block the tool call. Exit 0 to allow.

input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")
path=$(jq -r '.tool_input.file_path // empty' <<<"$input")

case "$tool" in
  Write)     content=$(jq -r '.tool_input.content // empty' <<<"$input") ;;
  Edit)      content=$(jq -r '.tool_input.new_string // empty' <<<"$input") ;;
  MultiEdit) content=$(jq -r '[.tool_input.edits[].new_string] | join(" ")' <<<"$input") ;;
  *) exit 0 ;;
esac

block() { echo "$1" >&2; exit 2; }

# Path-based: GitHub Actions workflow
if [[ "$path" == .github/workflows/*.yml || "$path" == .github/workflows/*.yaml ]]; then
  block "GitHub Actions workflow detected. Verify no untrusted github.event.* fields are interpolated into run: blocks. Use env: + \$VAR instead."
fi

# Content-based patterns
patterns=(
  "child_process.exec|child_process.exec, risk of shell injection. Prefer execFile with an args array."
  "execSync(|execSync, risk of shell injection. Prefer execFileSync with an args array."
  "new Function|new Function() runs arbitrary code from a string. Use a parser, dispatch table, or static lookup unless arbitrary-code evaluation is the actual requirement."
  "eval(|eval() runs arbitrary code. Use JSON.parse for data, dispatch tables for logic."
  "dangerouslySetInnerHTML|dangerouslySetInnerHTML, XSS risk. Sanitize via DOMPurify or render via JSX."
  "document.write|document.write, XSS vector and perf hazard. Use createElement + appendChild."
  ".innerHTML =|.innerHTML=, XSS risk on untrusted content. Use textContent, or sanitize via DOMPurify."
  "pickle|pickle on untrusted bytes is arbitrary-code execution. Use JSON or msgpack across trust boundaries."
  "os.system|os.system, shell injection risk. Use subprocess.run([...], shell=False)."
)

for entry in "${patterns[@]}"; do
  needle="${entry%%|*}"
  msg="${entry#*|}"
  if [[ "$content" == *"$needle"* ]]; then
    block "$msg"
  fi
done

exit 0
```

Make it executable:

```sh
chmod +x ~/.claude/hooks/security-patterns.sh
```

That gives the same enforcement as the `security-guidance` plugin in pure bash + jq, no Python.

## Notes

- **Block vs. warn.** The script above blocks (`exit 2`). To warn-but-allow, replace `block "$msg"` with `echo "$msg" >&2` and remove the exit, then `exit 0` at the end.
- **Once-per-session.** The original Python hook deduped by `file_path + rule_name`. The bash version above fires every time. If you want session-scoped dedup, persist state in `$CLAUDE_SESSION_DIR` or `/tmp/security-warnings-$$.log` keyed on a hash.
- **False positives.** Documentation files often contain these strings literally. If the security hook is blocking `Write` calls that are creating docs (this skill itself almost tripped on it during porting), either narrow the `matcher` to source-file extensions, or add an early-exit on `path` containing `docs/`, `SKILL.md`, `.md`.
- **Patterns are a starting point.** Add project-specific ones (e.g. `dangerouslyAllowBrowser: true`, raw SQL string concatenation, `crypto.createCipher` without algorithm).

## Pairs with

- [`writing-native-hooks`](../writing-native-hooks/SKILL.md), for the hook plumbing.
- `code-reviewer` agent, feed this list as "things to check" when reviewing diffs.
- `silent-failure-hunter` agent, many of these patterns hide errors too (exec swallowing stderr, etc.).
