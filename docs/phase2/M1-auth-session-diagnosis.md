# M1 Auth Session Diagnosis

Date: 2026-10-01

## Scope

This note records the M1-01 investigation of Supabase session loss across an
iOS relaunch or a background/foreground transition.

## Evidence

- The production web bundle enables Supabase `persistSession` and
  `autoRefreshToken` and mirrors `INITIAL_SESSION`, `SIGNED_IN`,
  `TOKEN_REFRESHED`, and `USER_UPDATED` sessions to native with
  `SET_AUTH_SESSION`.
- Native stores the mirrored access token, refresh token, expiry, and user ID
  in Keychain and can refresh an expired access token.
- Before this fix, app launch only used that Keychain session for background
  HealthKit work. A newly created WebView never received the stored session.
- Therefore web storage was the only source capable of restoring the visible
  login. If WebKit storage was empty, unavailable, or lost during startup, the
  app opened signed out even while a valid refresh token remained in Keychain.

## Root cause

Session persistence was one-way: web to native. The durable native copy was
not part of the WebView bootstrap protocol.

## Fix and race policy

After a main-frame load finishes, native refreshes the Keychain session when
needed and offers it to the web app through the existing
`AUTH_SESSION_UPDATED` message. The web app already handles this message with
`supabase.auth.setSession`.

The async Keychain/network operation captures an auth generation. Any
`SET_AUTH_SESSION` or `CLEAR_AUTH_SESSION` received before it finishes makes
the bootstrap result stale. This prevents a stored token from overwriting a
new account or reviving an explicit logout.

## Remaining acceptance gate

Simulator unit tests cover the ordering policy and the full native regression
suite. A signed iPhone run is still required for M1-04 acceptance: fresh login,
terminate/relaunch, background token refresh, logout, and account switch.
