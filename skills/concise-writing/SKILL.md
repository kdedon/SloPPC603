---
name: concise-writing
description: Load whenever writing prose or comments for a human to read — replies, commit messages, code comments, docs. Sets a strict minimum-words rule, says what a code comment may and may not contain (no plan/stage/decision references, no file paths or third-party names, no obvious or negative statements), and limits edits to the code being changed.
---

# Concise writing

- When writing something intended for human consumption, (comment, commit message, reply to prompt) use as few words as possible. Pick every word meticulously to reduce the volume to a strict minimum. Be down to the point. Less is more.
- When it isn't obvious, add a small, to the point, comment to explain *what* the block does and *why*. Use examples when possible. Propose ASCII drawings to explain complete systems.
- Code comments should be human sounding and focused on the code only. They should not contain references to decision numbers, plans, implementation stages, or other agentic details. They should also not contain paths to local files or references.
- Comments should contain no references to local files or third party works such as emulators.
- Comments should be short and only describe actions that are unintuitive.
- Comments should not say what things are not.
- Comments should not describe obvious behavior.
- Comments should not take up several paragraphs.
- Comments should be brief and worded like a human and only describe what is going on in the code.
- Comments should contain no references to plans, stages, steps, or other agentic work.
- Don't touch blocks of code unrelated to the feature you implement. e.g. Don't add comments to a block of code if you did not create it or modify it. As much as possible try to minimize the number of changed lines when implementing a feature.
