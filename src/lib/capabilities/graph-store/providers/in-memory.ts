/**
 * in-memory.ts — the in-memory `graph-store/1` reference provider.
 *
 * The simplest possible conforming engine: plain Maps, no persistence, always
 * available. It exists to (a) prove the interface is engine-agnostic — a
 * non-kuzu engine passes the same conformance suite — and (b) give the resolver
 * an always-bindable graph-store so the palace can resolve `service/graph-store`
 * even where the LadybugDB vector extension is absent (the `Dreamball-7bc`
 * degraded path). Non-persistent: data lives for the process lifetime only.
 */

import type {
  GraphStore,
  PalaceData,
  RoomData,
  RecordActionParams,
  ActionRow,
} from '../interface.js';

const byFp = (a: { fp: string }, b: { fp: string }): number =>
  a.fp < b.fp ? -1 : a.fp > b.fp ? 1 : 0;

export class InMemoryGraphStore implements GraphStore {
  readonly id = 'in-memory';
  readonly implementsVersion = '1.0';

  private opened = false;
  private readonly palaces = new Map<string, PalaceData>();
  private readonly rooms = new Map<string, Map<string, RoomData>>(); // palaceFp → roomFp → RoomData
  private readonly actions = new Map<string, RecordActionParams[]>(); // palaceFp → ordered log

  async open(): Promise<void> {
    this.opened = true;
  }

  async close(): Promise<void> {
    this.opened = false;
  }

  async ensurePalace(fp: string, opts?: { name?: string }): Promise<void> {
    this.assertOpen();
    if (!this.palaces.has(fp)) this.palaces.set(fp, { fp, name: opts?.name });
  }

  async addRoom(palaceFp: string, roomFp: string, opts?: { name?: string }): Promise<void> {
    this.assertOpen();
    let rooms = this.rooms.get(palaceFp);
    if (!rooms) {
      rooms = new Map();
      this.rooms.set(palaceFp, rooms);
    }
    if (!rooms.has(roomFp)) rooms.set(roomFp, { fp: roomFp, name: opts?.name });
  }

  async getPalace(palaceFp: string): Promise<PalaceData | null> {
    this.assertOpen();
    return this.palaces.get(palaceFp) ?? null;
  }

  async roomsFor(palaceFp: string): Promise<RoomData[]> {
    this.assertOpen();
    const rooms = this.rooms.get(palaceFp);
    return rooms ? [...rooms.values()].sort(byFp) : [];
  }

  async recordAction(params: RecordActionParams): Promise<void> {
    this.assertOpen();
    let log = this.actions.get(params.palaceFp);
    if (!log) {
      log = [];
      this.actions.set(params.palaceFp, log);
    }
    // Upsert on fp: replaying the same signed action is a no-op (D-021).
    if (!log.some((a) => a.fp === params.fp)) log.push(params);
  }

  async headHashes(palaceFp: string): Promise<string[]> {
    this.assertOpen();
    const log = this.actions.get(palaceFp) ?? [];
    const referenced = new Set<string>();
    for (const a of log) for (const p of a.parentHashes) referenced.add(p);
    return log
      .filter((a) => !referenced.has(a.fp))
      .map((a) => a.fp)
      .sort();
  }

  async actionsSince(palaceFp: string, opts?: { afterTimestamp?: number }): Promise<ActionRow[]> {
    this.assertOpen();
    const after = opts?.afterTimestamp ?? 0;
    const log = this.actions.get(palaceFp) ?? [];
    return log
      .filter((a) => a.timestamp > after)
      .map((a) => ({
        fp: a.fp,
        actionKind: a.actionKind,
        targetFp: a.targetFp ?? '',
        timestamp: a.timestamp,
      }))
      .sort((x, y) => x.timestamp - y.timestamp || byFp(x, y));
  }

  private assertOpen(): void {
    if (!this.opened) throw new Error('graph-store(in-memory): open() must be called first');
  }
}
