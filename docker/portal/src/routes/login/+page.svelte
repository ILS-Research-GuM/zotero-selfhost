<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import { translator } from '$lib/i18n';
	import { bold } from '$lib/html';

	let { data } = $props();
	const t = $derived(translator(data.language));
</script>

{#if data.outcome === 'cancelled'}
	<Page title={t('Cancelled')}>
		<p>{t('Zotero was not connected. You can close this window.')}</p>
	</Page>
{:else if data.outcome === 'connected'}
	<Page title={t('Zotero is connected')}>
		<p>{@html t('Zotero now syncs with the account %s. You can close this window and return to Zotero.', bold(data.username ?? ''))}</p>
	</Page>
{:else}
	<Page title={t('Connect Zotero')}>
		<p>{@html t('Should %s on your device get access to your Zotero library (account %s)?', bold(data.client ?? ''), bold(data.username ?? ''))}</p>
		<p>{t('Only confirm if you just started the login in Zotero yourself.')}</p>
		<form method="post">
			<input type="hidden" name="session" value={data.sessionToken}>
			<input type="hidden" name="csrf" value={data.csrf}>
			<button name="action" value="allow">{t('Connect')}</button><button name="action" value="deny">{t('Cancel')}</button>
		</form>
	</Page>
{/if}
