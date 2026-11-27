# Current first-router snapshot

This directory is the authoritative local snapshot of router-owned files that
were updated with the verified fast-switch controller on 27 November 2026 at
12:02 PM IST.

Files below `files/` preserve their absolute router paths. This snapshot is for
comparison, recovery planning and future patch preparation. Do not deploy the
entire directory blindly; install only the file required by a reviewed tweak.

`MANIFEST.sha256` contains hashes relative to `files/`. Regenerate it whenever
a router deployment changes one of these files, then verify the same hashes on
the live first router.

The downstream/second router is outside this snapshot and was not accessed.
