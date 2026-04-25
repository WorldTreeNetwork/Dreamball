<!--
  ResonanceSearch.svelte — K-NN resonance search UI (S6.3 AC10).

  Props:
    hits       — KnnHit[] to display (online mode: non-empty array)
    offline    — boolean: true when OfflineKnnError was thrown
    loading    — boolean: true while kNN call is in-flight

  Online mode: renders inscription cards with fp (truncated) + distance badge.
  Offline mode: renders "offline — cached-only" indicator (no blank screen).
  Loading mode: renders a subtle pulse indicator.

  No console errors past the catch boundary (AC10).
  The OfflineKnnError is caught by the consumer and this component only sees
  the resulting `offline=true` prop — it never receives the raw error.
-->
<script lang="ts">
  import type { KnnHit } from '../../memory-palace/store-types.js';

  interface Props {
    hits?: KnnHit[];
    offline?: boolean;
    loading?: boolean;
  }

  let { hits = [], offline = false, loading = false }: Props = $props();
</script>

<div class="resonance-search" role="region" aria-label="Resonance search results">
  {#if loading}
    <div class="status loading" aria-live="polite" data-testid="loading-indicator">
      <span class="pulse">searching resonance&hellip;</span>
    </div>
  {:else if offline}
    <div class="status offline" role="status" aria-live="polite" data-testid="offline-indicator">
      <span class="icon">&#9673;</span>
      <span>offline &mdash; cached-only</span>
    </div>
  {:else if hits.length === 0}
    <div class="status empty" data-testid="empty-indicator">
      <span>no resonant inscriptions found</span>
    </div>
  {:else}
    <ol class="hit-list" data-testid="hit-list">
      {#each hits as hit, i (hit.fp)}
        <li class="hit-card" data-testid="hit-card">
          <span class="rank">#{i + 1}</span>
          <span class="fp" title={hit.fp}>{hit.fp.slice(0, 12)}&hellip;</span>
          <span class="room" title={hit.roomFp}>room: {hit.roomFp.slice(0, 8)}&hellip;</span>
          <span class="badge distance" data-testid="distance-badge">
            d={hit.distance.toFixed(4)}
          </span>
        </li>
      {/each}
    </ol>
  {/if}
</div>

<style>
  .resonance-search {
    font-family: monospace;
    padding: 1rem;
    background: #0b1020;
    color: #c0cce0;
    border-radius: 6px;
    min-height: 80px;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0;
    font-size: 0.875rem;
  }

  .offline {
    color: #f0a050;
  }

  .offline .icon {
    font-size: 1rem;
  }

  .loading .pulse {
    opacity: 0.7;
    font-style: italic;
  }

  .empty {
    color: #6070a0;
    font-style: italic;
  }

  .hit-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .hit-card {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.4rem 0.6rem;
    background: #151a30;
    border-radius: 4px;
    font-size: 0.8rem;
  }

  .rank {
    color: #5080c0;
    min-width: 2rem;
  }

  .fp {
    flex: 1;
    color: #80b0e0;
  }

  .room {
    color: #6070a0;
    font-size: 0.75rem;
  }

  .badge {
    padding: 0.15rem 0.5rem;
    border-radius: 3px;
    font-size: 0.75rem;
    font-weight: bold;
  }

  .distance {
    background: #1a3040;
    color: #40c080;
  }
</style>
