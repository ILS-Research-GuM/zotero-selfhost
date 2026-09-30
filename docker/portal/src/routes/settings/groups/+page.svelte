<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Flash from '$lib/components/Flash.svelte';
	import GroupFields from '$lib/components/GroupFields.svelte';
	import { roleName, translator } from '$lib/i18n';

	let { data } = $props();
	const t = $derived(translator(data.language));
</script>

<Page title={t('Groups')} wide>
	<Flash flash={data.flash} />
	<p><a href="/">{t('Back to the library')}</a></p>
	{#if data.groups.length}
		<table>
			<tbody>
				<tr><th>{t('Group')}</th><th>{t('Your role')}</th><th>{t('Members')}</th><th></th></tr>
				{#each data.groups as g (g.groupID)}
					<tr>
						<td><a href={g.libraryURL}>{g.name}</a></td>
						<td>{roleName(t, g.role)}</td>
						<td>{g.members}</td>
						<td><a href="/settings/groups/{g.groupID}">{t('Manage')}</a></td>
					</tr>
				{/each}
			</tbody>
		</table>
	{:else}
		<p>{t('You are not a member of any group yet.')}</p>
	{/if}
	<h2>{t('New group')}</h2>
	<p>{t('Groups are private: only their members see them. You become the owner and can then add colleagues.')}</p>
	<form method="post">
		<input type="hidden" name="csrf" value={data.csrf}>
		<input type="hidden" name="action" value="create">
		<GroupFields {t} />
		<p><button>{t('Create group')}</button></p>
	</form>
</Page>
