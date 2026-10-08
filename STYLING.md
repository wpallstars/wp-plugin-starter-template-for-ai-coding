# Styling standards

Styling rules every plugin made from the wpallstars starter plugin follows,
for its admin screens and its front end. This file is the same in each of
them (names as placeholders: `STANDARDS.md` lists them, and the plugin's
`AGENTS.md` gives its values). The other rules: `STANDARDS.md`.

## Admin screens: spacing and forms

React forms and modals in wp-admin use WordPress components, and the
container owns the spacing, not the controls. Scope these rules to the
plugin's form classes (`.{css}-form`, `.{css}-fieldset`, `.{css}-form__row`,
`.{css}-form__actions`), never to all admin forms.

- Remove controls' outer margins: `__nextHasNoMarginBottom` on
  `TextControl`, `SelectControl`, `TextareaControl`, `CheckboxControl` and
  `ToggleControl`, and `__next40pxDefaultSize` on inputs, selects and
  adjacent buttons, where the component version supports those props. On
  older versions, use scoped CSS for the same spacing and height; do not
  pass unsupported props to DOM elements.
- Forms and groups use `display: grid; gap: 16px`. Related buttons have an
  8px gap; help text sits 4px below its field. Use WordPress's 4px spacing
  scale: 4, 8, 12, 16 and 24px. Reset `margin: 0` on paragraphs, headings
  and lists inside these containers; never mix browser margins with `gap`.
- Group fields with `<fieldset>` and `<legend>`, not headings with ad-hoc
  margins; the legend is `float: left; width: 100%` so it joins the grid.
  Separate groups with a `1px solid #dcdcde` top border.
- Short fields sit side by side in a row with
  `grid-template-columns: repeat(auto-fit, minmax(200px, 1fr))` and
  `align-items: start`: labels line up and fields wrap on narrow screens.
- A notice with content and actions has a content grid with `gap: 8px`.
  Show a read-only URL in a full-width monospace input, with **Copy** and
  **Open in a new window** buttons together on one wrapping row.
- A disabled control always explains why in help text below it, or, for a
  button that supports it, with `accessibleWhenDisabled` and a `title`.
  Validate required fields on submit and show a message instead of silently
  disabling the submit button.
- Modals use the plugin's `.{css}-modal` class: a fixed width at WordPress's
  small breakpoint (600px) and above, a full-width sheet below. End with
  right-aligned **Cancel** (tertiary) and the primary action.

## Front-end styling and dark mode

Block, shortcode and other front-end styles must work with the Kadence Pro
dark mode switcher (and themes that switch palettes the same way).

- How it switches: Kadence adds `color-switch-dark` or `color-switch-light`
  to `<body>`. The dark class sets `color-scheme: dark` and redefines
  `--global-palette1`…`15` and `--wp--preset--color--theme-palette-N` **on
  `<body>`**; `<html>` stays `color-scheme: light`. Palette 3 is the
  strongest text and palette 9 the page background in light mode; dark mode
  swaps them.
- Use `currentColor`, `inherit`, translucent neutrals (for example
  `rgba(127, 127, 127, 0.12)`) or palette variables, never fixed light or
  dark colours for text, backgrounds or borders.
- Do not follow the site with `@media (prefers-color-scheme)`: it tracks the
  visitor's system, not the switcher. Do not define custom properties on
  `:root` from palette variables: they resolve above `<body>` and keep the
  light values. Read palette variables where they are used, or define
  derived ones on the block.
- Preset references (`var:preset|color|theme-palette3`) become CSS variables
  with kebab-cased slugs, as core does: `--wp--preset--color--theme-palette-3`.
  Use `_wp_to_kebab_case()` in PHP and the same rule in editor JS (a hyphen
  between letters and digits, lower case).
- Embedded pages (iframes) do not follow the switcher: they see the
  visitor's system setting, and the browser paints their own background
  behind them, so they stay readable in both modes. Do not make iframes
  transparent or tint them.
- Test: view the page with the Kadence theme in light and dark mode
  (`STANDARDS.md` → Testing, step 5). Without Kadence Pro, simulate the
  switcher: print a
  `body.color-switch-dark { color-scheme: dark; --global-palette1: …; }`
  rule with a dark palette (palette 3 light, palette 9 dark, and the
  matching `--wp--preset--color--theme-palette-N: var(--global-paletteN)`
  lines), then swap the body class between `color-switch-light` and
  `color-switch-dark`. Check text, backgrounds, borders and palette colours
  chosen in block settings in both.
