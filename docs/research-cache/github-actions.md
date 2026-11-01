---
topic: github-actions
checked: 2026-11-01
stability: volatile
sources:
  - git ls-remote --tags https://github.com/<each action>.git
  - npm view netlify-cli version engines.node
  - npm view vercel version engines.node
---

# Pins for the CD templates and kit CI

Latest exact `vX.Y.Z` tag within the major the templates use, and the commit it peels to (`^{}` read for an annotated tag). Major bumps go through dependabot, not this file.

| Action | Tag | Commit SHA | Newest major available |
| --- | --- | --- | --- |
| `actions/checkout` | v4.4.0 | `11d5960a326750d5838078e36cf38b85af677262` | 7 |
| `actions/setup-node` | v4.4.0 | `49933ea5288caeca8642d1e84afbd3f7d6820020` | 7 |
| `pnpm/action-setup` | v4.4.0 | `fc06bc1257f339d1d5d8b3a19a8cae5388b55320` | 6 |
| `actions/upload-artifact` | v4.6.2 | `ea165f8d65b6e75b540449e92b4886f43607fa02` | 7 |
| `actions/download-artifact` | v4.3.0 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` | 8 |
| `actions/upload-pages-artifact` | v3.0.1 | `56afc609e74202658d3ffba0e8f6dda462b719fa` | 5 |
| `actions/deploy-pages` | v4.0.5 | `d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e` | 5 |
| `docker/login-action` | v3.7.0 | `c94ce9fb468520275223c153574b00df6fe4bcc9` | 4 |
| `docker/setup-buildx-action` | v3.12.0 | `8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` | 4 |
| `docker/build-push-action` | v6.19.2 | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` | 7 |

- `pnpm/action-setup`: the floating `v4` tag stays at v4.3.0 (`b906aff…`), one commit behind v4.4.0. Pinning v4.4.0 moves targets one commit past what `@v4` gives them today. The other nine floating tags equal the exact tag above.
- The `Newest major` column reads tag names only. Whether each tag is a published release was not checked.

| CLI | Version | `engines.node` |
| --- | --- | --- |
| `netlify-cli` | 27.16.1 | `>=22.13.0` |
| `vercel` | 65.9.0 | `>= 20` |

The templates' `node-version: '22'` (`templates/github/ci.yml:58`, `deploy.yml:153`) resolves to the latest 22.x.
