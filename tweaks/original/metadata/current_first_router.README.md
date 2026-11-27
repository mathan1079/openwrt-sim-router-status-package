# Current first-router snapshot

This directory is the authoritative local snapshot of router-owned files that
were last fully reconciled with the live first router on 27 November 2026,
after deploying SIM Manager `1.6.0-5`. The snapshot includes the persistent
automatic-switch history implementation and the LTE/5G SA/5G NSA profile
selector, along with the earlier AT-lock, GPIO, CFUN, ICCID and Jio safeguards.

Release `1.6.0-5` corrected package payload permissions: both
`files/usr/sbin/simmanager-fast-switch` and
`files/usr/sbin/simmanager-jio-ensure` are installed with mode `0755`. Their
contents and SHA-256 hashes are unchanged from `1.6.0-4`.

At reconciliation time SIM1 and SIM2 profiles, vendor UCI and the live RM500U
all used `NR5G:LTE`. Jio was registered on 5G SA n78 with both IPv4 and IPv6
connectivity healthy.

Files below `files/` preserve their absolute router paths. This snapshot is for
comparison, recovery planning and future patch preparation. Do not deploy the
entire directory blindly; install only the file required by a reviewed tweak.

`MANIFEST.sha256` contains hashes relative to `files/`. Regenerate it whenever
a router deployment changes one of these files, then verify the same hashes on
the live first router.

`files/etc/config/simmanager` is a point-in-time configuration capture. Its
last-seen operator, signal, band and timestamp fields are refreshed by normal
dashboard polling, so its live checksum may change without a configuration or
code deployment. Audit its policy fields semantically instead of treating later
metadata-only checksum drift as a fault.

The downstream/second router is outside this snapshot and was not accessed.
