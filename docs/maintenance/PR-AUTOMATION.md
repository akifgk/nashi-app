# Nashi PR and issue assistance: staged setup

Status: proposed, observation only. Do not mark the setup PR ready or merge it
until Orkun approves the policy and the GitHub App installations separately.
No subscription, new token, bypass actor or branch-protection change is included.

## What this proposal does

- CodeRabbit: Turkish PR summaries/file walkthroughs, incremental reviews and
  related issue/PR context. Automatic approval, author approval commands, generated
  fixes/tests, CI fixes, conflict resolution, automatic labels and post-merge
  actions are disabled. Drafts are skipped. These are review settings, not an
  authorization boundary against an administrator changing the service dashboard.
- Issue enrichment can suggest duplicate/related issues, PRs and assignees after
  activation. Automatic planning and automatic issue labels are disabled. Neither
  product is being authorized to implement, close or autonomously resolve issues.
- Mergify: four observation rules with empty action maps. They describe main PRs,
  successful check names, sensitive paths, and a narrow Markdown-only CI example.
  Even a matching rule has **no action**. This is not a live merge lane, and the
  Markdown observation is not a claim that every Markdown change is safe.
- All Mergify branch-writing/queue commands have an impossible `#files<0` guard;
  only read-only refresh is allowed to `orkunisitmak` with admin permission.
  This also removes Mergify's default permission for fork authors to rewrite their
  own heads through comment commands. Keep Merge Queue and Auto-Merge disabled
  in the dashboard; install-time capabilities are broader than this YAML.

No labels or human review requests are sent by Mergify. The four empty action
maps are accepted by the official schema. Live Summary rendering, condition
parsing and command behavior still need the installed service's validation and
simulation before activation; local tests are explicitly a limited model.

## Repository facts checked on 2026-10-27

Main: `e2f1a2ed0b5b1efaa363bc6419ac63b930cd3b78`. The branch metadata reports
protection and required `security`, `mac-source`, `windows` checks, each bound to
GitHub Actions App ID `15368`. The full administration-only protection endpoint
was inaccessible; no attempt is made to replace or weaken its settings.

`.github/workflows/source.yml` produces `security` and `mac-source`;
`.github/workflows/windows.yml` produces `windows`. External PR runs currently
wait for maintainer workflow approval (`action_required`). A matching check name
in Mergify is only an observation: exact current SHA, provider identity and latest
attempt must be verified by GitHub's protected checks and the reviewer.

The existing owner-only auto-merge workflow is unchanged: ready same-repository
PRs from immutable owner account `68860338` can merge after required checks and
request post-merge CI/Pages. It does not rely on CodeRabbit or labels. **Draft is
the required hold for this setup PR.** This proposal does not retrofit semantic
bugfix classification into that older owner workflow. Do not mark feature/mixed,
release or automation work ready without Orkun's explicit decision.

## Human authorization and future automatic work

Every PR remains manual with respect to Mergify. AI approval, `bug`/`approved`
labels, an issue's wording, author age and diff size are never merge authority.
Features, mixed changes, refactors, dependencies, lockfiles, build/workflow/config,
update trust, signing, security and release work require Orkun's decision.

Any later pure-bugfix lane needs a separate reviewed change and action-time
approval. Before enabling it, prove all of the following end to end:

1. Trusted maintainer identity/permission and authorization tied to the exact
   current head SHA. A label alone is not a signed or SHA-bound authorization.
2. GitHub Actions App `15368` succeeds for all three required checks on the latest
   head and tested base/integration; no stale, skipped, cancelled or fork-only
   substitute. New commits invalidate approval. Branch protection must dismiss
   stale approvals; verify actual settings instead of assuming this YAML sets them.
3. Explicit allowlist of ordinary files, with additions/deletions/renames and
   symlinks handled. Dependencies/locks, `.github`, automation, build scripts,
   security, update/signing/credential paths and release/config are excluded.
4. No bypass or privileged execution of contributor code, no secrets in fork CI,
   and no competing merge controller. Reconcile the existing owner workflow first.
5. Baseline versus fix regression tests and actual platform-native evidence when
   UI/media behavior changes. Approval and checks must be revalidated at merge.

## Installation and activation approval boundary

The parent setup task coordinates installations. At the actual GitHub screens,
show Orkun each App's **exact current** repository/account permissions, read/write
levels, selected repositories and any OAuth scopes, and request approval before
granting access. Select only the intended repositories, not all repositories.
Do not infer a grant from this configuration PR. No installation was performed
by this task, so the live permission lists and entitlement remain unverified.

CodeRabbit needs source/PR/issue context and can post review/issue output; Mergify
can have repository write capabilities beyond these inert rules. Public code and
PR/issue text will be processed by external services after approved activation.
Review data retention/provider policies and dashboard action settings at that step.
No personal files, production secrets, signing keys or API tokens should be added.

Official pricing currently offers CodeRabbit OSS Team features on public projects
without a paid subscription and Mergify Free/Open Source at $0. Eligibility,
product enablement and rate limits must be confirmed in the actual account.
CodeRabbit Free summarization is not the same as OSS code-review entitlement;
Security Scan and Agent are separately billed products. Do not select trials,
usage-based billing, paid scans/agents, or enter payment details.

After explicit approval, install on the selected repo, validate/simulate using the
hosted services on a disposable PR, inspect read/write effects and rerun negative
cases. Keep this PR draft until Orkun approves its merge. Only then enable the
approved review/issue assistance. Queue/merge automation remains disabled.

## Reproduce local validation

Use a disposable Python environment with `PyYAML==6.0.3` and
`jsonschema==4.25.1`; these are validator tools, not app dependencies.
Download the two official JSON schemas with normal TLS certificate verification,
then run:

```sh
python scripts/test-pr-automation.py --schema-dir /path/to/schemas
python scripts/audit-public-tree.py
python scripts/generate-localizations.py --check
git diff --check
```

The schema directory must contain `coderabbit.json` and `mergify.json`. Validation
is offline once downloaded. The regression cases cover documentation allow/deny,
forks, drafts, conflict, missing/failed/pending CI, source/workflow/dependency/config
and rename paths, forged labels, AI/stale approvals, and mutation commands denied
even to the owner. They are not a replacement for Mergify's real simulator.
No native app behavior changes, so the existing expensive native suite is not
rerun just to check YAML. Hosted tests and installation permissions remain pending.

## Official references

- [CodeRabbit schema](https://coderabbit.ai/integrations/schema.v2.json)
- [CodeRabbit configuration](https://docs.coderabbit.ai/reference/configuration)
- [Issue enrichment](https://docs.coderabbit.ai/issues/enrichment)
- [CodeRabbit OSS plans](https://docs.coderabbit.ai/management/plans)
- [Mergify schema](https://docs.mergify.com/mergify-configuration-schema.json)
- [Mergify rule syntax](https://docs.mergify.com/workflow/rule-syntax/)
- [Mergify command restrictions](https://docs.mergify.com/commands/restrictions/)
- [Mergify pricing](https://mergify.com/pricing)
