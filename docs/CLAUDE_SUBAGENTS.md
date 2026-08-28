# Claude Code subagents in this project

Claude Code supports built-in and custom subagents without another download.
Use `/agents` inside a Claude terminal to inspect, create, edit or remove them.
Choose **Project** scope when the agent should travel with this repository;
Claude stores project agents as Markdown files under `.claude/agents/`.

For this multi-provider project, leave a custom agent's model set to
`inherit` unless one exact provider route has been proved for subagent calls.
That keeps the subagent on the model/route selected for the parent Claude
terminal. Hard-coding `opus`, `sonnet` or `haiku` may ask the router for a
different model than the selected Codex/Google/custom provider exposes.

Good first uses are bounded read-only exploration, a focused test runner and
an independent reviewer. Give each agent a narrow description, only the tools
it needs and a finite `maxTurns`. Subagents have separate context and consume
provider usage; they reduce main-context noise, not provider billing.

Do not enable experimental agent teams by default. Teams create several full
Claude sessions and can consume substantially more usage. Revisit them only as
a separate owner-approved pilot with a proved provider route and budget.

Official references:

- <https://code.claude.com/docs/en/sub-agents>
- <https://code.claude.com/docs/en/agents>
- <https://code.claude.com/docs/en/agent-teams>
