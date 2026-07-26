# Cheat Sheet: Interview Response Framework

Structure **every** scenario-based answer this way — say the structure out loud even when confident, it demonstrates operational discipline, not just knowledge.

1. **Clarify the impact and scope** — what's broken, who/what is affected right now.
2. **Protect production before making changes** — stop the bleeding without causing a second incident.
3. **Gather evidence** — logs, state, plan output, cloud console, CI/CD history.
4. **Inspect configuration, plan, state, provider, and cloud reality** — find where these four views diverge.
5. **Identify the root cause** — not just the symptom.
6. **Select the safest remediation** — prefer reversible, low-blast-radius actions first.
7. **Validate using plan and independent cloud checks** — never trust one source of truth.
8. **Define rollback or recovery** — know how you'd undo it before you act.
9. **Add preventive controls** — policy, CI gate, module contract, or documentation change.
10. **Document the operational decision** — for the next engineer and for audit.

## Phrases that signal you're using this framework (use them)
- "First, let me clarify the actual blast radius before touching anything..."
- "I wouldn't apply this yet — let me check state against cloud reality first..."
- "The root cause isn't X, it's actually Y, because..."
- "Here's how I'd validate this worked, independent of Terraform's own output..."
- "The structural fix here is X, not a reminder to be more careful..."

## Phrases that are red flags if *you* say them
- "Just re-apply and see what happens."
- "That should be fine, Terraform usually handles it."
- "We'd just tell people to be more careful next time."
- "I'd force-unlock it since it's probably fine."

## The recurring theme across every senior-level answer in this repository
**A structural/technical fix beats a process reminder, every time.** If your answer to "how do you prevent this" is "we'd tell people to be careful" or "we'd add a reminder," you haven't found the real fix yet — look for the guardrail, the CI gate, the architectural change that makes the mistake *impossible*, not just less likely.

## Score yourself honestly
- **1-2**: You gave a definition or a happy-path description with no failure handling.
- **3 (Senior bar)**: You covered validation, rollback, and understood state/security implications.
- **4 (Lead bar)**: You covered architecture trade-offs, team governance, anticipated failure modes.
- **5 (Staff/Architect bar)**: You connected the technical decision to business risk, blast radius, cost, and organizational ownership.

See [`docs/interview-cheatsheet.md`](../docs/interview-cheatsheet.md) for the topic-to-question map and the "five questions that separate Senior from Staff." See [`mock-interviews/`](../mock-interviews/) to rehearse this framework under timed, question-by-question conditions.
