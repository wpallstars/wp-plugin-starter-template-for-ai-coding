# WP Plugin Starter design

Shared styling rules and tokens live in `STYLING.md`. The starter uses
WordPress admin components, its colour scheme and its existing header,
tabs and cards; it adds no independent brand palette to Light mode.

## Admin colour mode

- The header has an icon button after Buy me a coffee, with Light, Dark
  and System radio menu items. Each item has an icon, label and current
  choice tick. Screen readers get the mode name and save-failure message.
- Dark tokens: canvas `#101517`, surface `#1d2327`, raised `#2c3338`,
  border `#3c434a`, text `#f0f0f1`, muted `#c3c4c7`, field border `#8c8f94`.
  Accent fills follow WordPress's scheme; text accents are lightened.
- Palette overrides apply only below `html.wps-dark` on own screens.
  Light keeps existing colours. System follows the OS live. There are no
  mode transitions, including for reduced-motion users.

## Responsive Behaviour

- Keep the existing header's wrapping and small-screen breakpoints.
  The mode control joins the header actions rather than adding another row.
- Use a 32px minimum icon button and 36px minimum menu rows; the mobile
  WordPress button sizing remains in effect. Menu minimum width is 168px.
- Position the menu at the logical end of the button, below it, for LTR
  and RTL. Keep focus outlines visible. Arrows, Home, End and Escape move
  within or close the menu; Tab closes it without trapping focus.
