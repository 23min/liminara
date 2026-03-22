# LodeTime — DevOps as a Provenance Chain

**Can a runtime track its own development? When production breaks, can you trace backward from the incident to the decision that caused it?**

Research | recursive provenance, CI/CD as DAG, dependency decisions, deployment tracing

---

## The scenario

Proliminal releases Liminara v0.9.2 on a Tuesday. On Thursday, a customer reports that the VSME pack's XBRL renderer produces invalid output — the `xbrli:period` element uses an incorrect date format for duration disclosures. The fix is straightforward (a two-line patch), but the post-mortem question is harder: **how did this get into production?**

The answer involves a dependency upgrade, a CI configuration change, a test gap, and a deployment decision — spread across three weeks and four people. Today, reconstructing this chain requires searching through Slack messages, CI logs, GitHub PR comments, and deployment records. With LodeTime, the entire development lifecycle is itself a provenance-tracked pipeline. The chain is already there.

---

## The pipeline

```
  LIMINARA v0.9.2 RELEASE — traced backward from the incident
  ═════════════════════════════════════════════════════════════

  Week 1: Dependency decision
  ┌───────────────────────────────────────────────────┐
  │  dev.dependency_review                            │
  │  (recordable)                                     │
  │                                                   │
  │  ex_xbrl 0.4.1 → 0.5.0                           │
  │  Decision: upgrade                                │──→ decision record:
  │  Reason: "0.5.0 adds ESRS 2024 taxonomy;         │    dep = "ex_xbrl"
  │   changelog shows no breaking changes"             │    from = "0.4.1"
  │  Decided by: erik.lindqvist                       │    to = "0.5.0"
  │                                                   │    rationale = "ESRS 2024
  │  What wasn't noticed: duration period format      │     taxonomy support"
  │  changed from ISO 8601 basic to extended          │
  └───────────────────────────────────────────────────┘
                        │
  Week 2: CI configuration
  ┌───────────────────────────────────────────────────┐
  │  dev.ci_config_update                             │
  │  (artifact)                                       │
  │                                                   │
  │  .github/workflows/ci.yml updated                 │──→ ci-config (artifact)
  │  Change: XBRL validation step timeout             │    sha256:3a91...
  │  increased from 30s to 120s                       │
  │  (unrelated, but the XBRL validation suite        │
  │   was skipped in the same PR due to flakiness)    │
  └───────────────────────────────────────────────────┘
                        │
  Week 2: Test execution
  ┌───────────────────────────────────────────────────┐
  │  dev.run_tests                                    │
  │  (pure, pinned env)                               │
  │                                                   │
  │  mix test — 847 pass, 0 fail, 3 skip             │──→ test-report (artifact)
  │  Skipped: xbrl_validation_test.exs               │    sha256:f2d4...
  │  (marked @tag :skip in the CI config PR)          │
  │                                                   │
  │  The three skipped tests would have caught        │
  │  the period format change.                        │
  └───────────────────────────────────────────────────┘
                        │
  Week 3: Deployment decision
  ┌───────────────────────────────────────────────────┐
  │  dev.deploy_decision                              │
  │  (recordable)                                     │
  │                                                   │
  │  Deploy target: production (fly.io, arn region)   │──→ decision record:
  │  Decision: deploy v0.9.2                          │    version = "0.9.2"
  │  Decided by: klara.nilsson                        │    target = "production"
  │  Based on: test report (847 pass),                │    approved_by =
  │   staging smoke test (pass),                      │     "klara.nilsson"
  │   changelog review                                │
  └───────────────────────────────────────────────────┘
                        │
  Week 3: Deployment execution
  ┌───────────────────────────────────────────────────┐
  │  dev.deploy_execute                               │
  │  (side-effecting)                                 │
  │                                                   │
  │  fly deploy --app liminara-prod                   │──→ deploy-receipt
  │  Image: sha256:9c17...                            │    (artifact)
  │  Healthy: 3/3 instances                           │    sha256:b5e0...
  └───────────────────────────────────────────────────┘
                        │
  Thursday: Incident
  ┌───────────────────────────────────────────────────┐
  │  Customer report: XBRL period format invalid      │
  │                                                   │
  │  Trace backward:                                  │
  │    deploy-receipt → deploy decision               │
  │      → test-report (3 tests skipped!)             │
  │        → ci-config change (skip was here)         │
  │          → dependency decision (format change)    │
  │                                                   │
  │  Root cause visible in < 2 minutes.               │
  └───────────────────────────────────────────────────┘
```

---

## The recursive property

LodeTime treats Liminara's own development as a Liminara run. This is not metaphorical — it is a literal pipeline:

- **Dependency versions** are decisions (recorded with rationale, decided by a person)
- **CI configuration** is an artifact (content-addressed, versioned)
- **Test execution** is a pure op (same inputs produce same results)
- **Deployment target selection** is a decision (recorded with rationale and approval)
- **Deployment** is a side-effecting op (gated, receipted)

The same five concepts that power the VSME pack (Artifact, Op, Decision, Run, Pack) power the development process that builds the VSME pack. The runtime that provides provenance has provenance over itself.

---

## The post-mortem, traced

Without LodeTime, the post-mortem takes a day of forensics: reading commit messages, searching CI logs, asking Erik why he upgraded ex_xbrl. With LodeTime, the entire chain is navigable in the observation UI:

1. Start at the incident: "XBRL period format invalid in v0.9.2"
2. Find the deployment run for v0.9.2: `lode-deploy-2026-03-18`
3. See the deployment decision: approved by Klara, based on test report sha256:f2d4...
4. Open the test report: 847 pass, 0 fail, **3 skip** — click on the skipped tests
5. Trace the skip: introduced in CI config artifact sha256:3a91..., committed in the same PR as the timeout change
6. Trace the dependency: ex_xbrl 0.4.1 to 0.5.0, decision by Erik, rationale recorded
7. Root cause: the dependency upgrade changed period format behavior, and the tests that would have caught it were skipped in an unrelated CI change

Every link in this chain is a content-addressed artifact or a recorded decision. The chain cannot be broken by someone deleting a Slack message or a CI log expiring.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Why was ex_xbrl upgraded to 0.5.0?" | Decision record: Erik's rationale ("ESRS 2024 taxonomy support"), the changelog he reviewed (artifact), and the date. |
| "Who approved the deployment to production?" | Decision record: Klara, with the inputs she relied on (test report, staging results). |
| "Why weren't the XBRL validation tests run?" | Trace: CI config artifact sha256:3a91... introduced `@tag :skip`. That config was committed in PR #137 (timeout fix). The skip was a side effect of a different change. |
| "What would have happened if we hadn't skipped those tests?" | Hypothetical replay: re-run `lode-test-2026-03-15` with the skip removed. The three tests fail. The deployment decision's input (test report) changes. The gate would not have passed. |
| "Which other deployments used this CI config?" | Query: all runs referencing ci-config sha256:3a91... as an input. Returns every build that ran with the skipped tests. |
| "Has this dependency caused issues before?" | Query: all decision records where `dep = "ex_xbrl"`. Returns the full upgrade history with rationale and downstream effects. |

---

## Before and after

**Today:** The post-mortem takes a day. Erik remembers the upgrade but not the details. The CI config change was two weeks ago and the PR description says "fix timeout." The connection between the timeout fix, the test skip, and the deployment is invisible. The retro produces an action item: "add XBRL validation to CI." Nobody remembers this happened six months later when the same pattern recurs with a different dependency.

**With provenance:** The post-mortem takes fifteen minutes. The chain from incident to root cause is navigable. The decision to skip tests is a recorded artifact — not a forgotten commit in a forgotten PR. The decision to upgrade the dependency includes the rationale and the decider. When someone proposes skipping tests in a future CI change, the system can surface: "last time tests were skipped in CI config, it led to incident #47 in production." The institutional memory is in the provenance chain, not in people's heads.

---

*Looking for teams interested in applying provenance infrastructure to their own development and deployment processes — especially those with audit or compliance requirements for software releases. [Contact ->]*
