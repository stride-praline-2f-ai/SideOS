# Efficient GitHub Actions use

This public guide intentionally excludes personal account usage exports, old
account names and account-specific cost estimates. Repository visibility, plan,
runner class, included usage and GitHub's current prices determine actual cost.
Use GitHub Billing → Usage for the authoritative account statement.

- Ordinary edits run Linux checks. Request a native build only when needed.
- Consolidate changes before requesting one unsigned SideOS IPA.
- Reuse `ipa/device` for IPA requests so its component caches stay available.
- Successful source-matching artifacts are reused instead of rebuilding.
- Component caches require exact recipe, source, architecture and toolchain keys.
  Changing one component must not force unrelated Rust/JIT/installer recompilation.
- No simulator/preview jobs run in the device workflow.
- A source-only native check is available when compilation proof is needed without
  publishing an IPA. Do not run it for low-impact preference/artwork edits that
  can be checked locally and through the Linux workflow.
- Let a useful native build finish. Retry only failed jobs for transient runner
  failures; change source first for genuine code failures.

Public standard runners may have different billing rules from private or larger
runners. Do not promise a fixed price or free compute without checking the
account's current plan and [GitHub's runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing).

`tools/actions-cost-report.py` can analyse job metadata you export locally.
Keep those personal usage reports outside the repository; none are needed to
build or use SideOS.
