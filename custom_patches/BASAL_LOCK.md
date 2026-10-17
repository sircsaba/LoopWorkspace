# Basal Lock, 125 mg/dL

`basal_lock_125.patch` is Loop and Learn's Basal Lock customization
(`basal_lock/main3149_basal_lock.patch`, for Loop 3.14.9) with the lower limit changed from
200 to 125 mg/dL. It is applied by `build_loop.yml` in the "Customize Loop"
step, after the CustomizationSelect list (where `basal_lock` was removed), and
the build checks that the 125 limit is in the Loop code afterwards.

Because it is a copy kept here, updates to Loop and Learn's customization
repository never change the limit.

## When a new Loop version breaks it

The build stops at "Customize Loop" with `error: patch failed` on this file.
Nothing is built. To fix:

1. Take the newest `basal_lock/main…_basal_lock.patch` from
   https://github.com/loopandlearn/customization (use the `_profiles` variant
   only if the Profiles customization is applied too).
2. Change `doubleValue: 200)...HKQuantity` to `doubleValue: 125)...HKQuantity`
   in it.
3. Replace `basal_lock_125.patch` with it, commit, and build again.
