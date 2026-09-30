<script lang="ts">
	// Fields for name, description and who may edit, prefilled from the group
	import type { Translator } from '$lib/i18n';

	let { t, group = {} }: { t: Translator; group?: { name?: string; description?: string; libraryEditing?: string } } = $props();
	const editing = $derived(group.libraryEditing ?? 'members');
</script>

<p><label>{t('Name')}<br><input name="name" maxlength="100" required value={group.name ?? ''}></label></p>
<p><label>{t('Description (optional)')}<br><textarea name="description" rows="2" maxlength="1000">{group.description ?? ''}</textarea></label></p>
<p><label>{t('Who can add and change items and files?')}<br>
	<select name="editing">
		<option value="members" selected={editing === 'members'}>{t('All members')}</option>
		<option value="admins" selected={editing === 'admins'}>{t('Only owner and admins')}</option>
	</select>
</label></p>
