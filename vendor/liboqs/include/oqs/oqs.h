/* Minimal <oqs/oqs.h> override for the Dreamball-vendored subset of liboqs.
 *
 * Upstream pulls in kem.h, sig.h, sig_stfl.h, aes_ops.h, sha2_ops.h,
 * sha3x4_ops.h — all irrelevant for a build that only exposes ML-DSA-87
 * through its pqcrystals ref-impl entry points. This override keeps the
 * include graph to the four headers we actually use.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef OQS_H
#define OQS_H

#include <oqs/oqsconfig.h>
#include <oqs/common.h>
#include <oqs/rand.h>
#include <oqs/sha3_ops.h>

#endif /* OQS_H */
