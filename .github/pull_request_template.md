## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a crash, an action that did not run). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. -->

## How it was tested

<!-- The tests added, and what you ran by hand (in mix dev, in which browsers). -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix docs`, `mix test --exclude build` and `mix dialyzer` pass.
- [ ] `npm run typecheck` and `npm test` in `assets/` pass, for a change to `assets/`; `mix test.e2e` passes, for a change the browser sees.
- [ ] The guides and the `[Unreleased]` section of `CHANGELOG.md` are updated, for a change a user can see.
- [ ] Says so here if it changes the public API or what the palette does today.
- [ ] No changes to the version or the built files in `priv/static` (the maintainers keep those).
