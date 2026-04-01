# Skill: Release

Tag a release, update changelog, and publish.

## When to Use

Epic is complete and merged to main. User says: "Release v1.2", "Tag a release", "Publish"

## Checklist

1. **Pre-release checks**
   - [ ] On `main` branch
   - [ ] All tests pass
   - [ ] Build is green
   - [ ] No uncommitted changes

2. **Determine version**
   - [ ] Check current version (latest git tag)
   - [ ] Apply semantic versioning:
     - `MAJOR` — breaking changes
     - `MINOR` — new features, backward compatible
     - `PATCH` — bug fixes only
   - [ ] Confirm version with user

3. **Update changelog**
   - [ ] Add release section to `CHANGELOG.md`
   - [ ] Group changes: Added, Changed, Fixed, Removed
   - [ ] Reference milestone/epic for context
   - [ ] Stage changelog, show diff
   - [ ] 🛑 **STOP — wait for human to say "commit"**
   - [ ] Commit changelog: `docs: update changelog for vX.Y.Z`

4. **Create tag** (only after human approval)
   - [ ] 🛑 Confirm with human: "Tag as vX.Y.Z and push?"
   - [ ] `git tag -a vX.Y.Z -m "Release vX.Y.Z: <summary>"`
   - [ ] Push tag: `git push origin vX.Y.Z`
   - [ ] Mirror to GHE: `git push ghe vX.Y.Z`

5. **Post-release**
   - [ ] Update `ROADMAP.md` — mark epic as `released`
   - [ ] Verify deployment (if CI/CD auto-deploys on tag)
   - [ ] Run health checks
   - [ ] **Record learnings** — append to `work/agent-history/deployer.md`:
     - Release process issues or improvements discovered
     - Infrastructure or pipeline patterns worth remembering
   - [ ] If any deployment decisions were made, append to `work/decisions.md`

## Output

- Git tag `vX.Y.Z`
- Updated `CHANGELOG.md`
- Updated `ROADMAP.md`
