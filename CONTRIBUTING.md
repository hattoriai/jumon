# Contributing to Jumon

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report), what a pull request needs, and what the
maintainers keep for themselves. How to build the bundle, run the
development server and run the tests is in the README, under
[Development](README.md#development).

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form. The smallest
  commands module that shows it (its `actions/1` and `sources/1`, and the
  `live_session` it is mounted in) is the most useful thing you can give.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first, and [BACKLOG.md](BACKLOG.md):
the idea may already be planned, or turned down for a reason given there.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, an option of an action, an argument type or a callback;
- changes what the palette, an action, a source or a history does, or
  its public API (`Jumon.Commands`, the components, the hook,
  `mountJumon()`);
- changes the events between the hook and the LiveView;
- adds a dependency, in `mix.exs` or in `assets/`;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
or a bug fix with a test that fails without it. When in doubt, open the
issue: a short discussion costs less than a pull request that is not
merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A fix, the guides for an unrelated case and a README
  edit are three pull requests. Each is reviewed, reverted and released
  on its own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it: an error, a crash, an
  action that did not run. Say why a number was chosen when the change
  adds one.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors. A
  change to the matcher keeps `test/fixtures/match.json` true in Elixir
  and in TypeScript.
- **Docs.** A change a user can see updates the guide it belongs to and
  the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md).
- **The checks pass.** CI runs them; run them first:

  ```sh
  mix format --check-formatted
  mix compile --warnings-as-errors
  mix credo --strict
  mix docs
  mix test --exclude build
  mix dialyzer
  ```

  `mix precommit` runs most of them at once. CI also runs the tests with
  the oldest Phoenix and LiveView that Jumon supports
  (`JUMON_OLDEST=1`, after `mix deps.update phoenix phoenix_live_view`),
  on Elixir 1.18. A change to `assets/` also runs, in `assets/`:

  ```sh
  npm run typecheck
  npm test            # or mix test.js
  ```

  and a change the browser sees `mix test.e2e`, in Chromium, Firefox and
  WebKit.

The pull request template has these as a checklist.

## What the maintainers keep

- **Releases.** The version in `mix.exs` and `package.json`, the release
  headings of the changelog and the tags are changed by the maintainers,
  at a release.
- **The built bundle.** The files in `priv/static` are not in the
  repository; a pull request does not add them.

## Style

Match the code around your change: its naming, its comments and the way
its guides are written. `mix format` and `mix credo --strict` settle the
rest of the Elixir; `npm run typecheck` the TypeScript.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](LICENSE)).
