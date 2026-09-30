<script lang="ts">
	import { page } from '$app/state';
	import Page from '$lib/components/Page.svelte';
</script>

<Page title={page.error?.title ?? String(page.status)}>
	<p>
		{page.error?.message}
		{#if page.error?.link}<a href={page.error.link.href}>{page.error.link.label}</a>{/if}
	</p>
</Page>
