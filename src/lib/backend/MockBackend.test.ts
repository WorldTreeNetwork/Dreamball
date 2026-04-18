import { describe, it, expect } from 'vitest';
import { MockBackend, mockBall } from './MockBackend.js';

describe('MockBackend', () => {
	it('mockBall(avatar) has look + feel populated', () => {
		const b = mockBall('avatar');
		expect(b.type).toBe('jelly.dreamball.avatar');
		expect(b.look).toBeDefined();
		expect(b.feel).toBeDefined();
		expect(b.act).toBeUndefined();
	});

	it('mockBall(agent) populates memory + KG + emotional register', () => {
		const b = mockBall('agent');
		expect(b.type).toBe('jelly.dreamball.agent');
		expect(b.memory).toBeDefined();
		expect(b['knowledge-graph']).toBeDefined();
		expect(b['emotional-register']).toBeDefined();
		expect(b.act).toBeDefined();
	});

	it('mockBall(tool) has skill + applicable-to', () => {
		const b = mockBall('tool');
		expect(b.skill).toBeDefined();
		expect(b['applicable-to']).toContain('jelly.dreamball.agent');
	});

	it('mockBall(relic) has sealed-payload-hash + unlock-guild', () => {
		const b = mockBall('relic');
		expect(b['sealed-payload-hash']).toBeDefined();
		expect(b['unlock-guild']).toBeDefined();
	});

	it('mockBall(field) has omnispherical-grid', () => {
		const b = mockBall('field');
		expect(b['omnispherical-grid']).toBeDefined();
		expect(b['omnispherical-grid']?.['layer-depth']).toBe(3);
	});

	it('mockBall(guild) has members + admin + policy', () => {
		const b = mockBall('guild');
		expect(b['guild-name']).toBe('The Hummingbirds');
		expect(b.member?.length ?? 0).toBeGreaterThan(0);
		expect(b.admin?.length ?? 0).toBeGreaterThan(0);
		expect(b.policy).toBeDefined();
	});

	it('resolvePermittedSlots: anonymous observer sees public slots only', async () => {
		const backend = new MockBackend([mockBall('guild')]);
		const guild = (await backend.list())[0].summary;
		const slots = await backend.resolvePermittedSlots(guild, null);
		expect(slots).toContain('name');
		expect(slots).not.toContain('memory');
	});

	it('resolvePermittedSlots: guild member sees guild-only slots', async () => {
		const guild = mockBall('guild');
		const member = guild.member![0];
		const backend = new MockBackend([guild]);
		const slots = await backend.resolvePermittedSlots(guild, member);
		expect(slots).toContain('memory');
	});

	it('resolvePermittedSlots: admin sees admin-only slots', async () => {
		const guild = mockBall('guild');
		const admin = guild.admin![0];
		const backend = new MockBackend([guild]);
		const slots = await backend.resolvePermittedSlots(guild, admin);
		expect(slots).toContain('secret');
	});

	it('unlockRelic rejects non-relic input', async () => {
		const backend = new MockBackend();
		const notARelic = mockBall('avatar');
		await expect(backend.unlockRelic(notARelic, new Uint8Array(32))).rejects.toThrow();
	});

	it('unlockRelic (mock) resolves to a synthetic inner DreamBall', async () => {
		const backend = new MockBackend();
		const relic = mockBall('relic');
		const inner = await backend.unlockRelic(relic, new Uint8Array(32));
		expect(inner.type).toBe('jelly.dreamball.avatar');
	});
});
