# ERB Helpers

The plugin ships three ERB helpers and an optional inspector that rewrites
bare `<img>` tags at render time.

## `picture_tag` — responsive `<picture>` elements

```erb
<%= picture_tag "/images/hero.jpg",
      alt: "Sandstone formations at sunset",
      sizes: "(min-width: 1024px) 50vw, 100vw",
      priority: true,
      class: "w-full h-auto" %>
```

Renders:

```html
<picture>
  <source type="image/avif" srcset="/_bridgetown/image_pipeline/hero-400.avif 400w, ..." sizes="...">
  <source type="image/webp" srcset="/_bridgetown/image_pipeline/hero-400.webp 400w, ..." sizes="...">
  <img src="/_bridgetown/image_pipeline/hero-1600.jpg"
       srcset="..." sizes="..."
       width="2400" height="1600"
       alt="Sandstone formations at sunset"
       loading="eager" decoding="async" fetchpriority="high"
       class="w-full h-auto">
</picture>
```

`priority: true` adds `loading="eager"` and `fetchpriority="high"`. Use for
LCP candidates only.

## `bg_image_block` — responsive CSS backgrounds

For decorative `background-image` use cases. Emits an inline `<style>`
block; the caller uses the returned class on the element:

```erb
<%= bg_image_block "/images/all-flora.jpg" %>
<section class="bg-img-all-flora bg-cover p-6 lg:p-20">
  ...
</section>
```

Class names are derived from the source basename:
`/images/all-flora.jpg` → `bg-img-all-flora`.

**Breakpoint-only backgrounds** (replicates Tailwind's `lg:bg-[url(...)]`):

```erb
<%= bg_image_block "/images/hero.jpg", breakpoint_only: 1024 %>
<section class="bg-img-hero bg-cover">  <!-- bg only shows >=1024px -->
```

**Same source in two contexts** (e.g. hero + decorative loop):

```erb
<%= bg_image_block "/images/flowers.png", class_suffix: "hero" %>
<section class="bg-img-flowers-hero ...">

<%= bg_image_block "/images/flowers.png" %>
<div class="bg-img-flowers ...">
```

The `class_suffix:` kwarg keeps the two `<style>` blocks from colliding.

## `bg_image_class` — class name only, no style block

When you need to reference the class in multiple places after emitting the
block once:

```erb
<%= bg_image_block "/images/flowers.png" %>
<% klass = bg_image_class("/images/flowers.png") %>
<section class="<%= klass %> ...">...</section>
<aside class="<%= klass %> ...">...</aside>
```

## `Inspector` — auto-wrap bare `<img>` tags

Off by default. Enable in your initializer:

```ruby
init "bridgetown-image-pipeline" do
  auto_rewrite true
end
```

When on, any rendered `<img src="/images/foo.jpg">` whose source is in the
manifest is rewritten as a `<picture>` with the appropriate sources.
Opt-out on a per-tag basis with `data-no-pipeline`:

```html
<img src="/images/exact-bytes-required.jpg" data-no-pipeline>
```
