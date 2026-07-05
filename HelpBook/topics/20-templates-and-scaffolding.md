---
id: templates-and-scaffolding
swift: templatesAndScaffolding
title: Templates & Scaffolding
icon: doc.text
section: Templates
---
# Templates & Scaffolding

New projects are scaffolded from templates. Three tiers stack, from least to most specific: **Base < Component < Template**. A more specific tier refines the tiers below it.

The bundled templates lean Swift and Xcode, but nothing ties the template system to that stack. You can override any bundled file or add your own. A template can target whatever stack or workflow you have in mind. Even the bundled workflow skills arrive through templates; replace them and every new project starts differently.

## What templates provide

Templates contribute hooks, skills, docs, agents and arbitrary files or folders. Typed items land in their fixed category folder (`hooks/`, `skills/`, `docs/`, `agents/`); plain files and folders are placed wherever the template puts them.

## Customizing

Settings > Templates and the Template Manager (⇧⌘T) let you override any bundled file or add your own. Overrides are stored per file in Application Support rather than inside your project, so a new scaffold always starts from your current template state.

- A dot marker (●) means an override actually differs from the bundled file.
- **Reset to default** restores a bundled-backed file; **Delete** removes a user-authored one.
- Bundled files cannot be deleted from disk, so removing one places a tombstone that hides it from scaffolding.
- **Restore Defaults** moves the whole override store to the Trash, so the step is recoverable.

## Same-named files merge

When the same file name appears in more than one tier, the variants are composed into a single output file instead of the most specific one silently winning. How they compose depends on the file; see Template Merge Syntax.
