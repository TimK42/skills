---
name: uiux-audit
description: Comprehensive browser-based UI/UX audit for web applications. Covers accessibility (WCAG 2.2 AA), responsive design, i18n, PWA, form UX, and visual consistency. Use when reviewing or improving a web application's user experience.
version: 1.0
---

# UI/UX Audit Skill

Systematic browser-based UI/UX audit for web applications. Combines Nielsen's 10 Heuristics, WCAG 2.2 AA, PWA best practices, and i18n/accessibility standards.

---

## Before You Start

1. **Search the web** for latest UI/UX audit checklists (search terms: "UI UX audit checklist heuristics", "WCAG checklist", "PWA audit checklist") — supplement this guide with fresh references.
2. **Read existing audit files** if present (e.g., `docs/UX_AUDIT.md`, `docs/AUDIT.md`).
3. **Identify all app routes** — read the URL configuration (e.g., `config/urls.py`, `urls.py` per app, or framework equivalent).
4. **Start the dev server** — ensure the app is running locally and accessible via browser.

---

## Audit Dimensions

| Dimension | Focus | Priority |
|-----------|-------|----------|
| Accessibility | WCAG 2.2 AA, keyboard nav, screen readers, focus indicators | Critical |
| Responsive Design | Mobile (375px), tablet, desktop viewports | High |
| i18n/L10n | Language switching, untranslated strings, locale consistency | High |
| Form UX | Labels, validation, autocomplete, feedback states | High |
| Navigation | Breadcrumbs, skip links, footer, navbar structure | High |
| PWA | Manifest, service worker, offline fallback, meta tags | Medium |
| Visual Consistency | Headings hierarchy, spacing, dark mode, theming | Medium |
| Error Pages | 404, 500, 403 CSRF — custom vs default, nav context | Medium |
| SEO | Meta descriptions, semantic HTML, heading structure | Low |

---

## Audit Procedure

Work through each section in order. For every page, open it in the browser tool and inspect:

1. **Snapshot** — check DOM structure, headings, landmarks, forms, links
2. **Screenshot** — visual check for layout, contrast, spacing
3. **JavaScript evaluation** — programmatic checks (forms count, aria attributes, etc.)

### 1. Pre-Audit Setup

```javascript
// Check for target=_blank without rel="noopener"
document.querySelectorAll('a[target="_blank"]:not([rel*="noopener"])').length

// Check for duplicate language forms
document.querySelectorAll('form[action="/i18n/setlang/"]').length

// Check heading hierarchy
const headings = [];
document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(h => headings.push(h.tagName + ': ' + h.textContent.trim()));
headings
```

### 2. Public Pages (Unauthenticated)

Check each public page:

- [ ] **Login page** — form layout, field labels, error states, password manager support
- [ ] **Signup page** — required fields, password requirements, validation feedback
- [ ] **About / Terms / Privacy** — real content vs placeholder text, breadcrumb, footer
- [ ] **404 page** — custom template vs Django debug page, has nav/header/footer
- [ ] **Password reset** — email field, validation, navigation links
- [ ] **Homepage (unauthenticated)** — redirect behavior, landing content

### 3. Authenticated Pages

Log in as a test user. Check:

- [ ] **Homepage (logged in)** — report list / empty state, search filters, navbar changes
- [ ] **Profile page** — avatar upload, form fields, i18n, Django messages
- [ ] **Settings / Notification settings** — toggles, switches, aria-labels
- [ ] **Subscriptions** — empty state, heading i18n, management UI
- [ ] **Notifications** — empty state, mark-as-read, pagination
- [ ] **My Reports / My History** — filter tabs, empty states, pagination
- [ ] **Create Report / Comment** — form fields, validation, required indicators
- [ ] **Rooms / Chat** — empty states, list/table rendering
- [ ] **Analytics / Dashboard** — charts, data rendering, empty states
- [ ] **Monitoring / Admin pages** — health checks, stats

### 4. Accessibility Checks (WCAG 2.2 AA)

Check every page for:

- [ ] **Skip-to-content link** — First focusable element, links to `#main-content`
- [ ] **Heading hierarchy** — `h1` → `h2` → `h3` ..., no jumps
- [ ] **`<main>` landmark** — Exactly one `<main id="main-content">`
- [ ] **Focus indicators** — `:focus-visible` with visible outline (≥2px, high contrast)
- [ ] **Form labels** — All `<input>`/`<select>`/`<textarea>` have associated `<label>`
- [ ] **ARIA labels** — Icon-only links/buttons have `aria-label` with localized text
- [ ] **Images** — Decorative images have `alt=""`, informative images have descriptive `alt`
- [ ] **Color contrast** — Text meets WCAG AA contrast ratio (4.5:1 normal, 3:1 large)
- [ ] **Target size** — Interactive elements ≥24×24px (preferably 44×44px)
- [ ] **`<html lang>`** — Language attribute matches page content
- [ ] **`autocomplete` attributes** — Login fields, password, email, name fields
- [ ] **Empty states** — Accessible heading level, not inside a `<table>` without proper semantics

### 5. Responsive Design

- [ ] **Desktop (1440×900)** — Full layout, multi-column tables
- [ ] **Tablet (768×1024)** — Breakpoints work, no horizontal overflow
- [ ] **Mobile (375×812)** — Hamburger menu, card-based layout, font sizes ≥16px
- [ ] **Touch targets** — Buttons/links large enough to tap (≥44px)
- [ ] **Table responsiveness** — Card-based pattern or horizontal scroll on small screens

### 6. i18n / Localization

- [ ] **Default language** — Check correct locale is loaded
- [ ] **Language switch** — Toggle between all available languages
- [ ] **Full translation** — Every UI string is translated (check headings, buttons, placeholders, aria-labels, error messages, empty states)
- [ ] **English mode gaps** — Strings staying untranslated when switching to English
- [ ] **Language persistence** — Language preference survives navigation (check 404/500 pages)
- [ ] **Language form** — Only one language form on page, not duplicated

### 7. Dark Mode

- [ ] **Toggle works** — Button functional, state persists on navigation
- [ ] **All pages themed** — Check every page, including error pages
- [ ] **Contrast** — Text readable on dark background (body text ≈ rgb(224,224,224) on rgb(26,26,46))
- [ ] **Form elements** — Inputs, selects, textareas styled for dark mode
- [ ] **Data visualizations** — Charts, tables, progress bars visible in dark mode
- [ ] **No FOUC** — Dark mode init script prevents flash of unstyled content

### 8. PWA Audit

- [ ] **Manifest** — Returns 200, proper JSON with name, short_name, icons, start_url, display, theme_color
- [ ] **Service worker** — Registered, scope covers app, cache strategy works
- [ ] **Offline fallback** — `/pwa/offline/` page with navigation options and contact info
- [ ] **Theme color meta tags** — `theme-color` meta for light and dark modes
- [ ] **Apple meta tags** — `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`
- [ ] **Viewport meta** — `width=device-width, initial-scale=1.0`

### 9. HTTP Headers Check

Use `curl` or browser devtools to verify security headers:

```bash
curl -s -D- "http://localhost:8000/" | head -20
```

- [ ] **X-Frame-Options** — `DENY` or `SAMEORIGIN`
- [ ] **X-Content-Type-Options** — `nosniff`
- [ ] **Referrer-Policy** — `same-origin` or stricter
- [ ] **Content-Security-Policy** — Set (if applicable)
- [ ] **Cross-Origin-Opener-Policy** — `same-origin` or `same-origin-allow-popups`
- [ ] **404/500 status codes** — Proper HTTP status returned for error pages

### 10. Form UX

- [ ] **Labels** — All fields have visible labels (not placeholders-only)
- [ ] **Required indicators** — Required fields marked with `*`
- [ ] **Validation feedback** — Inline error messages, not page reload or nothing
- [ ] **Loading states** — Submit buttons disabled + spinner during submission
- [ ] **Success feedback** — Toast, banner, or redirect confirmation after submit
- [ ] **Password managers** — `autocomplete` attributes set correctly
- [ ] **Date fields** — `<input type="date">` or placeholder format hint
- [ ] **Stale messages** — Django messages cleared after redirect (no leftover login/logout messages)

### 11. Content & SEO

- [ ] **Real content** — No Lorem ipsum or placeholder text on public pages
- [ ] **Semantic HTML** — Proper use of `<nav>`, `<main>`, `<header>`, `<footer>`, `<article>`, `<section>`
- [ ] **Heading hierarchy** — Single `<h1>` per page, logical nesting
- [ ] **Meta description** — `<meta name="description">` on every page
- [ ] **Breadcrumb** — Present on interior pages, correct trail
- [ ] **Breadcrumb separators** — CSS `::before`, not inline text
- [ ] **Footer** — Links to About, Terms, Privacy, Contact
- [ ] **Skip link** — Visible or permanently visible

---

## Common JavaScript Analysis Snippets

Copy-paste these into browser console / evaluate:

```javascript
// Count forms by action
[...document.querySelectorAll('form')].reduce((acc, f) => {
  acc[f.action] = (acc[f.action] || 0) + 1;
  return acc;
}, {})

// Check heading hierarchy
const hs = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')];
hs.forEach(h => console.log(h.tagName, '→', h.textContent.trim()))

// Check aria-labels on links/buttons
[...document.querySelectorAll('a:not([href*="static"]):not([href*="#"]),button')]
  .filter(el => !el.textContent.trim() && !el.getAttribute('aria-label'))
  .forEach(el => console.log('Missing aria-label:', el.tagName, el.outerHTML.substring(0, 100)))

// Check images without alt
[...document.querySelectorAll('img:not([alt])')].forEach(img =>
  console.log('Missing alt:', img.src))

// Check for target=_blank without rel=noopener
document.querySelectorAll('a[target="_blank"]:not([rel*="noopener"])').length

// Dark mode check (returns computed style)
getComputedStyle(document.body).backgroundColor
getComputedStyle(document.body).color
```

---

## Reporting

Write findings to `docs/UX_AUDIT.md` with the following structure:

### Severity Levels

| Severity | Label | Meaning |
|----------|-------|---------|
| 🔴 Critical | `C1, C2...` | Blocks core functionality, security, or accessibility must-pass |
| 🟧 High | `H1, H2...` | Major usability, accessibility, or i18n gaps |
| 🟨 Medium | `M1, M2...` | Important improvements, non-blocking but significant |
| 🟩 Low | `L1, L2...` | Nice to have, polish, SEO |

### Report Structure

```markdown
# [App Name] UI/UX Audit Report

> Conducted: [date] via browser-based inspection
> Pages audited: [count] pages across [states]
> Framework: [references]
> Round: [number]

## ✅ Fixed Since Last Audit

| Issue | Status | Note |
|-------|--------|------|
| ... | ✅ **FIXED** | ... |

## 🔴 Critical Issues

### C1. [Title]
**Severity:** Critical
**Pages affected:** ...
**Evidence:** ...
**Fix:** ...

...

## ✅ Positive Findings

...

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | X |
| 🟧 High | X |
| 🟨 Medium | X |
| 🟩 Low | X |
| **Total** | **X** |
```

### Output Checklist

After audit:
- [ ] Report saved to `docs/UX_AUDIT.md`
- [ ] Issues created in GitHub tracker (optional per request)
- [ ] Daily memory updated with findings summary
- [ ] Fixed items confirmed via browser re-check
