# Maintain Nextshot Guides

The public Guides live at https://nextshot.dev/guides/. They teach the released Mac app with its default flags. The content stays in this repository.

The native handoff and published video checks are recorded in [[guides-acceptance]].

## Edit a guide

Guide files live in `site/guides/src/content/docs/`. They use MDX, which is Markdown with reusable components. Copy `site/guides/templates/guide.mdx` for a new page, then add the page to the sidebar in `site/guides/astro.config.mjs`.

- Teach one outcome per guide. Use the exact menu labels from the app.
- Put the result before the steps. Link prerequisites instead of repeating them.
- Use real screenshots from the released app. On m5pro, use only Nextshot Dev from the matching release source. Record its actual Dev version and build. Keep personal content out of the demo.
- Set `reviewedFor` to the app version you actually check. Do not raise it after a text-only edit without checking the app.
- Set `minVersion` only when the task needs a particular release. The page shows a notice when the current download is older.
- Keep experimental features and disabled flags out of general instructions.

## Shared components

| Component | Use |
| --- | --- |
| `Step` | A numbered step with a stable `#step-N` link |
| `GuideImage` | A screenshot, caption, and keyboard-accessible enlargement |
| `Shortcut` | A consistent group of key labels |
| `Clip` | An optional video with controls, a poster, and a written alternative |

Inter is self-hosted with its license in `site/guides/public/resources/inter-license.txt`. All lesson media lives in `site/guides/public/media/`. Keep names stable when the subject stays the same. Replace only images affected by a change. Record their source and app build in `site/guides/media-sources.json`.

The fictional practice page is `site/guides/public/demo.html`. The build also creates its editable ZIP with `site/guides/scripts/make-practice-project.py`. Its lemon illustration comes from the existing intro source. The practice page contains no account data and makes no third-party requests.

## Check the local result

Use Node.js 22.23.4 or later. Run these commands in `site/guides/`:

```bash
npm ci --include=dev
npm run build
npm run preview -- --port 4321
```

Open `http://127.0.0.1:4321/guides/`. Search works in the built preview. Astro's development server does not generate the Pagefind index.

Check every changed page on desktop and a narrow phone viewport. Check keyboard focus, section links, image enlargement, search, and media controls. Run the existing site checks before a commit. Keep the current `noindex, nofollow` policy.

The source template lives outside the content directory so it never becomes a published guide. The upstream ignore rules also match the guide content directory. Add new MDX pages with `git add -f site/guides/src/content/docs/<slug>.mdx`.

## Update the shortcut PDF

The shortcut sheet is generated from `site/guides/scripts/make-shortcuts.py`. Change the web reference and the script together. Run the script with a Python environment containing ReportLab. Render and inspect its only page before publication.

The generated file is `site/guides/public/resources/nextshot-shortcuts.pdf`.

## Publish with a release

The app release command attempts a Guides build before its approval prompt. It reports the build result, publishes and verifies the app first, then publishes the checked site artifact.

A guide failure leaves the app live. The release output reports whether Guides stayed unchanged or the Worker was restored. It prints a site-only retry command. An app rollback changes the download pointer only.

## Publish a guide correction

Confirm that the content describes released behavior. Run `site/deploy.sh --stage-only`. Its final line names a fresh artifact under `build/site-stages/`.

The artifact contains the Worker, configuration, assets, pinned homepage video and poster, and a checksum inventory. Preview it with the command printed by the staging script. Use a rehearsal R2 bucket for the app routes.

Publish that exact artifact with:

```bash
site/deploy.sh --deploy-staged /absolute/path/to/artifact
```

The publish command checks the inventory and never rebuilds. It verifies the live app before accepting the current Worker as a rollback target. A failed Guides check restores that Worker without changing R2 or the app download.

The default media inputs are `build/releases/Nextshot-onboarding-2026.10.24.mp4` and `build/site-poster.jpg`. Pass explicit `--video` and `--poster` inputs to change them. A guide correction must not change the homepage media by accident.

## When a feature changes

The coding agent checks which guides and screenshots the change affects. Update those pages with the feature. Check menu labels, key behavior, file access instructions, and whether a feature is enabled in the released app.

Use [[site]] for the rest of the website and release setup.
