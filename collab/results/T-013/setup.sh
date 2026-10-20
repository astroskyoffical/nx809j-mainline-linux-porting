set -e
R=/home/rm11build/redmagic-linux
S=$R/claude-T-013
M=$R/kernel-mainline-src
VM=$R/kernel-vendor-src/vendor/qcom/opensource/display-drivers/msm
mkdir -p $S/shim/linux/byteorder $S/shim/drm/display $S/src
cd $S
# copy real sources (read-only originals untouched)
cp $M/drivers/gpu/drm/display/drm_dsc_helper.c src/
cp $VM/sde_dsc_helper.c $VM/sde_dsc_helper.h src/
sha256sum $M/drivers/gpu/drm/display/drm_dsc_helper.c $M/include/drm/display/drm_dsc.h $M/include/drm/display/drm_dsc_helper.h $VM/sde_dsc_helper.c $VM/sde_dsc_helper.h $VM/msm_drv.h $M/drivers/gpu/drm/msm/dsi/dsi_host.c > input-sha256.txt
# extract actual dsi_populate_dsc_params from mainline dsi_host.c
awk '/^static int dsi_populate_dsc_params\(struct msm_dsi_host \*msm_host, struct drm_dsc_config \*dsc\)$/{f=1} f{print} f&&/^}/{exit}' $M/drivers/gpu/drm/msm/dsi/dsi_host.c > src/dsi_populate_dsc_params.c
# extract actual struct msm_display_dsc_info from vendor msm_drv.h
awk '/^struct msm_display_dsc_info \{/{f=1} f{print} f&&/^};/{exit}' $VM/msm_drv.h > src/msm_display_dsc_info.h
wc -l src/*
