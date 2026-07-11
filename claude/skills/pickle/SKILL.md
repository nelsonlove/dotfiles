---
name: pickle
description: Use when creating, inspecting, responding to, or integrating Pickle requests. Pickle is a local mdbase-backed human approval inbox for agents and Tickle jobs, with typed markdown requests/responses, structured JSON responses, Android notifications over Tailscale, and CLI commands such as pickle ask, inbox, show, respond, response, wait, events, and watch.
---

# Pickle

Pickle is a personal agent inbox for structured requests, approvals,
annotations, and automation handoffs. Use it when an agent or local automation
needs a durable human decision instead of guessing or blocking in chat.

## CLI

Prefer the installed CLI:

```bash
pickle --help
```

Common commands:

```bash
pickle ask --source agent --kind approval --title "Approve action?" --message "Question..."
pickle ask --title "Review output?" --message "Please inspect the attached files." --attach summary.md --attach screenshot.png
pickle message --title "FYI" --message "No response beyond acknowledgement is needed."
pickle inbox --status pending --json
pickle show --json <request-id>
pickle respond --json '{"decision":"approve","comment":"Looks right."}' <request-id>
pickle response <request-id>
pickle events --after 0
pickle token
```

Use `--collection <name-or-path>` when the target collection is not the
configured default. On this machine, the default collection is `pickle`, backed
by the Obsidian vault folder `00-09 System/01 Capture & triage/01.10 Agent inbox`.

## mdbase Contract

Pickle collections are mdbase collections. Request files live under
`requests/`; response files live under `responses/`; attachments live under
`attachments/<request-id>/`.

The link from a response file to a request file is the source of truth for
request lifecycle:

- no linked response: `pending`
- one linked response: `answered`
- more than one linked response: `conflict`
- `status: cancelled` on the request: `cancelled`

Do not rely on or write `status: answered` in request frontmatter.

`message` is the concise human-facing prompt. Use the body for longer context.

## Approval Pattern

1. Create one Pickle request with a concise title, clear message, relevant links
   or attachments, and metadata pointing back to the calling workflow.
2. Store the Pickle request id in the upstream system of record so later
   automation can find it again.
3. Prefer asynchronous follow-up automation over blocking a long-running job
   with `pickle wait`, unless the user explicitly wants a synchronous checkpoint.
4. When the response arrives, copy the response into the upstream workflow state
   before acting on it.

Use this response payload for ordinary approve/reject/revise requests:

```json
{
  "decision": "approve",
  "comment": "Looks right."
}
```

For message-style notifications, `pickle message` uses the
`pickle_response_ack` response type.

## Guardrails

- Pickle records human input. The project-specific repo state, ledger task,
  issue sidecar, or workflow store should remain canonical for project work.
- Keep request bodies private and concise. Link to local files when a path is
  enough. Attach small plaintext, Markdown, PNG, JPEG, or WebP artifacts when
  the human needs to inspect the exact captured output from the phone.
- Use `--dedupe-key` when repeated automation checks could ask the same
  question more than once.
- When exposing Pickle beyond localhost, keep it behind Tailscale or another
  private network boundary.
