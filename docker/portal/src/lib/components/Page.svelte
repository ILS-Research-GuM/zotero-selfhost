<script lang="ts">
	// Frame of every portal page: title, language switcher, narrow or wide column
	import type { Snippet } from 'svelte';
	import { page } from '$app/state';
	import { languageNames } from '$lib/i18n';

	let { title, wide = false, children }: { title: string; wide?: boolean; children: Snippet } = $props();
	const languages = $derived(page.data.languages ?? []);
</script>

<svelte:head><title>{title}</title></svelte:head>

<main class:wide>
	{#if languages.length > 1}
		<nav class="lang">
			{#each languages as l (l)}
				{#if l === page.data.language}
					<b>{languageNames[l] ?? l}</b>
				{:else}
					<a href="{page.url.pathname}?lang={l}" hreflang={l}>{languageNames[l] ?? l}</a>
				{/if}
			{/each}
		</nav>
	{/if}
	<h1>{title}</h1>
	{@render children()}
</main>

<style>
	:global(body) { font: 16px/1.5 system-ui, sans-serif; margin: 0; color: #222; }
	main { max-width: 32rem; margin: 4rem auto; padding: 0 1rem; }
	main.wide { max-width: 48rem; }
	:global(button) { font: inherit; padding: .5rem 1.2rem; margin-right: .5rem; cursor: pointer; }
	:global(code) { background: rgba(127, 127, 127, .15); padding: 0 .2em; border-radius: 3px; }
	:global(table) { border-collapse: collapse; }
	:global(td), :global(th) { padding: .2rem .8rem .2rem 0; text-align: left; }
	:global(a) { color: #2563eb; }
	@media (prefers-color-scheme: dark) {
		:global(body) { background: #1e1e1e; color: #ddd; }
		:global(a) { color: #7aa7ff; }
	}
	.lang { float: right; font-size: .85rem; }
	.lang a, .lang b { margin-left: .5rem; }
</style>
