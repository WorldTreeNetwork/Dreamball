/**
 * Chiptune SFX. Synthesised with Web Audio — no asset downloads.
 * Muted by default until the user first interacts (autoplay policy).
 */

let ctx: AudioContext | null = null;
let muted = true;

function ac(): AudioContext | null {
	if (typeof window === 'undefined') return null;
	if (!ctx) {
		const Ctx =
			(window.AudioContext as typeof AudioContext | undefined) ??
			((window as unknown as { webkitAudioContext?: typeof AudioContext })
				.webkitAudioContext as typeof AudioContext | undefined);
		if (!Ctx) return null;
		ctx = new Ctx();
	}
	return ctx;
}

export function unmute(): void {
	muted = false;
	ac()?.resume();
}

export function toggleMute(): boolean {
	muted = !muted;
	if (!muted) ac()?.resume();
	return muted;
}

export function isMuted(): boolean {
	return muted;
}

/** Square-wave blip at `freq` Hz for `dur` seconds. */
export function blip(freq = 440, dur = 0.08, type: OscillatorType = 'square'): void {
	if (muted) return;
	const c = ac();
	if (!c) return;
	const osc = c.createOscillator();
	const gain = c.createGain();
	osc.type = type;
	osc.frequency.value = freq;
	gain.gain.value = 0.0001;
	gain.gain.exponentialRampToValueAtTime(0.08, c.currentTime + 0.005);
	gain.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + dur);
	osc.connect(gain).connect(c.destination);
	osc.start();
	osc.stop(c.currentTime + dur + 0.02);
}

export const SFX = {
	boot: () => blip(220, 0.12, 'sawtooth'),
	tick: () => blip(880, 0.03, 'square'),
	fold: () => blip(330, 0.06, 'triangle'),
	peel: () => blip(520, 0.15, 'sine'),
	wish: () => {
		blip(440, 0.06);
		setTimeout(() => blip(660, 0.08), 60);
		setTimeout(() => blip(880, 0.12), 140);
	},
	start: () => {
		blip(523, 0.08);
		setTimeout(() => blip(659, 0.08), 80);
		setTimeout(() => blip(784, 0.14), 170);
	}
};
