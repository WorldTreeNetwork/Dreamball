/**
 * Shared selection state. What the user last clicked in the Outliner.
 * Consumers read .path/.label/.kind and react. Blender calls this the
 * "active" item; we call it selection because Phase 0 is single-select.
 *
 * Exposed via Svelte context at the `wt-selection` key.
 */

export interface OutlinerItem {
	path: string[];
	label: string;
	kind: string;
	detail?: string;
}

export const SELECTION_KEY = Symbol('wt-selection');

export class Selection {
	path: string[] = $state([]);
	label: string = $state('— nothing selected —');
	kind: string = $state('');
	detail: string = $state('');

	select(item: OutlinerItem): void {
		this.path = item.path;
		this.label = item.label;
		this.kind = item.kind;
		this.detail = item.detail ?? '';
	}

	clear(): void {
		this.path = [];
		this.label = '— nothing selected —';
		this.kind = '';
		this.detail = '';
	}

	pathString(): string {
		return this.path.length === 0 ? '/' : '/' + this.path.join('/');
	}
}
