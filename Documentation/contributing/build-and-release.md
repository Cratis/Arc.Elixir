---
title: Build and release
description: How Arc for Elixir is built, tested and released - the pull request checks, the proxy contract gate, the labels that decide a version, and how a merge reaches Hex.
---

A change reaches users through a pull request, a label and a merge. This page explains each automated step and how to reproduce it locally, so a red check is something you can fix rather than something you wait on.

## Layout

| Path | Contents |
| --- | --- |
| `Source/arc` | The `cratis_arc` Hex package: the only thing that is published |
| `Samples` | The plug, Phoenix and React samples |
| `ContractTests` | The proxy contract gate: generated TypeScript, compiled and run against the real client |
| `Documentation` | These pages, and the excerpt verifier |
| `decisions` | Accepted design decisions |

## Reproduce the checks locally

You need Elixir 1.18 or later, and Node.js 22 for the contract gate and the React sample. CI uses Elixir 1.19.5 on Erlang/OTP 28.5.

```shell
cd Source/arc
mix deps.get
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
mix test

cd ../..
Samples/run-tests.sh            # the samples
ContractTests/run.sh            # the proxy contract
python3 Documentation/verify-snippets.py
```

## The pull request pipeline

Every pull request runs `Build` and `Verify Pull Request Policy`.

| Workflow | Job | What it proves |
| --- | --- | --- |
| `build.yml` | Build and test | Formatting, no compiler warnings, and the specs |
| `build.yml` | Documentation | Every `# From:` excerpt in these pages still matches its source file |
| `build.yml` | Samples | The plug and Phoenix samples format, compile and test, and the React sample type-checks and builds against the proxies the Phoenix sample generated |
| `build.yml` | Proxy contract | Proxies are deterministic, compile under strict TypeScript against the published `@cratis/arc` packages, and the real client works against an Arc server |
| `verify-pull-request-policy.yml` | policy | The description is a valid release note and exactly one release label is set |

Verification that runs only after a merge cannot inform the merge, so everything `Publish` runs also runs here first.

### The proxy contract

`ContractTests/run.sh` is the guard on the most coupled part of the project, the generated TypeScript:

1. Generate proxies for the test fixtures twice and compare hashes: output must be deterministic.
2. `npm ci` and `tsc --noEmit` with `strict` and `verbatimModuleSyntax` against pinned versions of `@cratis/arc`, `@cratis/arc.react` and `@cratis/fundamentals`.
3. Start an Arc server on Bandit and run the real client against it with `node --test`.

The npm versions are pinned in `ContractTests/TypeScript/package.json` so the gate means something. Dependabot proposes bumps as `no-release` pull requests; a bump that breaks the gate shows you the incompatibility before users meet it.

## Documentation excerpts

A fenced block whose first line is `# From: path/to/file` is an excerpt of a real file. `Documentation/verify-snippets.py` fails when an excerpt no longer appears, line for line, in its source. Change the sample, then the page.

## Labels and versions

Exactly one label decides what a merge releases:

| Label | Use for |
| --- | --- |
| `major` | A breaking change to a public module, option or generated-proxy shape |
| `minor` | A new capability that breaks nothing |
| `patch` | A bug fix or an internal change with identical behavior |
| `no-release` | Documentation, samples, tests, CI, and other changes nothing published depends on |

A pull request that touches nothing a user can observe is `no-release`: an unnecessary release burns a version number and buries the ones that matter. Group small related changes into one pull request, because the pull request is the release boundary.

## The pull request description is the release note

The description is published verbatim as the GitHub release. Follow `.github/pull_request_template.md`: an optional short summary, then only the `Added`, `Changed`, `Fixed`, `Removed`, `Security` and `Deprecated` sections that have bullets, each bullet short and about what a user compiles against or observes. End a bullet that fully delivers an issue with `(#123)`. Put test plans, verification and review notes in a pull request comment, not the description.

## Publishing

`publish.yml` runs on every push to `main` that changes `Source/**`, and can be started by hand with an explicit version and release notes.

1. **release** uses `cratis/release-action` to find the merged pull request, read its label, choose the version, and create the GitHub release from the description.
2. **test** compiles and runs the specs once more.
3. **publish** runs when a release was cut. It copies the README and LICENSE into the package, writes the version into `Source/arc/VERSION`, compiles, and runs `mix hex.publish --yes` with the `HEX_API_KEY` secret.
4. **verify-published** fails the run when a merge published nothing for a reason that means something went wrong (no label, or an error), so a missing release cannot be mistaken for a success. A commit pushed straight to `main` or a `no-release` merge publishes nothing and is fine.

Releases are serialized: a new merge queues behind a release in flight instead of cancelling it.

`VERSION` in the repository is a placeholder. The real version exists only at publish time, from the release label.

## Keeping dependencies current

- **Update Packages** runs nightly. It runs `mix deps.update --all` in the package and each Elixir sample and opens a `no-release` pull request, because `mix.lock` is not part of the published package.
- **Dependabot** updates the pinned npm packages and the workflow actions, also as `no-release`.

## Documentation site

When `Documentation/**` changes on `main`, `documentation.yml` asks the Cratis documentation site to rebuild. A merged page is live only after that build; confirm it before saying so.

## When a check is red

- *Formatting*: run `mix format`. If a declaration macro such as `field` is rewritten with parentheses, check `import_deps: [:cratis_arc]` in `.formatter.exs`.
- *Warnings*: the build compiles with `--warnings-as-errors`; fix the warning, do not suppress it.
- *Proxy contract, step 1*: something nondeterministic entered the generator output, for example an unordered map. Sort it.
- *Proxy contract, step 2*: the generated TypeScript no longer compiles. Read the first error; it usually names a template line in `Arc.ProxyGenerator.Render`.
- *Policy*: read the failure; it names the rule and the line.
