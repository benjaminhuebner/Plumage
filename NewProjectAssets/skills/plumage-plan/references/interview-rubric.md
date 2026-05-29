# Interview rubric

This reference is loaded by `/plumage-plan` when it is time to conduct the interview. Eight topics in fixed order. After each user reply, restate the understanding in one line, then ask the next question. Write each section into the spec as the interview goes.

The rationale matters more than the rigid order: an interview that follows the letter of the rubric but produces a spec the user cannot act on has failed. Use the *why* to handle cases this rubric does not spell out.

## The eight topics

### 1. Goal — one sentence, the *why*

One sentence describing why this issue exists. Not what it does — *why*.

**Pushback:** "Implement X" is a task, not a goal. Push back. "Users keep losing their drafts when the app crashes" is a goal. "Add autosave to the editor" is a task.

**Why:** The goal is what the next person reading this in six months uses to decide whether the implementation still serves its purpose. A task masquerading as a goal anchors the spec to one solution and hides whether the *problem* was actually solved.

### 2. User-visible behavior — what the user sees, does, gets back

Concrete examples beat abstractions. "When the user types `:` at the start of a line, a slash-command palette opens" beats "Slash commands are easy to access".

**Pushback:** Anything that cannot be observed from outside the system. "Performance is improved" — push for the actual observable: response time, frame rate, perceived smoothness, what.

**Why:** Implementation drift is normal. User-visible behavior is the contract that survives drift.

### 3. Scope: in — bullet list

What is explicitly included. Each bullet is something the implementer will deliver.

### 4. Scope: out — bullet list

What is explicitly excluded. Often more useful than "in" because it stops the implementation from sprawling.

**Pushback:** If the user cannot name anything that is out, that is a smell — either the issue is too big, or the edges have not been considered. Ask "what would be the next obvious feature to add to this, that we are deliberately not doing now?"

**Why:** "Out" prevents scope creep mid-implementation and gives `/plumage-implement` clear stop conditions.

### 5. Technical approach — high-level

Files/modules touched, new types, external interfaces. High-level, not line-by-line.

**Pushback:**

- Cross-check against `PROJECT.md` and `decisions.md`. If the approach conflicts with a **Did** entry or a **Won't** entry, surface it before writing the section. Ask the user: change the issue, change the doc, or split.
- If the user gives two implementation shapes ("we could do X or Y"), ask for a commit. The spec records one approach. The other goes into a `decisions.md` **Won't** entry if the user is willing.

**Why:** Forcing the commitment to one shape during planning is cheap. Forcing it during implementation is expensive.

### 6. Edge cases — what happens when

Error paths, empty states, concurrent access, large inputs, permission failures. Ask "what happens when…" until the realistic failure modes are covered.

**Pushback:** "Handle errors" is not an edge case — push for which specific error and what specifically happens. "Network drops mid-upload" is an edge case. "Something goes wrong" is not.

### 7. Tasks — ordered list of commits

Each task should be one commit, verifiable on its own. Five to fifteen is a reasonable range.

**Pushback:**

- A task that mixes refactor + feature → ask to split. The refactor goes first as its own task; the feature builds on it.
- More than 15 tasks needed? The issue is too big. Propose splitting it and stop the interview.
- A task that cannot be verified without finishing a later task → reorder, or merge them.

**Why:** Per-task commits with green build + tests = trivial bisect, trivial revert. A 12-file mega-commit at the end of a long session is a debugging nightmare two weeks from now.

### 8. Done when — checkboxes that decide whether the spec is finished

Specific and checkable.

- Good: "VoiceOver pass on the new sheet"
- Good: "Existing tests still green; three new tests covering empty/single/many cases"
- Bad: "Accessibility checked" — by whom, against what?
- Bad: "Feels good" — subjective; rewrite.

**Why:** "Done when" is what flips the spec to `waiting-for-review`. If it depends on subjective judgment, the issue never finishes.

## Interview hygiene

- One topic at a time. Do not dump the whole list at once — the user gives faster, sharper answers when the question is narrow.
- After each reply, restate in one line, then ask the next question. The restate catches misunderstanding before it goes into the spec.
- Write into the spec as the interview goes. The spec is the running record. If the session crashes, the partial spec is the resume point — not the agent's memory.
- The user can change earlier answers at any time. Treat the spec as a living document during the interview, frozen only at `approved`.
