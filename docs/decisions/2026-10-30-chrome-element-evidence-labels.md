# Chrome element evidence keeps no field label text

Date: 2026-10-30. Issue: #185, under #124 and #177. Status: implemented in the Chrome extension source; installed check not observed.

## Question

The handoff (`docs/sessions/2026-10-29-chrome-extension-handoff.md`) says: "Keep field values, placeholders, labels, and editable content out of element evidence." Does "labels" mean only the text that names a form field, or any visible page text?

## Sources read

- Closed #184 states the rule as: retain only structural field identity (tag, role, sanitized selector, bounds) and "do not read or retain values, placeholder text, field labels, selected options, or editable text". Its words "field labels" name labels of fields.
- Closed #184 and #183 depend on matching buttons and own-text elements by their text. The installed acceptance on 2026-10-29 shows a button match at 19 CSS pixels and a field match with empty text.
- The handoff and the 2026-10-29 browser-native-first decision give no wider meaning.

## Decision

"Labels" means text that names or holds a form field. It does not mean ordinary page text.

| Element | Recorded text |
| --- | --- |
| `<label>`, bound to a field or not | none |
| Any element inside a `<label>` | none |
| `aria-label` or own text on an element with a field role (`textbox`, `searchbox`, `combobox`, `listbox`, `checkbox`, `radio`, `slider`, `spinbutton`, `switch`), editable or not | none |
| Any element inside an element with a field role | none |
| Native `input`, `textarea`, `select`, and `contenteditable` | none (unchanged) |
| Buttons, links, headings, paragraphs, and other page text | kept, as before |

A `<label>` is dropped even when no field is bound to it, because its only job is to name a field and the binding is not always visible in the DOM. This rule is the smallest one that keeps #183 and #184 matching intact.

Two details come from the automated security review of the first commit on 2026-10-30. Role names match without regard to case or surrounding space. The check for a surrounding `<label>` or field role walks ancestors across shadow boundaries, because `Element.closest` stops at a shadow root. The older skip for descendants of `select`, `textarea`, and `contenteditable` in `snapshot()` still uses `closest`. Its shadow-boundary gap is not changed here.

## Not decided here

A paragraph or `div` that visually works as a field caption, with no `<label>` and no field role, cannot be told apart from page text. Its text stays. The screenshot shows it anyway.

## Scope

- Changed: `browser-extension/src/core/evidence.ts` (new), `src/content.ts` (`snapshot()` calls `evidenceCaption`), `checks/evidence.test.mjs`. No new permission, timer, or service.
- Evidence tier: fixture. The pure decision function runs in Node against label, aria-label, non-editable field-role, and button cases. A source guard confirms `snapshot()` uses the function. The DOM adapter in `content.ts` was not run in an installed extension.
- Follow-up found: a non-editable `role=textbox` element is not in `privateRects()`, so its pixels stay unmasked in the screenshot even though its text is no longer recorded. This is a pixel-masking question, separate from element evidence.
