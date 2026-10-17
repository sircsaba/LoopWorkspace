# Basal Lock, 125 mg/dL

Because the Profiles customization is in the build list, the copies that are
actually used are `basal_lock_125_3149_profiles.patch` (Loop 3.14.9) and
`basal_lock_125_3144_profiles.patch` (3.14.4–3.14.8), made from
`basal_lock/main…_basal_lock_profiles.patch`. The copies without `_profiles` are
kept for a build without Profiles; the build simply applies whichever one fits.

`basal_lock_125_3144.patch` and `basal_lock_125_3149.patch` are Loop and Learn's
Basal Lock customization (`basal_lock/main3144_basal_lock.patch` for Loop
3.14.4–3.14.8 and `main3149_basal_lock.patch` for 3.14.9) with the lower limit
changed from 200 to 125 mg/dL. The build applies the newest one that fits. It is applied by `build_loop.yml` in the "Customize Loop"
step, after the CustomizationSelect list (where `basal_lock` was removed), and
the build checks that the 125 limit is in the Loop code afterwards.

Because it is a copy kept here, updates to Loop and Learn's customization
repository never change the limit.

## When a new Loop version breaks it

The build stops at "Customize Loop" with "No basal_lock_125 patch fits this
Loop version".
Nothing is built. To fix:

1. Take the newest `basal_lock/main…_basal_lock.patch` from
   https://github.com/loopandlearn/customization (use the `_profiles` variant
   only if the Profiles customization is applied too).
2. Change `doubleValue: 200)...HKQuantity` to `doubleValue: 125)...HKQuantity`
   in it.
3. Save it as `basal_lock_125_<version>.patch` (e.g. `basal_lock_125_3150.patch`),
   commit, and build again.
