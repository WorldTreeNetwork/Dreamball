/**
 * Wishes store — Phase-1 lifecycle. A wish is a `ball.dreamball` in
 * `stage: seed` attached to a Tree branch. The Tree's agent germinates
 * it through `budding → ripening → ripe`; the user `plucks` it into a
 * downloadable `.ball`. See docs/products/wishing-tree/PHASES.md §6.
 *
 * All germination here is MOCKED via MockAgent. Real LLM hop drops in
 * via TODO-LLM markers.
 */

import { synthesise, type SynthesisedFruit } from './agent/MockAgent.js';

export type WishState = 'tied' | 'budding' | 'ripening' | 'ripe' | 'plucked';
export type Branch = 'N' | 'E' | 'S' | 'W';

export interface Wish {
	id: string;
	text: string;
	branch: Branch;
	tiedAt: number;
	state: WishState;
	fruit?: SynthesisedFruit;
}

let nextId = 1;
function newId(prefix: string): string {
	return prefix + '-' + (nextId++).toString().padStart(4, '0');
}

const TIMINGS = {
	tiedToBudding: 1500,
	buddingToRipening: 2500,
	ripeningToRipe: 4500
} as const;

export class WishGarden {
	wishes: Wish[] = $state([]);
	plucks: number = $state(0);
	transmissions: number = $state(0);
	revision: number = $state(0);

	private timers = new Map<string, number[]>();

	tie(text: string, branch: Branch = pickBranch()): Wish | null {
		const t = text.trim();
		if (!t) return null;
		const w: Wish = { id: newId('wish'), text: t, branch, tiedAt: Date.now(), state: 'tied' };
		this.wishes = [w, ...this.wishes];
		this.scheduleLifecycle(w);
		return w;
	}

	private scheduleLifecycle(w: Wish): void {
		const ts: number[] = [];
		ts.push(
			window.setTimeout(() => this.advance(w.id, 'budding'), TIMINGS.tiedToBudding) as unknown as number
		);
		ts.push(
			window.setTimeout(
				() => this.advance(w.id, 'ripening'),
				TIMINGS.tiedToBudding + TIMINGS.buddingToRipening
			) as unknown as number
		);
		ts.push(
			window.setTimeout(
				() => this.germinate(w.id),
				TIMINGS.tiedToBudding + TIMINGS.buddingToRipening + TIMINGS.ripeningToRipe
			) as unknown as number
		);
		this.timers.set(w.id, ts);
	}

	private advance(id: string, to: WishState): void {
		const i = this.wishes.findIndex((w) => w.id === id);
		if (i < 0) return;
		const w = this.wishes[i];
		if (w.state === 'plucked') return;
		const next = { ...w, state: to };
		this.wishes = [...this.wishes.slice(0, i), next, ...this.wishes.slice(i + 1)];
	}

	private germinate(id: string): void {
		const i = this.wishes.findIndex((w) => w.id === id);
		if (i < 0) return;
		const w = this.wishes[i];
		if (w.state === 'plucked') return;
		// TODO-LLM: replace MockAgent.synthesise with a real LLM call,
		// gated by the Root Zone key vault + the Tree's emotional-register
		// urgency budget. For Phase 1 this is deterministic and offline.
		const fruit = synthesise(w.text);
		const next: Wish = { ...w, state: 'ripe', fruit };
		this.wishes = [...this.wishes.slice(0, i), next, ...this.wishes.slice(i + 1)];
	}

	pluck(id: string): SynthesisedFruit | null {
		const i = this.wishes.findIndex((w) => w.id === id);
		if (i < 0) return null;
		const w = this.wishes[i];
		if (w.state !== 'ripe' || !w.fruit) return null;
		const next = { ...w, state: 'plucked' as WishState };
		this.wishes = [...this.wishes.slice(0, i), next, ...this.wishes.slice(i + 1)];
		this.plucks += 1;
		this.revision += 1;
		this.cancel(id);
		return w.fruit;
	}

	cancel(id: string): void {
		const ts = this.timers.get(id);
		if (ts) ts.forEach((t) => window.clearTimeout(t));
		this.timers.delete(id);
	}

	transmit(): void {
		this.transmissions += 1;
		this.revision += 1;
	}

	count(state: WishState): number {
		return this.wishes.filter((w) => w.state === state).length;
	}

	totalRipe(): number {
		return this.count('ripe');
	}
}

const branches: Branch[] = ['N', 'E', 'S', 'W'];
let branchIdx = 0;
function pickBranch(): Branch {
	const b = branches[branchIdx % branches.length];
	branchIdx++;
	return b;
}

/** Convert a branch direction to a (cx,cy)-relative angle for visual placement. */
export function branchAngle(b: Branch): number {
	return { N: -90, E: 0, S: 90, W: 180 }[b];
}
