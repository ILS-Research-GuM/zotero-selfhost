<script lang="ts">
	import Page from '$lib/components/Page.svelte';
	import Flash from '$lib/components/Flash.svelte';
	import GroupFields from '$lib/components/GroupFields.svelte';
	import { roleName, translator } from '$lib/i18n';

	let { data } = $props();
	const t = $derived(translator(data.language));
	const group = $derived(data.group);
	const isOwner = $derived(group.role === 'owner');
	const canManage = $derived(isOwner || group.role === 'admin');
	const others = $derived(data.members.filter((m) => m.role !== 'owner'));
</script>

{#snippet button(action: string, userID: number, label: string, role?: string)}
	<form method="post">
		<input type="hidden" name="csrf" value={data.csrf}>
		<input type="hidden" name="action" value={action}><input type="hidden" name="user" value={userID}>
		{#if role}<input type="hidden" name="role" value={role}>{/if}
		<button>{label}</button>
	</form>
{/snippet}

{#snippet confirmForm(action: string, text: string, label: string)}
	<form method="post">
		<input type="hidden" name="csrf" value={data.csrf}>
		<input type="hidden" name="action" value={action}>
		<p><label><input type="checkbox" name="confirm" value="1" required> {text}</label></p>
		<p><button>{label}</button></p>
	</form>
{/snippet}

<Page title={group.name} wide>
	<Flash flash={data.flash} />
	<p><a href={group.libraryURL}>{t('Open library')}</a> · <a href="/settings/groups">{t('All groups')}</a></p>
	{#if group.description !== ''}<p class="description">{group.description}</p>{/if}
	<p>
		{t('Your role: %s.', roleName(t, group.role))}
		{group.libraryEditing === 'members'
			? t('All members can add and change items and files.')
			: t('Only owner and admins can add and change items and files.')}
	</p>

	<h2>{t('Members')}</h2>
	<table>
		<tbody>
			{#each data.members as m (m.userID)}
				<tr>
					<td>{m.username}{m.userID === data.me ? ` (${t('you')})` : ''}</td>
					<td>{roleName(t, m.role)}</td>
					<td>
						{#if m.role !== 'owner' && m.userID !== data.me}
							{#if isOwner}
								{#if m.role === 'admin'}
									{@render button('role', m.userID, t('Make member'), 'member')}
								{:else}
									{@render button('role', m.userID, t('Make admin'), 'admin')}
								{/if}
							{/if}
							{#if isOwner || (canManage && m.role === 'member')}
								{@render button('remove', m.userID, t('Remove'))}
							{/if}
						{/if}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>

	{#if canManage}
		<h2>{t('Add colleague')}</h2>
		<form method="post">
			<input type="hidden" name="csrf" value={data.csrf}>
			<input type="hidden" name="action" value="add">
			<p>
				<label>{t('Username or email')}<br><input name="login" list="accounts" required autocomplete="off"></label>
				<datalist id="accounts">{#each data.usernames as u (u)}<option value={u}></option>{/each}</datalist>
			</p>
			<p>{t('Colleagues appear here after they have logged in once. New members can read; whether they can edit depends on the group settings. Admins can also manage members.')}</p>
			<p><button>{t('Add')}</button></p>
		</form>
	{/if}

	{#if isOwner}
		<h2>{t('Settings')}</h2>
		<form method="post">
			<input type="hidden" name="csrf" value={data.csrf}>
			<input type="hidden" name="action" value="settings">
			<GroupFields {t} {group} />
			<p><button>{t('Save')}</button></p>
		</form>
		{#if others.length}
			<h2>{t('Transfer ownership')}</h2>
			<form method="post">
				<input type="hidden" name="csrf" value={data.csrf}>
				<input type="hidden" name="action" value="transfer">
				<p><select name="user">{#each others as m (m.userID)}<option value={m.userID}>{m.username}</option>{/each}</select></p>
				<p><label><input type="checkbox" name="confirm" value="1" required> {t('I want to hand the group over. I stay in the group as admin.')}</label></p>
				<p><button>{t('Transfer ownership')}</button></p>
			</form>
		{/if}
		<h2>{t('Delete group')}</h2>
		{@render confirmForm('delete', t('Delete the group with all its items and files for all members. This cannot be undone.'), t('Delete group'))}
	{:else}
		<h2>{t('Leave group')}</h2>
		{@render confirmForm('leave', t('I want to leave the group. Only an owner or admin can add me again.'), t('Leave group'))}
	{/if}
</Page>

<style>
	.description { white-space: pre-line; }
</style>
