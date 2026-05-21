# Configuration

All options, with defaults:

| Option | Default | Description |
|--------|---------|-------------|
| `source_globs` | `["src/images/**/*.{jpg,jpeg,png}"]` | What to process. **Must live under `src/`** — public URLs are derived by stripping the `src/` prefix, so `src/images/foo.jpg` becomes `/images/foo.jpg` in `picture_tag` lookups. Sources outside `src/` are processed but unreachable from templates. |
| `exclude` | `[]` | Glob patterns to skip |
| `widths` | `[400, 600, 800, 1200, 1600]` | Derivative widths |
| `formats` | `[:avif, :webp]` | Output formats (plus original) |
| `output_dir` | `"_bridgetown/image_pipeline"` | Output path under `output/` |
| `quality` | `{ avif: 65, webp: 88, jpeg: 88 }` | Per-format quality |
| `auto_rewrite` | `false` | Enable the Inspector |
| `fail_on_missing` | `false` | Raise vs. warn on missing manifest |
| `breakpoints` | `{ 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 }` | Tailwind-style breakpoints for `bg_image_block` |
| `default_width` | `1600` | Default tier for `bg_image_block`'s un-prefixed rule |

## Gotcha: Tailwind v4 and `bg-[url(...)]` in docs

Tailwind v4 auto-scans every file from the CSS entrypoint's parent dir up to
the git root. If your repo has Markdown documentation that quotes raw
Tailwind classes like `bg-[url(...)]` (e.g. in a README that explains a
migration from the old utility to this plugin), Tailwind will pick those
literal strings up and try to emit CSS rules for them. esbuild will then
fail to resolve the `...` placeholder URL, breaking your build.

Fix: add `@source not` directives to your Tailwind CSS:

```css
@import "tailwindcss";
@source not "../../docs/**";
@source not "../../test/**";
```
