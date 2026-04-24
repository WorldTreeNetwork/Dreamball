/**
 * cypher-utils.test.ts — property tests for Cypher string escape hardening.
 *
 * Sprint-1 code review HIGH-4: fuzz escCypherString with fast-check to
 * verify the escaped output never contains injection vectors.
 */

import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { escCypherString, cypherString } from './cypher-utils.js';

const LS = String.fromCharCode(0x2028); // U+2028 LINE SEPARATOR
const PS = String.fromCharCode(0x2029); // U+2029 PARAGRAPH SEPARATOR

describe('HIGH-4: escCypherString hardening', () => {
  it('escapes U+2028 LINE SEPARATOR', () => {
    const input = `before${LS}after`;
    const escaped = escCypherString(input);
    expect(escaped).not.toContain(LS);
    expect(escaped).toContain('\\u2028');
  });

  it('escapes U+2029 PARAGRAPH SEPARATOR', () => {
    const input = `before${PS}after`;
    const escaped = escCypherString(input);
    expect(escaped).not.toContain(PS);
    expect(escaped).toContain('\\u2029');
  });

  it('escapes all dangerous characters', () => {
    const nasty = `it's a \\backslash\nnewline\rcarriage\0null${LS}ls${PS}ps`;
    const escaped = escCypherString(nasty);
    // Single quotes should be escaped as \'
    expect(escaped).not.toMatch(/(?<!\\)'/);
    expect(escaped).not.toContain('\n');
    expect(escaped).not.toContain('\r');
    expect(escaped).not.toContain('\0');
    expect(escaped).not.toContain(LS);
    expect(escaped).not.toContain(PS);
  });

  it('property: 1000 arbitrary strings produce safe wrapped output', () => {
    fc.assert(
      fc.property(fc.string(), (s) => {
        const escaped = escCypherString(s);
        const wrapped = `'${escaped}'`;

        // The escaped body must not contain an unescaped single quote.
        // An unescaped quote is one preceded by an even number (0, 2, ...)
        // of backslashes (lookbehind for even-count \\). Simpler: check
        // that every ' in the escaped body is preceded by an odd number
        // of backslashes (meaning it was escaped).
        for (let i = 0; i < escaped.length; i++) {
          if (escaped[i] === "'") {
            let bsCount = 0;
            for (let j = i - 1; j >= 0 && escaped[j] === '\\'; j--) bsCount++;
            // Odd backslash count = escaped quote (ok); even = unescaped (bad)
            expect(bsCount % 2).toBe(1);
          }
        }

        // No raw control bytes (NUL, newline, carriage return).
        expect(wrapped).not.toContain('\x00');
        expect(wrapped).not.toContain('\n');
        expect(wrapped).not.toContain('\r');

        // No unescaped U+2028 / U+2029.
        expect(wrapped).not.toContain(LS);
        expect(wrapped).not.toContain(PS);
      }),
      { numRuns: 1000 }
    );
  });
});

describe('HIGH-4: cypherString defence assertions', () => {
  it('wraps a normal string with single quotes', () => {
    expect(cypherString('hello')).toBe("'hello'");
  });

  it('wraps a string containing a single quote', () => {
    expect(cypherString("it's")).toBe("'it\\'s'");
  });

  it('wraps a string containing U+2028', () => {
    const result = cypherString(`a${LS}b`);
    expect(result).toBe("'a\\u2028b'");
  });
});
