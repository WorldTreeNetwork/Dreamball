/** Local animation document, deliberately separate from the causal ball.timeline.
 * Plain data: no renderer objects or executable source cross this boundary. */
export type Curve = {
	interpolation: 'linear' | 'smooth' | 'step';
	keys: readonly (readonly [seconds: number, value: number])[];
};
export type Pose = { y: number; tilt: number; turn: number; stretch: number };
export type Clip = { duration: number; tracks: Partial<Record<keyof Pose, Curve>> };
export type StageDocument = {
	version: 1;
	object: { id: string; assetSlot: 'look.asset'; fit: number };
	idle: Clip;
	reaction: Clip;
	trigger: { channel: string; clip: 'reaction'; whilePlaying: 'ignore' };
};

export const starStage: StageDocument = {
	version: 1,
	object: { id: 'star', assetSlot: 'look.asset', fit: 2 },
	idle: {
		duration: 4,
		tracks: {
			y: {
				interpolation: 'smooth',
				keys: [
					[0, 0],
					[1, 0.1],
					[2, 0],
					[3, -0.1],
					[4, 0]
				]
			},
			tilt: {
				interpolation: 'smooth',
				keys: [
					[0, 0],
					[1, -0.055],
					[3, 0.055],
					[4, 0]
				]
			}
		}
	},
	reaction: {
		duration: 1.8,
		tracks: {
			y: {
				interpolation: 'smooth',
				keys: [
					[0, 0],
					[0.15, -0.1],
					[0.65, 0.65],
					[1.15, 0],
					[1.4, 0.16],
					[1.8, 0]
				]
			},
			turn: {
				interpolation: 'smooth',
				keys: [
					[0, 0],
					[0.2, 0],
					[1.25, Math.PI * 2],
					[1.8, Math.PI * 2]
				]
			},
			stretch: {
				interpolation: 'smooth',
				keys: [
					[0, 0],
					[0.15, -0.16],
					[0.4, 0.14],
					[0.8, 0],
					[1.15, -0.12],
					[1.4, 0.07],
					[1.8, 0]
				]
			}
		}
	},
	trigger: { channel: 'star.touch', clip: 'reaction', whilePlaying: 'ignore' }
};

export function sampleCurve(curve: Curve, seconds: number): number {
	const keys = curve.keys;
	if (!keys.length) return 0;
	if (seconds <= keys[0][0]) return keys[0][1];
	for (let i = 1; i < keys.length; i++) {
		const [end, b] = keys[i];
		if (seconds < end) {
			const [start, a] = keys[i - 1];
			let t = (seconds - start) / (end - start);
			if (curve.interpolation === 'step') t = 0;
			if (curve.interpolation === 'smooth') t = t * t * (3 - 2 * t);
			return a + (b - a) * t;
		}
	}
	return keys[keys.length - 1][1];
}

export type StageEvent = { channel: string; at: number };

/** One instance owns one channel scope. No global event bus or per-frame history writes. */
export class StagePlayer {
	time = 0;
	private reactionAt: number | null = null;
	constructor(
		readonly document: StageDocument,
		private emit: (event: StageEvent) => void = () => {}
	) {}
	get reacting() {
		return this.reactionAt !== null;
	}
	send(channel: string): boolean {
		if (channel !== this.document.trigger.channel || this.reacting) return false;
		this.reactionAt = this.time;
		this.emit({ channel: 'reaction.started', at: this.time });
		return true;
	}
	advance(seconds: number) {
		if (!Number.isFinite(seconds) || seconds < 0) return;
		this.time += seconds;
		if (
			this.reactionAt !== null &&
			this.time >= this.reactionAt + this.document.reaction.duration
		) {
			const at = this.reactionAt + this.document.reaction.duration;
			this.reactionAt = null;
			this.emit({ channel: 'reaction.finished', at });
		}
	}
	seek(seconds: number) {
		if (!Number.isFinite(seconds)) return;
		if (this.reacting) this.emit({ channel: 'reaction.cancelled', at: this.time });
		this.reactionAt = null;
		this.time = Math.max(0, seconds);
	}
	pose(): Pose {
		const pose: Pose = { y: 0, tilt: 0, turn: 0, stretch: 0 };
		const sample = (clip: Clip, time: number) => {
			for (const name of Object.keys(clip.tracks) as (keyof Pose)[]) {
				pose[name] += sampleCurve(clip.tracks[name]!, time);
			}
		};
		sample(this.document.idle, this.time % this.document.idle.duration);
		if (this.reactionAt !== null) sample(this.document.reaction, this.time - this.reactionAt);
		return pose;
	}
}
