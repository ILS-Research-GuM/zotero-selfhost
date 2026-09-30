<script lang="ts">
	let { flash }: { flash: { error: boolean; text: string } | null } = $props();
</script>

{#if flash}<p class={flash.error ? 'error' : 'ok'}><b>{flash.text}</b></p>{/if}

<style>
	/* Global: scoped classes would get a suffix, and tests look for class="ok" / class="error" */
	:global(.error) { color: #c00; }
	:global(.ok) { color: #080; }
	:global(td form) { display: inline; }
	:global(td button) { padding: .1rem .6rem; font-size: .9rem; }
	:global(input:not([type=checkbox])), :global(textarea), :global(select) { font: inherit; width: 100%; box-sizing: border-box; }
	:global(tr) { border-bottom: 1px solid rgba(127, 127, 127, .3); }
</style>
