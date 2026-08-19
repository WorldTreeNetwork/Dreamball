<!--
  ShellLens stories — canonical DreamBall container mesh (Star Tamagotchi).
  Happy path loads the served GLB. Placeholder path uses a missing URL so
  the crystal fallback is visible without depending on a network 404 of the
  real asset.
-->
<script module lang="ts">
	import { defineMeta } from '@storybook/addon-svelte-csf';
	import ShellLens from '$lib/lenses/ShellLens.svelte';
	import { mockBall } from '$lib/backend/MockBackend.js';
	import { SHELL_MESH_URL } from '$lib/lenses/shell-mesh.js';

	const { Story } = defineMeta({
		title: 'Lenses/ShellLens',
		component: ShellLens,
		tags: ['autodocs']
	});
</script>

<Story name="Star Tamagotchi (canonical shell)">
	{#snippet children()}
		{@const ball = mockBall('avatar', { name: 'Star Tamagotchi' })}
		<div style="width: 400px; height: 400px;">
			<ShellLens {ball} meshUrl={SHELL_MESH_URL} />
		</div>
	{/snippet}
</Story>

<Story name="Placeholder (failed mesh)">
	{#snippet children()}
		{@const ball = mockBall('avatar', { name: 'Missing shell' })}
		<div style="width: 400px; height: 400px;">
			<ShellLens {ball} meshUrl="/characters/no-such-shell.glb" />
		</div>
	{/snippet}
</Story>
