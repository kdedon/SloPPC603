---
name: concise-writing
description: Load whenever writing prose or comments for a human to read — replies, commit messages, code comments, docs. Sets a strict minimum-words rule, says what a code comment may and may not contain (no plan/stage/decision references, no file paths or third-party names, no obvious or negative statements), and limits edits to the code being changed.
---

# Concise writing

Applies to comments, commit messages, docs and replies.

## Rules

- Use as few words as possible. Pick each word deliberately; less is more.
- When a block is not obvious, add a short comment saying *what* it does and *why*.
  Use examples where they help; propose ASCII drawings for whole systems.
- Comments describe only the code, briefly and in a human voice: unintuitive behavior,
  never obvious behavior, never what the code is not, never several paragraphs.
- Comments carry no references to plans, stages, steps, decision numbers or other agentic work.
- Comments carry no local file paths and no references to third-party works such as emulators.
- Leave unrelated code alone: don't add comments to blocks you did not create or modify,
  and keep the changed-line count minimal.

## Checklist

- [ ] Every sentence earns its place; nothing restates the code or the obvious.
- [ ] Comments explain what and why for non-obvious code only, in a few lines.
- [ ] No plan, stage, decision or agent references; no local paths or third-party names.
- [ ] No negative statements about what the code is not.
- [ ] Only lines belonging to the change were touched.
