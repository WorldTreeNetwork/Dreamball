/**
 * Minimal PlayCanvas app factory for the splat lens.
 *
 * Mirrors the setup in `/Users/dukejones/work/Projects/Family/web3d-space/
 * src/lib/playcanvas/create-app.ts` — same reference implementation the
 * user pointed at for gaussian splat rendering. SSR-safe dynamic import;
 * WebGPU primary with WebGL2 fallback; GSplat component system + handler
 * wired for the `.sog` and `compressed.ply` formats that PlayCanvas
 * natively supports.
 *
 * We keep the import dynamic so consumers that don't need splats pay
 * zero bundle cost for PlayCanvas — it only loads when SplatLens mounts.
 */

export interface PlayCanvasApp {
	pc: typeof import('playcanvas');
	app: import('playcanvas').AppBase;
	device: import('playcanvas').GraphicsDevice;
}

export interface CreateAppOptions {
	canvas: HTMLCanvasElement;
	deviceTypes?: string[];
	maxPixelRatio?: number;
}

export async function createPlayCanvasApp(opts: CreateAppOptions): Promise<PlayCanvasApp> {
	const pc = await import('playcanvas');

	const device = await pc.createGraphicsDevice(opts.canvas, {
		deviceTypes: opts.deviceTypes ?? ['webgpu', 'webgl2'],
		antialias: false // splats don't benefit from AA
	});

	device.maxPixelRatio = opts.maxPixelRatio ?? Math.min(window.devicePixelRatio, 2);

	const createOptions = new pc.AppOptions();
	createOptions.graphicsDevice = device;

	createOptions.componentSystems = [
		pc.RenderComponentSystem,
		pc.CameraComponentSystem,
		pc.LightComponentSystem,
		pc.GSplatComponentSystem
	];
	createOptions.resourceHandlers = [pc.TextureHandler, pc.ContainerHandler, pc.GSplatHandler];

	const app = new pc.AppBase(opts.canvas);
	app.init(createOptions);

	app.setCanvasFillMode(pc.FILLMODE_FILL_WINDOW);
	app.setCanvasResolution(pc.RESOLUTION_AUTO);

	const resize = () => app.resizeCanvas();
	window.addEventListener('resize', resize);
	app.on('destroy', () => window.removeEventListener('resize', resize));

	app.start();

	return { pc, app, device };
}
