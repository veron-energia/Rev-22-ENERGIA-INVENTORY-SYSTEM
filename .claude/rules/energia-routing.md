# Energia task routing

In the main conversation, review each new instruction and start the requested work immediately within the active permissions. This rule applies to the coordinator. A delegated worker should complete its own assignment and return to the coordinator.

Make a brief routing decision based on the consequence of an error, the uncertainty, the amount of work and the deadline. Answer tiny follow-ups directly when the answer is already in context. For delegated work, use the Agent tool with the matching named project agent and its configured model and effort.

- `energia-quick` uses Haiku 5.5 at Low for bounded lookups, extractions, copy rewrites and mechanical text edits.
- `energia-build` uses Sonnet 5.5 at Medium for ordinary React, TypeScript and Supabase changes with clear acceptance criteria.
- `energia-critical` uses Opus 5.5 at High for work affecting money, stock, permissions or data integrity. The main Opus session can own this work directly when it already has the relevant context.
- `energia-investigate` uses Fable 5.2 at High for a difficult, unresolved question that spans components or needs sustained reasoning. Give it one specific question and the evidence already collected. If Fable reaches its included limit or would require paid credits, continue in Opus if its included capacity is available.

Use one worker by default. Run two in parallel when they can make independent progress. For React and Supabase, agree on the data contract first, give each worker separate files, and sequence any dependent edits. Give each worker only its goal, relevant paths, constraints and expected check. Carry forward prior findings when escalating.

Increase a worker's effort only for a concrete reason, such as an ambiguous invariant or a failed verification. Use the per-invocation effort setting when needed. Extra is `xhigh`. Urgency can shorten the scope or justify independent parallel work. Keep checks for high-impact behavior.

Opus owns the final answer. Review worker results together, inspect relevant changes and verify the affected behavior across boundaries. For substantive delegated work, give one short line naming the workers used and their assigned efforts, plus the outcome of the checks. Use included subscription capacity for this workflow. If work is blocked, report what remains.
