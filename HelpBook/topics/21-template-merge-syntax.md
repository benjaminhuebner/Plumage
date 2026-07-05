---
id: template-merge-syntax
swift: templateMergeSyntax
title: Template Merge Syntax
icon: chevron.left.forwardslash.chevron.right
section: Templates
---
# Template Merge Syntax

When template tiers contribute a file with the same name, Plumage merges the variants into one output file. The strategy is chosen in this order:

1. **Placeholder merge** whenever the least-specific variant contains `<<<keyword>>>` placeholder lines, regardless of file extension.
2. **Format-aware merge** by extension: `.json`, `.xml`, `.md` / `.markdown`.
3. **Plain-text append** for any other text file.
4. **Copy** for binary files and for variants a merge cannot parse. The most specific variant wins verbatim.

Merged output keeps the most specific variant's permissions, so scripts stay executable.

## Placeholder merge

The least-specific file (the skeleton) marks insertion points with a placeholder alone on its own line:

```
## Reference docs
<<<refdocs>>>
```

Any contributing variant fills a placeholder with a matching block:

```
%% refdocs %%
- docs/PROJECT.md — what this project is
%% /refdocs %%
```

Rules:

- Matching is exact and case-sensitive: `<<<refdocs>>>` is filled only by `%% refdocs %%`, never by `%% Refdocs %%` or `%% ref docs %%`.
- Markers must stand alone on their line; whitespace around the keyword inside the markers is ignored.
- Several blocks with the same keyword, in one file or across tiers, join in source order separated by a blank line.
- Unfilled placeholders are dropped from the output. If the dropped placeholder sat directly under a `## ` heading, the heading is removed too, so an empty section leaves no orphan.
- An unclosed `%% keyword %%` or a stray `%% /keyword %%` is an authoring error.

## Markdown: merge by heading

Without placeholders, `.md` files merge section-wise:

- Sections match on the exact heading line, level included: `## Build and test` only matches `## Build and test`, never `# Build and test`.
- A repeated heading fuses the contribution's leading block (up to its first blank line) into the existing section; lines the section already contains are skipped.
- New headings append at the end of the document.
- YAML frontmatter is never line-merged; the most specific variant's frontmatter wins wholesale.
- Fenced code blocks move and deduplicate as one unit. They are never split.

## JSON: deep merge

- Objects merge key by key; the more specific variant wins on conflicts.
- Arrays append elements that are not already present (deep value equality).
- Expect a regenerated file rather than a byte-for-byte edit: output is re-serialized pretty-printed with sorted keys.
- If any variant fails to parse, no merge happens and the most specific variant is copied verbatim.

## XML: structural merge

- All variants must share the root element name; otherwise the most specific variant is copied verbatim.
- Attributes replace by name.
- A child element whose name is unique on both sides merges recursively; other children append unless a structurally identical one already exists.
- Output is re-serialized pretty-printed.

## Plain text: append

Text files with no better strategy concatenate in tier order, one blank line between chunks. A variant identical to an earlier one is skipped, so a copied and untouched file never doubles its content.
