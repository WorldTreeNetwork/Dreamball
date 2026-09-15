// Run with Vite serving: node tests/animation/star-stage.smoke.mjs
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const browser = await chromium.launch({ headless: true });
const url = process.env.STAR_STAGE_URL ?? 'http://127.0.0.1:5178/demo/star';
const errors = [];
try {
	const page = await browser.newPage({ viewport: { width: 1100, height: 950 } });
	page.on('pageerror', (error) => errors.push(error.message));
	await page.goto(url);
	const stage = page.locator('[data-ready="true"]');
	await stage.waitFor();
	const frames = async () => Number(await stage.getAttribute('data-frames'));
	let before = await frames();
	await page.waitForTimeout(1100);
	const rendered = (await frames()) - before;
	assert(rendered > 0 && rendered <= 34, `30 fps ceiling: ${rendered} frames / 1.1s`);
	await page.getByRole('button', { name: 'Pause animation' }).click();
	before = await frames();
	await page.waitForTimeout(500);
	assert.equal(await frames(), before, 'paused player must not redraw');
	assert.equal(await page.getByRole('slider').count(), 0, 'viewer has no timeline scrubber');
	assert.equal(await page.locator('output').count(), 0, 'viewer has no time readout');
	await page.getByRole('button', { name: 'Say hello to Star', exact: true }).click();
	await page.waitForFunction(
		() => document.querySelector('[data-reacting]')?.getAttribute('data-reacting') === 'true'
	);
	await page.waitForFunction(
		() => document.querySelector('[data-reacting]')?.getAttribute('data-reacting') === 'false'
	);
	// Exercise the visibility handler without depending on headless window-manager focus.
	await page.evaluate(() => {
		Object.defineProperty(document, 'hidden', { configurable: true, value: true });
		document.dispatchEvent(new Event('visibilitychange'));
	});
	before = await frames();
	await page.waitForTimeout(500);
	assert.equal(await frames(), before, 'hidden player must not redraw');
	await page.evaluate(() => {
		delete document.hidden;
		document.dispatchEvent(new Event('visibilitychange'));
	});
	await page.getByRole('button', { name: 'Pause animation' }).click();
	await page.screenshot({ path: '/tmp/star-stage-desktop.png' });
	await page.setViewportSize({ width: 375, height: 812 });
	await page.waitForTimeout(150);
	assert(
		await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
		'mobile must not overflow'
	);
	await page.screenshot({ path: '/tmp/star-stage-mobile.png' });
	await page.getByRole('button', { name: 'Play animation' }).click();
	await page.evaluate(() => {
		document.body.style.paddingBottom = '1500px';
		window.scrollTo(0, document.body.scrollHeight);
	});
	await page.waitForTimeout(200);
	before = await frames();
	await page.waitForTimeout(500);
	assert.equal(await frames(), before, 'offscreen player must not redraw');
	await page.close();
	const reduced = await browser.newPage({ reducedMotion: 'reduce' });
	await reduced.goto(url);
	await reduced.locator('[data-ready="true"]').waitFor();
	const stillFrames = await reduced.locator('[data-frames]').getAttribute('data-frames');
	await reduced.waitForTimeout(500);
	assert.equal(await reduced.locator('[data-frames]').getAttribute('data-frames'), stillFrames);
	await reduced.getByRole('button', { name: 'Say hello to Star', exact: true }).click();
	assert.match(await reduced.locator('body').innerText(), /Star is happy you’re here/);
	assert.equal(await reduced.locator('[data-reacting]').getAttribute('data-reacting'), 'false');
	await reduced.close();
	const invalid = await browser.newPage();
	await invalid.route('**/characters/star-tamagotchi.ball', (route) =>
		route.fulfill({ body: Buffer.from([0]), contentType: 'application/ball+cbor' })
	);
	await invalid.goto(url);
	await invalid.getByRole('alert').waitFor();
	assert.equal(
		await invalid.locator('canvas').count(),
		0,
		'invalid capsule must not reach the renderer'
	);
	assert.deepEqual(errors, []);
	console.log(
		`PASS: idle (${rendered} frames/1.1s), pause, no timeline controls, reaction, hidden/offscreen suspension, mobile, reduced motion, invalid capsule.`
	);
} finally {
	await browser.close();
}
