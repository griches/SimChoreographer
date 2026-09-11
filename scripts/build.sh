#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# Reuse a real development identity so rebuilds retain a stable designated requirement.
if [[ -z "${TAPPER_SIGNING_IDENTITY:-}" ]]; then
    TAPPER_SIGNING_IDENTITY=$(python3 - <<'PYIDENTITY'
import pathlib, re, subprocess, sys
cache = pathlib.Path('.build/tapper-signing-identity')
identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
if cache.exists():
    identity = cache.read_text().strip()
    if identity != '-' and identity not in identities:
        sys.exit('Saved SimChoreographer signing identity is unavailable. Set TAPPER_SIGNING_IDENTITY explicitly.')
else:
    matches = re.findall(r'\b([A-F0-9]{40}) "Apple Development:[^"\n]+"', identities)
    identity = matches[0] if len(matches) == 1 else '-'
    if identity == '-':
        print('No unique Apple Development identity found; using ad hoc signing for this local build.', file=sys.stderr)
        print('A developer certificate is optional. Set TAPPER_SIGNING_IDENTITY to select one.', file=sys.stderr)
    cache.parent.mkdir(exist_ok=True)
    cache.write_text(identity + '\n')
print(identity)
PYIDENTITY
)
fi
if [[ "$TAPPER_SIGNING_IDENTITY" == "-" ]]; then
    printf 'Local ad hoc build: macOS privacy permissions may need reapproval after rebuilding.\n'
fi
swift build -c release
# Sign outside the file-provider-managed source folder: it can reattach
# Finder metadata between xattr cleanup and codesign.
tapper_stage=$(mktemp -d /private/tmp/tapper-build.XXXXXX)
trap 'rm -rf "$tapper_stage"' EXIT
staged_app="$tapper_stage/SimChoreographer.app"
mkdir -p "$staged_app/Contents/MacOS" build
cp .build/release/SimChoreographer "$staged_app/Contents/MacOS/Tapper"
cp .build/release/simchoreographerctl build/simchoreographerctl
cp .build/release/tapperctl build/tapperctl
cat > "$staged_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Tapper</string>
<key>CFBundleIdentifier</key><string>com.garyriches.tapper</string>
<key>CFBundleName</key><string>SimChoreographer</string>
<key>CFBundleDisplayName</key><string>SimChoreographer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${TAPPER_SIGNING_IDENTITY}" "$staged_app"
codesign --verify --strict "$staged_app"
ditto --norsrc --noextattr "$staged_app" build/SimChoreographer.app
codesign --verify build/SimChoreographer.app
# Preserve old launch paths without leaving a second, outdated app bundle.
if [[ -d build/Tapper.app && ! -L build/Tapper.app ]]; then
    mv build/Tapper.app "$tapper_stage/Previous-Tapper.app"
fi
ln -sfn SimChoreographer.app build/Tapper.app
printf 'Built build/SimChoreographer.app and build/simchoreographerctl (tapperctl remains compatible)\n'
