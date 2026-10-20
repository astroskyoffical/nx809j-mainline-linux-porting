S=/home/rm11build/redmagic-linux/claude-T-013
cp /mnt/c/Users/astro/AppData/Local/Temp/claude/t013/kshim.h $S/shim/kshim.h
echo '#include "kshim.h"' > $S/shim/linux/stddef.h
cat > $S/shim/drm/display/drm_dp_helper.h <<'X'
#include "kshim.h"
#include <drm/display/drm_dp.h>
X
