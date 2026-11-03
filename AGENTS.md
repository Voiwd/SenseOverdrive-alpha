# Project context

This is a multiplayer horror game being built in Godot by a solo developer.

When helping with this project:

- Focus primarily on programming, code review, and architecture. Art work is rare; only take it on when requested or needed for a specific task.
- Keep the solo-dev workload in mind: prefer manageable, incremental changes and practical scope.
- Avoid unnecessary architecture, tooling, or maintenance burden.
- Treat horror, psychological tension, body modification, and the hostile machine as the core creative direction.
- The game is early-stage. Distinguish implemented features from ideas in the Obsidian vault, and don't assume planned systems already exist.

# Debug and iteration

- Always provide a practical way to quickly test and adjust each feature at runtime, without requiring the developer to play through the game or reproduce normal player actions to reach it.
- Choose the lightest useful approach for the feature, such as an isolated test scene, debug controls, adjustable parameters, or a direct way to trigger its states. Make the controls and how to access them clear when delivering the work.
- Keep debugging tools proportionate to the task and the solo developer's workload; reuse existing tools when they fit instead of building unnecessary infrastructure.
- Export feature parameters that the developer may need to tune, and make their changes effective at runtime through the Inspector or the lightest suitable debug controls. The developer handles the final tuning; do not require source edits for routine adjustments.
- Document each exported variable and control when writing code, explaining what it changes and, where useful, its units, range, and the effect of increasing or decreasing it. For GDScript Inspector properties, use a `##` documentation comment immediately before the declaration so the description appears in the Inspector tooltip. Keep descriptions concise and useful for tuning.

# Linear tasks, version control, and integration

- Work on only one task at a time for this project. Before starting any new task, whether selected autonomously or requested by the user, check Linear for work in progress and inspect active project chats and relevant branches/PRs for ongoing implementation or integration. If another task is in development or awaiting integration, alert the user with its identifier/link and do not start the new task concurrently; ask for an explicit change of priority if needed. Recheck immediately before claiming a task to avoid overlapping runs.
- Keep `main` as the stable branch and use the persistent `develop` branch for all development tasks. Select `develop` before making task changes; do not create a new feature branch for each task. Continue working on only one task at a time.
- Before integration, review and commit all project changes made for the task, including code, scenes, resources, assets, configuration, documentation, additions, moves, and deletions. Check tracked and untracked files so no required changes are left unversioned. Preserve pre-existing or unrelated work and keep it separate from the task's commits.
- When the task is complete, push `develop` and open or update a pull request from `develop` to `main`. Link the Linear issue and describe the changes, validation performed, and quick runtime test controls when applicable. Deliver the PR link; do not treat a local commit or a direct merge as a substitute for the PR. Keep `develop` after integration so it can be reused for the next task, and keep incomplete or unvalidated work out of `main`.
- Take responsibility for anticipating branch conflicts: inspect the working tree, current remote integration branch, and relevant active branches or PRs before implementation, then check again before opening the PR and before integration. Identify overlapping files and dependencies early and choose an integration order that reduces conflicts.
- Keep `develop` up to date with `main` as needed, resolve conflicts while preserving the intent of both changes, and repeat the affected validation after resolution. Do not overwrite unrelated work or force-push shared branches. Before deleting an old feature branch, verify that its changes are preserved in `main` or `develop`, accounting for squash merges. If a conflict requires a product decision that cannot be inferred safely, explain the specific conflict and request that decision before integration.
- Report unresolved conflicts or integration blockers promptly, with the affected branches/files and the next action required. Do not declare the task ready for integration while known conflicts or required checks remain unresolved.
