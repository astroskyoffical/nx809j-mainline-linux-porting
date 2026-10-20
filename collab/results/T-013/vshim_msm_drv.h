/* T-013 userspace shim replacing vendor msm_drv.h for sde_dsc_helper.c.
 * drm_dsc_config comes from the pinned mainline drm_dsc.h (vendor tree ships no
 * common-kernel headers). struct msm_display_dsc_info is the verbatim vendor
 * definition extracted from msm_drv.h:552-575; MSM_CHROMA_*, DSC_BPP/DSC_BPC
 * and msm_get_src_bpc are copied from vendor msm_drv.h:89-91,810,816 and msm_drv.c:460-480. */
#ifndef T013_VSHIM_MSM_DRV_H
#define T013_VSHIM_MSM_DRV_H
#include "kshim.h"
#include <drm/display/drm_dsc.h>
#define MSM_CHROMA_444 0x0
#define MSM_CHROMA_422 0x1
#define MSM_CHROMA_420 0x2
#define mult_frac(x, n, d) (((x) * (n)) / (d))
#define DSC_BPP(config) ((config).bits_per_pixel >> 4)
#define DSC_BPC(config) ((config).bits_per_component)
#include "msm_display_dsc_info.h"
static inline int msm_get_src_bpc(int chroma_format, int bpc)
{
	switch (chroma_format) {
	case MSM_CHROMA_444: return bpc * 3;
	case MSM_CHROMA_422: return bpc * 2;
	case MSM_CHROMA_420: return mult_frac(bpc, 3, 2);
	default: return bpc * 3;
	}
}
#endif
