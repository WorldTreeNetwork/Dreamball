import { describe, expect, it } from 'vitest';
import { sampleCurve, StagePlayer, starStage, type StageEvent } from './star-stage.js';

describe('animation clock and channels', () => {
	it('interpolates and clamps curves, including exact step boundaries', () => {
		const keys = [
			[0, 2],
			[2, 6]
		] as const;
		expect(sampleCurve({ keys, interpolation: 'linear' }, 0.5)).toBe(3);
		expect(sampleCurve({ keys, interpolation: 'smooth' }, 0.5)).toBe(2.625);
		expect(sampleCurve({ keys, interpolation: 'step' }, 1.9)).toBe(2);
		expect(sampleCurve({ keys, interpolation: 'step' }, 2)).toBe(6);
		expect(sampleCurve({ keys, interpolation: 'linear' }, -1)).toBe(2);
		expect(sampleCurve({ keys, interpolation: 'linear' }, 4)).toBe(6);
	});
	it('loops exactly and samples the same pose regardless of frame partition', () => {
		const a = new StagePlayer(starStage);
		const b = new StagePlayer(JSON.parse(JSON.stringify(starStage)));
		a.advance(0.75);
		for (let i = 0; i < 3; i++) b.advance(0.25);
		expect(a.pose()).toEqual(b.pose());
		a.advance(4);
		expect(a.pose()).toEqual(b.pose());
	});
	it('scopes reactions, ignores repeated touches, and emits completion once even across a large step', () => {
		const events: StageEvent[] = [];
		const player = new StagePlayer(starStage, (event) => events.push(event));
		const other = new StagePlayer(starStage);
		expect(player.send('other.touch')).toBe(false);
		expect(player.send('star.touch')).toBe(true);
		expect(player.send('star.touch')).toBe(false);
		player.advance(0.65);
		expect(player.pose().y).toBeGreaterThan(0.6);
		expect(other.reacting).toBe(false);
		player.advance(5);
		player.advance(5);
		expect(events).toEqual([
			{ channel: 'reaction.started', at: 0 },
			{ channel: 'reaction.finished', at: 1.8 }
		]);
		expect(player.reacting).toBe(false);
	});
	it('seeking cancels a reaction without replaying side effects', () => {
		const events: StageEvent[] = [];
		const player = new StagePlayer(starStage, (event) => events.push(event));
		player.send('star.touch');
		player.seek(2);
		expect(player.reacting).toBe(false);
		expect(events.map((event) => event.channel)).toEqual([
			'reaction.started',
			'reaction.cancelled'
		]);
		expect(player.pose().y).toBe(0);
		player.advance(NaN);
		player.seek(Infinity);
		expect(player.time).toBe(2);
	});
});
