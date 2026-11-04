# M1 supplementary evidence — 2026-10-01

Automated checks only; nothing was installed on or run against a physical
iPhone. M1-02 to M1-08 stay in **Testing** until the physical-iPhone
acceptance in M1-04 is done.

Environment: Xcode 26.6, iOS 26.5 simulator (iPhone 17 Pro), native repository
at `8feb25a` plus the uncommitted working tree of the same day (M1-07 health
sources, landscape signing, M2 Icon verification). Debug builds started with
`-HonouredBridgeStub` load a local test page; in that mode
`AppConfig.supabaseURL` is nil, so no scenario contacts Supabase.

## Results

| Check | Result | Covers | Files |
| --- | --- | --- | --- |
| Session restore across cold launches (7 launches, see below) | 17/17 | M1-02 | `simulator/sim-01` … `sim-07` |
| Native unit tests (`xcodebuild test`) | 114/114, incl. `AuthSupportTests` 7 (restore race gate) and `HealthSourcePreferenceTests` 7 | M1-02, M1-07, M1-08 | `native-unit-tests.txt` |
| Bridge-stub regression scenarios | Google 22/22 + reload 2/2, sound 5/5, goals 13/13, timer 17/17, landscape 10/10, Live Activities 89/89 (8 scenarios) | M1-08 | `simulator/sim-08` … `sim-22`, `sim-r-*` |
| Signed device build (generic iOS, not installed) | Succeeded; Apple Development identity, team profile for `com.jimmy.upwork.honoured`; entitlements: Sign in with Apple, HealthKit, HealthKit background delivery | M1-03, M1-07 | `signed-device-build.txt` |
| Published web bundle (`honour-your-word.lovable.app`) | Contains every M1 marker (below), and also the Oct 1 landscape and Icon M2-04/M2-05 changes | M1-03, M1-05, M1-06, M1-07 | `published-web-markers.txt` |
| Web → native message names | All 32 outbound web types are handled by native; every M1 reply type is emitted by native and read by web | M1-08 | — |
| Production auth data (read-only aggregates) | 13 users, 0 anonymous; identities: email 11, apple 2 (last 2026-09-23), google 1; 0 users with Apple linked to another provider; 0 stored Apple refresh credentials; 0 account deletions | M1-03 | — |

### Session restore scenarios

Each line is a separate launch; the app is terminated in between.

1. `auth-restore-setup`: a session for user A is accepted and stored in the Keychain.
2. `auth-restore-check`: the new page receives `AUTH_SESSION_UPDATED` with `source: native_restore`, user A's tokens and expiry, as a broadcast, exactly once; logout then empties the Keychain.
3. `auth-restore-cleared`: after logout and relaunch nothing is restored and the Keychain stays empty.
4. `auth-restore-setup` again (user A stored).
5. `auth-restore-race`: a login for user B sent while the page is loading is accepted, user A is never offered, and the Keychain holds B.
6. `auth-restore-expired-setup`: an already expired session is stored.
7. `auth-restore-expired-check`: an expired session that cannot be refreshed is never offered. In stub mode the refresh fails with `notConfigured` because the backend is off, so this does **not** exercise Supabase rejecting a real refresh token.

### First-pass failures

The first full pass failed 5 checks (goals 2, timer-foreground 2,
live-activities-multiple 1). The simulator's notification-permission prompt
was unanswered (`notification-prompt-blocking-first-pass.png`): `SET_GOALS`
waits for that prompt before evaluating goals, and the alert makes the app
inactive. After Allow, all three scenarios passed (`sim-r-*`).

## Not covered here

- Real Supabase sign-in, token refresh and logout on a signed iPhone (M1-04).
- The Sign in with Apple sheet, the Apple-to-existing-account link, and storage
  of Apple's refresh token for revocation. Production has two Apple identities
  but no stored Apple credential, so the revoke path (App Store 5.1.1(v)) has
  not been observed working; check the `APPLE_SIGNIN_*` secrets and do one real
  Apple sign-in.
- Real HealthKit sources (Apple Watch vs iPhone), notification permission and
  Settings return, gesture feel, signature rendering and VoiceOver.
- Web unit tests were not re-run for this record; the latest Lovable run at
  commit `94615a0` reported 404/404, which includes the M1 test files.
