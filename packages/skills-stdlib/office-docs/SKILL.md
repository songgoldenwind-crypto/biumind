---
name: office-docs
display_name: 办公文档
description: 生成可验收的办公产物：Markdown/Wiki 长文、表格（CSV/xlsx）、PPT/PDF、研究简报、授权目录下的批量文件。当用户要周报、纪要整理、汇报材料、批量改文件时使用。
icon: 📎
permissions: []
paths: ["**/*.md", "**/*.csv", "**/*.xlsx", "**/*.pptx", "**/*.pdf", "docs/**", "wiki/**"]
---

# Office deliverables

You are producing **checkable files**, not a chat essay. Prefer writing
real files in the working directory (or Wiki pages) so the task result
pane can list, diff, and preview them.

## When to use

- Meeting notes → weekly report
- Spreadsheet / CSV from unstructured lists
- Slide outline or PPTX
- Research brief with sources
- Batch rename / extract / convert files the user authorized

## Output kinds

| User asks | Write |
|---|---|
| 长文 / 周报 / 纪要 | Markdown (`.md`) or Wiki page |
| 表格 / 名单 / 账 | `.csv` first; `.xlsx` if formulas or multiple sheets are required |
| PPT / 汇报 | `.pptx` (python-pptx) or Markdown slide outline `slides.md` if the runtime has no pptx lib |
| PDF | export from Markdown / HTML when a converter exists; otherwise `.md` + tell the user |
| 研究报告 | `*-research.md` with: 问题、发现、证据、结论、待办 |
| 批量文件 | one folder, many files; summarize the file list in the last message |

## How to write files

1. Confirm the working directory is the user's authorized folder.
2. Use Write / Edit tools. One artefact per clear deliverable; batch jobs may emit many files.
3. After writing, list paths in the reply so the result pane can parse them.
4. Optional artefact JSON for a research brief:

```
{"kind":"artifact","type":"research","title":"...","content":"..."}
```

## PPT / xlsx fallbacks

If `python-pptx` / `openpyxl` are missing:

- PPT → `slides.md` with `## Slide N` headings and speaker notes
- Excel → UTF-8 CSV (one file per sheet)

Do not pretend a binary Office file exists when you only wrote Markdown.

## Constraints

- Do not touch files outside the authorized workdir.
- Default to ONE primary deliverable unless the user asked for a pack.
- Wiki for durable knowledge; local files for reports the user will download.

User's request: $ARGS
