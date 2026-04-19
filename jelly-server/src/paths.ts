/**
 * Cross-runtime path helpers.
 *
 * `import.meta.dir` is Bun-native and undefined under Vitest's worker
 * runtime. `fileURLToPath(import.meta.url)` is the portable fallback that
 * works in both. Every module that needs a stable module-relative path
 * should import `moduleDir` from here rather than reaching for
 * `import.meta.dir` directly.
 */

import { dirname } from 'path';
import { fileURLToPath } from 'url';

export function moduleDir(metaUrl: string, metaDir?: string): string {
  if (typeof metaDir === 'string' && metaDir.length > 0) return metaDir;
  return dirname(fileURLToPath(metaUrl));
}
