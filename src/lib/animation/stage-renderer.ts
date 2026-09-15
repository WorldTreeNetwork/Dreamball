import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { StagePlayer, starStage } from './star-stage.js';

export type StageState = {
	time: number;
	playing: boolean;
	reacting: boolean;
	ready: boolean;
	reduced: boolean;
	frames: number;
};

function disposeModel(root: THREE.Object3D) {
	const textures = new Set<THREE.Texture>();
	root.traverse((object) => {
		if (!(object instanceof THREE.Mesh)) return;
		object.geometry.dispose();
		for (const material of Array.isArray(object.material) ? object.material : [object.material]) {
			for (const value of Object.values(material))
				if (value instanceof THREE.Texture) textures.add(value);
			material.dispose();
		}
	});
	for (const texture of textures) {
		texture.dispose();
		const bitmap = texture.source.data;
		if (typeof ImageBitmap !== 'undefined' && bitmap instanceof ImageBitmap) bitmap.close();
	}
}

/** Three adapter; the animation player has no dependency on Three or the DOM. */
export function createStageRenderer(
	canvas: HTMLCanvasElement,
	url: string,
	onstate: (state: StageState) => void,
	onerror: (message: string) => void
) {
	const renderer = new THREE.WebGLRenderer({
		canvas,
		alpha: true,
		antialias: true,
		powerPreference: 'low-power'
	});
	renderer.toneMapping = THREE.ACESFilmicToneMapping;
	renderer.toneMappingExposure = 0.95;
	const scene = new THREE.Scene();
	const camera = new THREE.PerspectiveCamera(36, 1, 0.1, 40);
	camera.position.set(0, 1.9, 6.5);
	camera.lookAt(0, 1.35, 0);
	const actor = new THREE.Group();
	scene.add(actor);
	const room = new RoomEnvironment();
	const pmrem = new THREE.PMREMGenerator(renderer);
	const environment = pmrem.fromScene(room, 0.04, 0.1, 100, { size: 128 });
	room.dispose();
	pmrem.dispose();
	scene.environment = environment.texture;
	scene.environmentIntensity = 0.85;
	const key = new THREE.DirectionalLight('#fff0d5', 1.6);
	key.position.set(3, 5, 4);
	const rim = new THREE.DirectionalLight('#b9dce9', 1.2);
	rim.position.set(-3, 2, -2);
	scene.add(key, rim, new THREE.HemisphereLight('#e5f6ff', '#41344b', 1));
	// Painted contact shadow: one quad, no shadow map or postprocess.
	const shadowCanvas = document.createElement('canvas');
	shadowCanvas.width = shadowCanvas.height = 64;
	const context = shadowCanvas.getContext('2d')!;
	const gradient = context.createRadialGradient(32, 32, 1, 32, 32, 32);
	gradient.addColorStop(0, 'rgba(7, 18, 23, 0.3)');
	gradient.addColorStop(1, 'rgba(7, 18, 23, 0)');
	context.fillStyle = gradient;
	context.fillRect(0, 0, 64, 64);
	const shadow = new THREE.Mesh(
		new THREE.PlaneGeometry(2.6, 1.3),
		new THREE.MeshBasicMaterial({
			map: new THREE.CanvasTexture(shadowCanvas),
			transparent: true,
			depthWrite: false
		})
	);
	shadow.rotation.x = -Math.PI / 2;
	scene.add(shadow);
	const player = new StagePlayer(starStage);
	const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
	let reduced = preference.matches;
	let playing = !reduced;
	let ready = false;
	let disposed = false;
	let visible = false;
	let frames = 0;
	let timer: ReturnType<typeof setTimeout> | undefined;
	let previous = performance.now();
	let model: THREE.Object3D | undefined;
	const report = () =>
		onstate({
			time: player.time % starStage.idle.duration,
			playing,
			reacting: player.reacting,
			ready,
			reduced,
			frames
		});
	const active = () => !disposed && ready && visible && !document.hidden;
	function draw() {
		if (!active()) return;
		const pose = player.pose();
		actor.position.y = 1.22 + pose.y;
		actor.rotation.set(0, pose.turn, pose.tilt);
		actor.scale.set(
			1 / Math.sqrt(1 + pose.stretch),
			1 + pose.stretch,
			1 / Math.sqrt(1 + pose.stretch)
		);
		shadow.scale.setScalar(1 - pose.y * 0.25);
		shadow.material.opacity = 0.85 - pose.y * 0.35;
		renderer.render(scene, camera);
		frames++;
		report();
	}
	function stop() {
		clearTimeout(timer);
		timer = undefined;
	}
	function schedule() {
		stop();
		if (!active() || !playing || reduced) return;
		timer = setTimeout(() => {
			const now = performance.now();
			player.advance((now - previous) / 1000);
			previous = now;
			draw();
			schedule();
		}, 1000 / 30);
	}
	function wake() {
		previous = performance.now();
		draw();
		schedule();
	}
	function resize() {
		const { width, height } = canvas.getBoundingClientRect();
		if (!width || !height) return;
		renderer.setPixelRatio(
			Math.min(window.devicePixelRatio || 1, 1.5, 1200 / Math.max(width, height))
		);
		renderer.setSize(width, height, false);
		camera.aspect = width / height;
		camera.updateProjectionMatrix();
		draw();
	}
	const resizeObserver = new ResizeObserver(resize);
	resizeObserver.observe(canvas);
	const intersection = new IntersectionObserver(([entry]) => {
		visible = entry.isIntersecting;
		wake();
	});
	intersection.observe(canvas);
	document.addEventListener('visibilitychange', wake);
	function motionChanged() {
		reduced = preference.matches;
		playing = !reduced;
		player.seek(0);
		wake();
		report();
	}
	preference.addEventListener('change', motionChanged);
	function contextLost(event: Event) {
		event.preventDefault();
		stop();
		ready = false;
		report();
		onerror('The graphics context was lost. Reload the page to bring Star back.');
	}
	canvas.addEventListener('webglcontextlost', contextLost);
	new GLTFLoader()
		.loadAsync(url)
		.then((gltf) => {
			if (disposed) {
				disposeModel(gltf.scene);
				return;
			}
			model = gltf.scene;
			const box = new THREE.Box3().setFromObject(model);
			const size = box.getSize(new THREE.Vector3());
			const center = box.getCenter(new THREE.Vector3());
			const fitted = new THREE.Group();
			model.position.sub(center);
			fitted.add(model);
			fitted.scale.setScalar(starStage.object.fit / (Math.max(size.x, size.y, size.z) || 1));
			actor.add(fitted);
			ready = true;
			resize();
			wake();
			report();
		})
		.catch((error: unknown) => {
			if (!disposed) onerror(error instanceof Error ? error.message : String(error));
		});
	return {
		toggle() {
			if (reduced) return;
			playing = !playing;
			wake();
			report();
		},
		touch() {
			if (!ready || reduced) return false;
			const accepted = player.send(starStage.trigger.channel);
			playing = true;
			wake();
			report();
			return accepted;
		},
		seek(time: number) {
			playing = false;
			player.seek(time);
			wake();
			report();
		},
		dispose() {
			disposed = true;
			stop();
			resizeObserver.disconnect();
			intersection.disconnect();
			document.removeEventListener('visibilitychange', wake);
			preference.removeEventListener('change', motionChanged);
			canvas.removeEventListener('webglcontextlost', contextLost);
			if (model) disposeModel(model);
			disposeModel(shadow);
			environment.dispose();
			renderer.dispose();
			renderer.forceContextLoss();
		}
	};
}
