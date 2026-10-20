set -e
S=/home/rm11build/redmagic-linux/claude-T-013
cp /mnt/c/Users/astro/AppData/Local/Temp/claude/t013/kshim.h $S/shim/kshim.h
for h in linux/export.h linux/kernel.h linux/module.h linux/init.h linux/errno.h linux/byteorder/generic.h linux/types.h linux/bits.h linux/bug.h drm/display/drm_dp_helper.h drm/drm_fixed.h drm/drm_print.h; do
  echo '#include "kshim.h"' > $S/shim/$h; done
cat >> $S/shim/drm/drm_print.h <<'X'
struct drm_printer { int dummy; };
#define drm_printf_indent(p, i, ...) do {} while (0)
#define drm_printf(p, ...) do {} while (0)
X
cat >> $S/shim/drm/display/drm_dp_helper.h <<'X'
struct dp_sdp_header { u8 HB0, HB1, HB2, HB3; };
#define DP_SDP_PPS 0x10
#define DP_SDP_PPS_HEADER_PAYLOAD_BYTES_MINUS_1 0x7F
X
cd $S && ls -R shim | head -30
