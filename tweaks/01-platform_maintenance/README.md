# Platform maintenance

This merged topic owns independent router and package-maintenance safeguards.

## Cumulative changed files

- `/etc/config/watchdog`: external watchdog restart prevention.
- `/etc/opkg/distfeeds.conf`: duplicate, obsolete and unavailable feed cleanup.

The package helper permission correction is repository-build behavior rather
than a router configuration file. Release `1.6.0-5` corrected the package so
`simmanager-fast-switch` and `simmanager-jio-ensure` retain executable mode;
the active implementation remains in the project build and verification
scripts.

## Source stages merged

1. `router_watchdog_restart_prevention`
2. `opkg_feed_cleanup`
3. `packaged_helper_permission_fix`

Use `change.patch` for the cumulative router-file delta. Earlier intermediate
stages remain available through Git history.
