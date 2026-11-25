#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package_name="luci-app-simmanager"
version=${VERSION:-1.0.0}
release=${RELEASE:-1}
output_dir="$project_dir/dist"
output_file="$output_dir/${package_name}_${version}-${release}_all.ipk"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/simmanager-ipk.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

mkdir -p "$work_dir/data/usr/lib/lua/luci" "$work_dir/control" "$output_dir"
cp -R "$project_dir/luci-app-simmanager/luasrc/." "$work_dir/data/usr/lib/lua/luci/"
cp -R "$project_dir/luci-app-simmanager/root/." "$work_dir/data/"

cat > "$work_dir/control/control" <<EOF
Package: $package_name
Version: $version-$release
Architecture: all
Maintainer: Mathan
Depends: luci-base, luci-compat, luci-lib-jsonc
Section: luci
Priority: optional
Description: Read-only RM500U dashboard and independent SIM profiles
EOF

printf '%s\n' '/etc/config/simmanager' > "$work_dir/control/conffiles"
cat > "$work_dir/control/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] || rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
exit 0
EOF
cat > "$work_dir/control/prerm" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] || rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
exit 0
EOF
chmod 755 "$work_dir/control/postinst" "$work_dir/control/prerm"
printf '2.0\n' > "$work_dir/debian-binary"

find "$work_dir/data" -type d -exec chmod 755 {} \;
find "$work_dir/data" -type f -exec chmod 644 {} \;
chmod 755 "$work_dir/data/usr/sbin/simmanager-status"

(cd "$work_dir/control" && bsdtar --format=ustar --no-xattrs --uid 0 --gid 0 -czf "$work_dir/control.tar.gz" .)
(cd "$work_dir/data" && bsdtar --format=ustar --no-xattrs --uid 0 --gid 0 -czf "$work_dir/data.tar.gz" .)

rm -f "$output_file"
(cd "$work_dir" && bsdtar --format=ustar --no-xattrs --uid 0 --gid 0 -czf "$output_file" ./debian-binary ./data.tar.gz ./control.tar.gz)
echo "$output_file"

