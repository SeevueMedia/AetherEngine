# Seevue's engine line

This is SeevueMedia's private fork of AetherEngine. Seevue's Flutter client
(`seevue_player` plugin) builds against it. Nothing from here goes upstream
for now.

## Branches

| Branch | What it is |
| --- | --- |
| `seevue/main` | **The Seevue line, and the fork's default branch.** Upstream 7.56.0 plus Seevue's commits: the authoritative TLS trust evaluator, the opt-in libass ASS renderer, the subtitle selection fences (SV-397, SV-492) and the Profile 7 FEL host contract (SV-531). Seevue pins revisions from this branch. |
| `main` | A plain copy of upstream (`superuser404notfound/AetherEngine`). It carries no Seevue commits, so don't open PRs into it. |
| `sv-397-subtitle-selection-fence` | The line's earlier name, kept so existing references keep working. Every commit on it is also on `seevue/main`. |

## Rules

- **Engine PRs go into `seevue/main`.** Start the branch name and the PR title
  with the Seevue task key (`sv-785-…`, `SV-785: …`).
- Seevue's pin is `aetherEngineRevision` in
  `apps/client/tool/toolchain.json` in the Seevue repository. Every commit it
  has pinned must stay reachable, so never rebase, force-push or reset
  `seevue/main`.
- To take a newer upstream release, update `main` from upstream, then merge
  `main` into `seevue/main` in a PR. Merge it; never rebase it.
