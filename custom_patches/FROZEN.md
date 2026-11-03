# Frozen Loop

Loop is frozen at version 3.14.11 on the `monitor-glucose` branch: every build
makes exactly the same Loop, with the same changes, until you decide to update.

## What keeps it frozen

- `LOOP_FROZEN: 'true'` at the top of `.github/workflows/build_loop.yml`: the
  build does not merge new code from LoopKit.
- The Loop and Learn customizations are copies kept here in `custom_patches/lnl/`
  (Profile Save & Load, watch title, negative insulin damper, taken from Loop and
  Learn's repository on 2026-10-25), not downloaded at each build.
- Your own changes are here too: heartbeat, shared food list, Nightscout CGM
  backup source (with the phone name), Nightscout service phone name / backup phone,
  and Basal Lock 125.
- The branch `loop-3.14.11-frozen` marks this exact version, to come back to it
  (never build from it or change it: it is only a copy to go back to).

## Builds

- Automatic: "5. Build Loop every 2 months" (on the main branch) starts
  "4. Build Loop Manual" on `monitor-glucose` on the 5th of January, March, May,
  July, September and November. A TestFlight build lasts 90 days, so there is
  about a month to fix a problem.
- By hand, any time: Actions › 4. Build Loop Manual › Run workflow › `monitor-glucose`.

## Updating Loop one day

1. Actions › 0. Check Loop update › Run workflow. It says whether the newest
   Loop still takes all the changes (it tests the copies in `custom_patches/`).
2. In `build_loop.yml`, set `LOOP_FROZEN: 'false'` and run "4. Build Loop Manual".
   The build merges the newest Loop into this branch, then builds.
3. Set `LOOP_FROZEN` back to `'true'` to freeze the new version.

If a Loop and Learn customization no longer fits the new Loop, take the matching
newer patch from https://github.com/loopandlearn/customization (same folder
names) and replace the copy in `custom_patches/lnl/` (and its name in
build_loop.yml). Basal Lock has one copy per Loop version (`basal_lock_125_*`).

## What can still force a change (not Loop itself)

- GitHub retires old Mac and Xcode versions: the build uses the `xcode-27`
  runner and Xcode 27.0 (two lines in build_loop.yml).
- Apple raises the minimum Xcode for TestFlight uploads about once a year.
- The distribution certificate expires yearly: the build renews it, or run
  "3. Create Certificates".
