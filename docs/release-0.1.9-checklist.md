# LinDirStat 0.1.9 release checklist (draft)

This checklist follows the 0.1.6 process in [parity-plan.md](parity-plan.md).
Dan is merging the ready pull requests himself. A release candidate and final
publication each need his separate go decision.

## Merge and verify

1. Finish the disposable combined macOS check of the seven pull requests:
   build, unit and UI tests, GUI gate, and screenshots for resize, extension
   highlighting, background search, and panel centering. The combined Linux
   checkout has already passed build, unit and command-line tests, 62 UI tests,
   strict treemap parity, and 191 Adwaita GUI checks.
2. Dan merges in this order: #180, #174, #175, #177, #181, #176, #178. After
   each merge, verify both required checks on `main`. Resolve any branch
   conflicts while preserving both `isBusy` conditions from #177 and #178,
   their imports, and all added test helpers and cases. After the full batch
   lands, run the complete Linux build, unit, command-line and UI suites,
   strict treemap parity, and light/dark Adwaita GUI gate on merged `main`.
   The earlier combined checkout does not replace these checks.
3. Re-measure #172 resize behavior on merged Linux `main` and close it only
   if the post-merge numbers support the fix. Review the strong dimmed resize
   preview that Dan accepted during a drag. Confirm the associated #168,
   #170, #171, #173, and #179 issues are closed as their changes land.
4. Review the separate diagnostic PR #184. Its green Linux and macOS CI and
   focused regression cover an empty-table layout-observer exception; it is
   not a fix for the recoverable menu freeze in open issue #185.

## Prepare the candidate

5. Review the Linux and macOS 0.1.9 notes, then a separate version PR for
   `package.version` and runtime notices. Re-check release inputs and keep
   the current toolchain and packager pins unless a separately reviewed
   compatibility change is ready. Issue #164 tracks that later adoption.
6. With Dan's candidate go, run `release.yml` on `main` with
   `version=0.1.9-rc1`. Record the workflow run ID and exact source commit.
7. From that run, Linux performs the AppImage `--from-ci` dry run and update
   check from a clean clone checked out at the run's exact commit (the script's
   `bwrap` step cannot follow a worktree `gitdir` link). Include a clean
   Fedora GNOME/KDE smoke with default fonts. The earlier #182 check used an
   optimization-only rc0, so it does not replace
   validation of the full seven-PR candidate.
8. macOS checks the DMG from the same run: first open after the documented
   xattr step, an explicit fixture scan (never the home directory), Save and
   Open panels, and Preferences/Treemap layouts. Dan checks GNOME Wayland,
   including rounded corners, Select Target panel stacking, the accepted
   dimmed resize preview, and the three-pane workflow.

## Final candidate and publication

9. When rc1 findings are resolved and `main` is green, run the manual final
   `release.yml` candidate without a version override. Repeat the Linux dry
   run from a clean clone at that exact run's commit, plus the macOS DMG check.
   Freeze `main` from this candidate through publication.
10. With Dan's separate publish go, Linux runs `release-linux.sh --from-ci`
    with `--publish` from the `main` branch on the key-holding laptop. Verify
    tag `v0.1.9` peels to the final run's commit, six release assets and their
    checksums, and the signed live update feed offering 0.1.9. Then close the
    0.1.9 milestone.

The unreproduced menu freeze (#185) stays open for a future captured stuck
stack. Its status does not imply that a fix shipped in 0.1.9.
