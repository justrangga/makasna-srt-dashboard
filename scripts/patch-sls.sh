#!/usr/bin/env bash
# Patch and build SRT Live Server (SLS) for the Makasna TV Pool.
# Run on the gateway server. Requires root. Installs build deps, clones
# Edward-Wu/srt-live-server, applies three patches, builds, installs /usr/local/bin/sls.
#
# Patches (idempotent):
#   1. Max listen port 10000 -> 65535 (needed for hub port 12105).
#   2. Empty Stream ID fallback to live/live/stream for players/decoders.
#      Covers both cases: missing SRTO_STREAMID and empty-string sid (''
#      passes getsockopt but is rejected by split_sid upstream).
#   3. <time.h> include for current GCC.
set -euo pipefail

SRC_DIR="${SLS_SRC_DIR:-/usr/local/src/srt-live-server}"
REPO_URL="https://github.com/Edward-Wu/srt-live-server.git"
JOBS="$(nproc 2>/dev/null || echo 2)"

[[ ${EUID} -eq 0 ]] || { echo "Run as root: sudo bash scripts/patch-sls.sh" >&2; exit 1; }

apt-get update
apt-get install -y git build-essential libz-dev libsrt-openssl-dev

if [[ ! -d ${SRC_DIR}/.git ]]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 "${REPO_URL}" "${SRC_DIR}"
fi
cd "${SRC_DIR}"

patch_file() { # patch_file <file> <python-regex-old> <python-new>
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys, re, pathlib
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path); t = p.read_text()
t2, n = re.subn(old, new, t, count=1)
assert n == 1, f"pattern not found in {path}"
p.write_text(t2)
print(f"patched: {path}")
PYEOF
}

# 1. listen port range up to 65535
if ! grep -q '1024, 65535' slscore/SLSListener.hpp; then
  patch_file slscore/SLSListener.hpp \
    'SLS_SET_CONF\(server, int,    listen,               "listen port", 1024, 10000\),' \
    'SLS_SET_CONF(server, int,    listen,               "listen port", 1024, 65535),'
else
  echo "already patched: slscore/SLSListener.hpp (port range)"
fi

# 2. empty streamid fallback
if ! grep -q 'empty streamid, fallback to live/live/stream' slscore/SLSListener.cpp; then
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('slscore/SLSListener.cpp'); t = p.read_text()
t = t.replace('\tint  sid_size = sizeof(sid);\n',
              '\tint  sid_size = sizeof(sid);\n\tbool empty_sid = false;\n', 1)
old = '''if (0 != srt->libsrt_getsockopt(SRTO_STREAMID, "SRTO_STREAMID", &sid, &sid_size)) {
        sls_log(SLS_LOG_ERROR, "[%p]CSLSListener::handler, [%s:%d], fd=%d, get streamid info failed.",
                this, peer_name, peer_port, srt->libsrt_get_fd());
    \tsrt->libsrt_close();
        delete srt;
    \treturn client_count;
    }'''
new = '''if (0 != srt->libsrt_getsockopt(SRTO_STREAMID, "SRTO_STREAMID", &sid, &sid_size) || strlen(sid) == 0) {
        sls_log(SLS_LOG_INFO, "[%p]CSLSListener::handler, [%s:%d], fd=%d, empty streamid, fallback to live/live/stream.",
                this, peer_name, peer_port, srt->libsrt_get_fd());
        empty_sid = true;
        sprintf(sid, "live/live/stream");
        sid_size = strlen(sid);
    }'''
assert old in t, "streamid block not found; SLS source may have changed upstream"
p.write_text(t.replace(old, new, 1))
print("patched: slscore/SLSListener.cpp (empty streamid fallback)")
PYEOF
else
  echo "already patched: slscore/SLSListener.cpp (empty streamid fallback)"
fi

# 2b. attach the manager stat callback to the main-loop stat POST client.
# Without it get_request_data() yields an empty body and the dashboard's
# /api/sls/stat endpoint never receives player stats.
if ! grep -q 'set_stage_callback(CSLSManager::stat_client_callback' srt-live-server.cpp; then
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('srt-live-server.cpp'); t = p.read_text()
old = '''    conf_srt = (sls_conf_srt_t *)sls_conf_get_root_conf();
    if (strlen(conf_srt->stat_post_url) > 0)
        http_stat_client->open(conf_srt->stat_post_url, stat_method, conf_srt->stat_post_interval);'''
new = '''    conf_srt = (sls_conf_srt_t *)sls_conf_get_root_conf();
    if (strlen(conf_srt->stat_post_url) > 0) {
        http_stat_client->set_stage_callback(CSLSManager::stat_client_callback, sls_manager);
        http_stat_client->open(conf_srt->stat_post_url, stat_method, conf_srt->stat_post_interval);
    }'''
assert old in t, "stat_post_url open block not found"
p.write_text(t.replace(old, new, 1))
print("patched: srt-live-server.cpp (stat callback attached)")
PYEOF
else
  echo "already patched: srt-live-server.cpp (stat callback attached)"
fi

# 3. newer GCC compatibility
if ! grep -q '#include <time.h>' slscore/common.cpp; then
  sed -i 's|#include <cstdarg>|#include <cstdarg>\n#include <time.h>|' slscore/common.cpp
  echo "patched: slscore/common.cpp (<time.h>)"
else
  echo "already patched: slscore/common.cpp"
fi
if ! grep -q '#include <time.h>' slscore/common.hpp; then
  sed -i 's|#include <unistd.h>|#include <unistd.h>\n#include <time.h>|' slscore/common.hpp
  echo "patched: slscore/common.hpp (<time.h>)"
else
  echo "already patched: slscore/common.hpp"
fi

make -j"${JOBS}" 2>&1 | tail -2
install -m 755 bin/sls /usr/local/bin/sls
echo "OK: /usr/local/bin/sls installed"
