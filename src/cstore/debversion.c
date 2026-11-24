/*
 * Debian version comparison, used to sort config node names so that, e.g.,
 * "eth9" sorts before "eth10".
 *
 * This is the comparison from APT (apt-pkg/deb/debversion.cc,
 * debVersioningSystem::CmpFragment and DoCmpVersion), itself adapted from
 * dpkg (lib/dpkg/version.c). It is carried here so that every config
 * command does not have to load libapt-pkg and the dozen libraries it
 * depends on just to sort a list of names.
 *
 * Copyright (C) APT Development Team and dpkg authors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <string.h>

#include "debversion.h"

static int
isalpha_ascii(int c)
{
  return (c | 32) >= 'a' && (c | 32) <= 'z';
}

static int
order(char c)
{
  if (isdigit(c))
    return 0;
  else if (isalpha_ascii(c))
    return c;
  else if (c == '~')
    return -1;
  else if (c)
    return c + 256;
  else
    return 0;
}

/* compare one fragment (epoch, upstream version, or revision). the string
 * is split into runs of non-digits, compared by order(), and runs of
 * digits, compared as numbers.
 */
static int
cmp_fragment(const char *A, const char *AEnd, const char *B, const char *BEnd)
{
  const char *lhs = A;
  const char *rhs = B;
  while (lhs != AEnd && rhs != BEnd) {
    int first_diff = 0;

    while (lhs != AEnd && rhs != BEnd && (!isdigit(*lhs) || !isdigit(*rhs))) {
      int vc = order(*lhs);
      int rc = order(*rhs);
      if (vc != rc)
        return vc - rc;
      ++lhs;
      ++rhs;
    }

    while (*lhs == '0')
      ++lhs;
    while (*rhs == '0')
      ++rhs;
    while (isdigit(*lhs) && isdigit(*rhs)) {
      if (!first_diff)
        first_diff = *lhs - *rhs;
      ++lhs;
      ++rhs;
    }

    if (isdigit(*lhs))
      return 1;
    if (isdigit(*rhs))
      return -1;
    if (first_diff)
      return first_diff;
  }

  // the strings must be equal
  if (lhs == AEnd && rhs == BEnd)
    return 0;

  // lhs is shorter
  if (lhs == AEnd) {
    if (*rhs == '~')
      return 1;
    return -1;
  }

  // rhs is shorter
  if (rhs == BEnd) {
    if (*lhs == '~')
      return -1;
    return 1;
  }

  // shouldn't happen
  return 1;
}

/* compare two NUL-terminated strings as Debian versions ([epoch:]version
 * [-revision]). returns <0, 0 or >0.
 */
int
deb_version_cmp(const char *A, const char *B)
{
  const char *AEnd = A + strlen(A);
  const char *BEnd = B + strlen(B);

  // strip off the epoch and compare it
  const char *lhs = (const char *) memchr(A, ':', AEnd - A);
  const char *rhs = (const char *) memchr(B, ':', BEnd - B);
  if (lhs == NULL)
    lhs = A;
  if (rhs == NULL)
    rhs = B;

  // a zero epoch is the same as no epoch, so remove it
  if (lhs != A) {
    for (; *A == '0'; ++A);
    if (A == lhs) {
      ++A;
      ++lhs;
    }
  }
  if (rhs != B) {
    for (; *B == '0'; ++B);
    if (B == rhs) {
      ++B;
      ++rhs;
    }
  }

  // compare the epoch
  int res = cmp_fragment(A, lhs, B, rhs);
  if (res != 0)
    return res;

  // skip the :
  if (lhs != A)
    lhs++;
  if (rhs != B)
    rhs++;

  /* find the last -. the part after it is the revision, unless the - is
   * the first character, in which case there is no revision. (APT decides
   * this by looking at the character before the revision, which for a
   * string with no - is the terminating NUL.)
   */
  const char *dlhs = (const char *) memrchr(lhs, '-', AEnd - lhs);
  const char *drhs = (const char *) memrchr(rhs, '-', BEnd - rhs);
  int lrev = (dlhs != NULL && dlhs != lhs);
  int rrev = (drhs != NULL && drhs != rhs);
  if (dlhs == NULL)
    dlhs = AEnd;
  if (drhs == NULL)
    drhs = BEnd;

  // compare the main version
  res = cmp_fragment(lhs, dlhs, rhs, drhs);
  if (res != 0)
    return res;

  // no revision is treated like -0
  if (lrev && rrev) {
    return cmp_fragment(dlhs + 1, AEnd, drhs + 1, BEnd);
  } else if (lrev) {
    const char *null = "0";
    return cmp_fragment(dlhs + 1, AEnd, null, null + 1);
  } else if (rrev) {
    const char *null = "0";
    return cmp_fragment(null, null + 1, drhs + 1, BEnd);
  }
  return 0;
}
