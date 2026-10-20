/* T-013 harness: PPS from unmodified vendor sde_dsc_helper.c and from unmodified
 * mainline drm_dsc_helper.c + verbatim dsi_populate_dsc_params(), for the captured
 * NX809J BF375/RM692H5 magic mode (1216x2688, 608x16 slices, 10 bpc, 8 bpp, BP on). */
#include "kshim.h"
#include <drm/display/drm_dsc.h>
#include <drm/display/drm_dsc_helper.h>
#include "sde_dsc_helper.h"

struct device { int dummy; };
struct platform_device { struct device dev; };
struct msm_dsi_host { struct platform_device *pdev; };
#define DRM_DEV_ERROR(dev, ...) fprintf(stderr, "DRM_DEV_ERROR " __VA_ARGS__)
#include "dsi_populate_dsc_params.c"

static void dump(const char *tag, const u8 *b)
{
	printf("%s", tag);
	for (int i = 0; i < 128; i++) printf(" %02x", b[i]);
	printf("\n");
}

static void dumpcfg(const char *tag, const struct drm_dsc_config *d)
{
	printf("%s ver=%u.%u bpc=%u bpp16=%u lbd=%u bp=%d rgb=%d pic=%ux%u slice=%ux%u count=%u chunk=%u"
	       " ixd=%u idd=%u isv=%u sii=%u sdi=%u flbo=%u nflbo=%u sbo=%u io=%u fo=%u fminqp=%u fmaxqp=%u"
	       " rcms=%u ef=%u ql0=%u ql1=%u tgt=%u/%u mux=%u\n",
	       tag, d->dsc_version_major, d->dsc_version_minor, d->bits_per_component, d->bits_per_pixel,
	       d->line_buf_depth, d->block_pred_enable, d->convert_rgb, d->pic_width, d->pic_height,
	       d->slice_width, d->slice_height, d->slice_count, d->slice_chunk_size, d->initial_xmit_delay,
	       d->initial_dec_delay, d->initial_scale_value, d->scale_increment_interval,
	       d->scale_decrement_interval, d->first_line_bpg_offset, d->nfl_bpg_offset, d->slice_bpg_offset,
	       d->initial_offset, d->final_offset, d->flatness_min_qp, d->flatness_max_qp, d->rc_model_size,
	       d->rc_edge_factor, d->rc_quant_incr_limit0, d->rc_quant_incr_limit1, d->rc_tgt_offset_high,
	       d->rc_tgt_offset_low, d->mux_word_size);
	printf("%s rc_range(min,max,bpg):", tag);
	for (int i = 0; i < DSC_NUM_BUF_RANGES; i++)
		printf(" %u,%u,%d", d->rc_range_params[i].range_min_qp, d->rc_range_params[i].range_max_qp,
		       (s8)(d->rc_range_params[i].range_bpg_offset << 2) >> 2);
	printf("\n");
}

static void base(struct drm_dsc_config *c)
{
	memset(c, 0, sizeof(*c));
	c->dsc_version_major = 1;
	c->dsc_version_minor = 1;
	c->slice_height = 16;
	c->slice_width = 608;
	c->slice_count = 2;
	c->bits_per_component = 10;
	c->bits_per_pixel = 8 << 4;
	c->block_pred_enable = true;
	c->pic_width = 1216;
	c->pic_height = 2688;
}

int main(void)
{
	int rc;
	/* Vendor path: dsi_panel_parse_dsc_params() order, dsi_panel.c:3426-3567 */
	struct msm_display_dsc_info v;
	u8 vbuf[128];
	memset(&v, 0, sizeof(v));
	base(&v.config);
	v.scr_rev = 0;          /* qcom,mdss-dsc-scr-version absent in capture */
	v.slice_per_pkt = 2;
	v.chroma_format = MSM_CHROMA_444;
	rc = sde_dsc_populate_dsc_config(&v.config, v.scr_rev);
	printf("vendor_populate_rc=%d\n", rc);
	v.rc_override_v1 = false; /* qcom,mdss-dsc-rc-override_v1 absent in capture */
	rc = sde_dsc_populate_dsc_private_params(&v, 1216, false);
	printf("vendor_private_rc=%d slice_last_group_size=%d det_thresh_flatness=%d bytes_in_slice=%d bytes_per_pkt=%d pkt_per_line=%d eol_byte_num=%d\n",
	       rc, v.slice_last_group_size, v.det_thresh_flatness, v.bytes_in_slice, v.bytes_per_pkt, v.pkt_per_line, v.eol_byte_num);
	rc = sde_dsc_create_pps_buf_cmd(&v, (char *)vbuf, 0, sizeof(vbuf));
	printf("vendor_pps_rc=%d\n", rc);
	dumpcfg("VCFG", &v.config);
	dump("VPPS", vbuf);

	/* Mainline path: panel-provided fields, then dsi_host.c dsi_populate_dsc_params() */
	struct drm_dsc_config m;
	struct drm_dsc_picture_parameter_set pps;
	struct platform_device pd;
	struct msm_dsi_host host = { .pdev = &pd };
	base(&m);
	rc = dsi_populate_dsc_params(&host, &m);
	printf("mainline_populate_rc=%d\n", rc);
	drm_dsc_pps_payload_pack(&pps, &m);
	dumpcfg("MCFG", &m);
	dump("MPPS", (u8 *)&pps);
	printf("sizeof_pps=%zu\n", sizeof(pps));
	return 0;
}
