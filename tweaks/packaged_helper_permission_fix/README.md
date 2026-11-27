# Packaged helper permission fix

## Problem

Release `1.6.0-4` first reset every package payload file to mode `0644` and
then restored executable mode for a fixed list of programs. The list omitted:

- `/usr/sbin/simmanager-fast-switch`
- `/usr/sbin/simmanager-jio-ensure`

Both source files were executable, but the generated IPK installed them as
non-executable. `simmanager-control` consequently skipped the fast helper's
`-x` check and immediately used the vendor USB power-cycle path. The vendor
worker also could not execute the Jio helper.

## Change

Release `1.6.0-5` explicitly assigns mode `0755` to both helpers while building
the package. Verification now requires both source files to be executable and
checks their shell syntax. No router configuration, AT command, GPIO sequence,
or switching policy was changed.

## Verification

1. Run `make verify`.
2. Build the IPK and inspect `data.tar.gz`; both helper entries must be mode
   `0755`.
3. Upgrade the first router and verify both installed files with `ls -l`.
4. Do not trigger a SIM switch as part of deployment. The next user-triggered
   switch will prove whether the fast path succeeds or safely falls back.

## Rollback

Install release `1.6.0-4` only if rollback is required. That release is safe
but silently uses the slower vendor path because these helpers are mode `0644`.

## Repository scope

This is a package-construction correction, so the tweak stores documentation
only. Duplicating the repository Makefile or build script inside `tweaks/`
would create a stale second build system and is intentionally avoided.
