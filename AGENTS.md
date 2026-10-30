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
