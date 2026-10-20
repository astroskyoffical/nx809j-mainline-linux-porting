/* T-013 userspace shim: minimal kernel definitions so the unmodified
 * drm_dsc_helper.c / sde_dsc_helper.c compile in userspace. Not kernel code. */
#ifndef T013_KSHIM_H
#define T013_KSHIM_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#define EINVAL 22
#define ERANGE 34
#define EOPNOTSUPP 95

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int8_t s8; typedef int16_t s16; typedef int32_t s32; typedef int64_t s64;
typedef uint16_t __be16; typedef uint32_t __be32; typedef uint8_t __u8; typedef uint16_t __u16; typedef uint32_t __u32;
#define cpu_to_be16(x) ((u16)__builtin_bswap16((u16)(x)))
#define __packed __attribute__((packed))
#define WARN_ON_ONCE(x) (!!(x))
#define BIT(n) (1UL << (n))
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define DIV_ROUND_UP(n, d) (((n) + (d) - 1) / (d))
#define EXPORT_SYMBOL(x)
#define EXPORT_SYMBOL_GPL(x)
#define MODULE_DESCRIPTION(x)
#define MODULE_LICENSE(x)
#define __printf(a, b)
#define WARN_ON(x) (!!(x))
#define BUILD_BUG_ON(x)
#define min(a, b) ((a) < (b) ? (a) : (b))
#define max(a, b) ((a) > (b) ? (a) : (b))
#define pr_err(...) fprintf(stderr, __VA_ARGS__)
#define SDE_ERROR(...) fprintf(stderr, "SDE_ERROR " __VA_ARGS__)
#define SDE_INFO(...) fprintf(stderr, "SDE_INFO " __VA_ARGS__)
#define DRM_DEBUG_KMS(...) do {} while (0)
#define DRM_DEBUG(...) do {} while (0)
#define DRM_ERROR(...) fprintf(stderr, __VA_ARGS__)
#endif
