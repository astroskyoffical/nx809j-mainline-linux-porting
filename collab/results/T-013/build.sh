set -o pipefail
S=/home/rm11build/redmagic-linux/claude-T-013; M=/home/rm11build/redmagic-linux/kernel-mainline-src
T=/mnt/c/Users/astro/AppData/Local/Temp/claude/t013
cd $S; mkdir -p vshim
cp $T/kshim.h shim/kshim.h; cp $T/vshim_msm_drv.h vshim/msm_drv.h; echo '#include "kshim.h"' > vshim/sde_kms.h; cp $T/harness.c harness.c
gcc --version | head -1
CF="-std=gnu11 -O0 -Wall -Wno-unused-function -Ishim -I$M/include"
gcc $CF -c src/drm_dsc_helper.c -o drm_dsc_helper.o 2>&1 | tee build-mainline.log; echo rc_mainline=$?
gcc $CF -Ivshim -Isrc -c src/sde_dsc_helper.c -o sde_dsc_helper.o 2>&1 | tee build-vendor.log; echo rc_vendor=$?
gcc $CF -Ivshim -Isrc -c harness.c -o harness.o 2>&1 | tee build-harness.log; echo rc_harness=$?
gcc harness.o drm_dsc_helper.o sde_dsc_helper.o -o harness 2>&1; echo rc_link=$?
./harness > harness.out; echo rc_run=$?
cat harness.out
sha256sum harness.c shim/kshim.h vshim/msm_drv.h src/* harness.out
