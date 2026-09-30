<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import { translator } from '$lib/i18n';

	let { data } = $props();
	const t = $derived(translator(data.language));
</script>

<Page title={t('Downloads')} wide>
	{#if data.html !== null}
		<!-- Written by the admin of this server -->
		{@html data.html}
	{:else if data.files.length}
		<ul>{#each data.files as f (f)}<li><a href="/downloads/{f}">{f}</a></li>{/each}</ul>
	{:else}
		<p>{t('There are no downloads.')}</p>
	{/if}
</Page>
