#!/usr/bin/env bash
# Run ONCE per session, before the jp-reel skill. Idempotent.
# Fixes the sandbox problems seen on day 1: blocked Whisper/Remotion downloads, wrong Python for pip, missing tsconfig,
# preview.mjs and selfcheck.py issues. Usage: export JP_WORK=/home/claude/jp-work; bash tools/prerequisite.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export JP_WORK="${JP_WORK:-/home/claude/jp-work}"
S="$(ls -d /root/.claude/skills/synced/*/jp-reel 2>/dev/null | head -1)"
[ -n "$S" ] || { echo "jp-reel skill folder not found"; exit 1; }
CHROME="$(ls -d /opt/pw-browsers/chromium-*/chrome-linux64/chrome 2>/dev/null | head -1)"
[ -n "$CHROME" ] || { echo "no Chromium in /opt/pw-browsers"; exit 1; }
PYV="$(python3 -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

echo "== python packages (interpreter $PYV)"
python3 -m pip install -q --break-system-packages faster-whisper numpy 2>&1 | tail -1
python3 -m pip install -q --break-system-packages --target "/usr/local/lib/python$PYV/dist-packages" --upgrade pillow 2>&1 | tail -1

echo "== skill patches"
python3 - "$S" "$CHROME" "$HERE" <<'PY'
import sys,re,os
S,CH,HERE=sys.argv[1:4]
def patch(path,fn):
    s=open(path).read(); t=fn(s)
    if t!=s: open(path,"w").write(t); print("patched",os.path.basename(path))
# 1 preview.mjs: use the installed Chromium
patch(f"{S}/scripts/preview.mjs",lambda s: s if "browserExecutable" in s else s.replace('logLevel: "error" })',f'logLevel: "error", browserExecutable: "{CH}" }})'))
# 2 selfcheck.py: newer ffprobe adds a trailing comma
patch(f"{S}/scripts/selfcheck.py",lambda s: s if 'rstrip(",")' in s else s.replace('"{f}"\').stdout.strip()','"{f}"\').stdout.strip().rstrip(",")'))
# 3 transcribe.py: no model download -> estimated timing fallback
def tr(s):
    if "align.py" in s: return s
    old='    model = WhisperModel(os.environ.get("WHISPER_MODEL", "base.en"), compute_type="int8")\n'
    new=('    try:\n        model = WhisperModel(os.environ.get("WHISPER_MODEL", "base.en"), compute_type="int8")\n'
         '    except Exception as e:\n        print("whisper model unavailable, using estimated timing:", type(e).__name__)\n'
         f'        subprocess.run([sys.executable, "{HERE}/align.py", str(N)], check=True)\n        sys.exit(0)\n')
    return s.replace(old,new)
patch(f"{S}/scripts/transcribe.py",tr)
# 4 pipeline.sh: a failed preview must stop the run
patch(f"{S}/scripts/pipeline.sh",lambda s: s.replace('(cd "$W" && node preview.mjs $N 2>&1 | tail -3) || exit 1','(cd "$W" && node preview.mjs $N 2>&1 | tail -3; exit ${PIPESTATUS[0]}) || exit 1'))
PY

echo "== work dir"
bash "$S/scripts/setup.sh" 2>&1 | grep -v "^FAILED: remotion browser" | tail -3
cd "$JP_WORK"
[ -f tsconfig.json ] || echo '{"compilerOptions":{"target":"ES2020","module":"ESNext","moduleResolution":"bundler","jsx":"react-jsx","strict":false,"skipLibCheck":true,"esModuleInterop":true}}' > tsconfig.json
cat > remotion.config.ts <<CFG
import {Config} from "@remotion/cli/config";
Config.setBrowserExecutable("$CHROME");
Config.setChromiumOpenGlRenderer("swangle");
CFG
echo "== done. Skill: $S | Chromium: $CHROME"
