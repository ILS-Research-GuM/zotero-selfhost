<!--
User guide template for deployers. Copy it, fill in the placeholders and remove what doesn't apply, then
hand it to your users. Rendered, this comment is invisible.

Placeholders (most match .env):
  {{SERVER_NAME}}        how users know your server, e.g. "the Example Institute server"
  {{SERVER_NAME_DE}}     the same in German, e.g. "dem Server des Beispiel-Instituts"
  {{WEB_LIBRARY_URL}}    WEB_LIBRARY_URL, e.g. https://zotero.example.org
  {{ZOTERO_API_URL}}     ZOTERO_API_URL with a trailing /, e.g. https://api.zotero.example.org/
  {{STREAMING_URL}}      STREAMING_URL with a trailing /, e.g. wss://stream.zotero.example.org/
  {{OIDC_LABEL}}         OIDC_LABEL, the name on the login button, e.g. "Example ID"
  {{SHARED_GROUP_NAME}}  DEFAULT_GROUP_NAME, only with SHARED_GROUP_OWNER
  {{CONTACT}}            who users contact, e.g. "the IT service desk (it@example.org)"
  {{CONTACT_DE}}         the same in German

Sections marked with [OIDC], [PASSWORD], [BOTH] (OIDC and PASSWORD_LOGIN=true) or [SHARED GROUP]
depend on your configuration: keep the matching ones, delete the others and the markers.
The portal shows its pages in English or German depending on the browser, so both button texts are given.

Example: sed -e 's|{{WEB_LIBRARY_URL}}|https://zotero.example.org|g' ... USER-GUIDE-template.md > USER-GUIDE.md
-->

# Zotero on {{SERVER_NAME}} – User Guide / Anleitung

[English](#english) · [Deutsch](#deutsch)

---

<a id="english"></a>
## English

{{SERVER_NAME}} runs its own Zotero server. Your library and your PDFs are stored there, not at zotero.org.

<!-- [OIDC] -->
You log in with your {{OIDC_LABEL}} account.
<!-- [PASSWORD] -->
You log in with the username and password you received from {{CONTACT}}.
<!-- [BOTH] -->
You log in with your {{OIDC_LABEL}} account. If you don't have one, you get a username and password from
{{CONTACT}}.
<!-- [END] -->

### Web library (browser)

1. Open **{{WEB_LIBRARY_URL}}**.
2. Log in:
   <!-- [OIDC] -->
   Log in with your {{OIDC_LABEL}} account.
   <!-- [PASSWORD] -->
   Enter your username (or email) and password and click **Log in** (German: **Anmelden**).
   <!-- [BOTH] -->
   Click **Log in with {{OIDC_LABEL}}** (German: **Anmelden mit {{OIDC_LABEL}}**). Without such an account, use
   the username and password form below the button.
   <!-- [END] -->
3. You see **My Library**<!-- [SHARED GROUP] --> and the group **{{SHARED_GROUP_NAME}}**<!-- [END] -->.

<!-- [OIDC] [BOTH] -->
On your first login your Zotero account is created automatically.
<!-- [END] -->
Your library starts out empty until you sync the desktop app or add items.

### Desktop app

#### 1. Install Zotero

Install the official Zotero app from https://www.zotero.org/download/ (version 10 or newer).
If Zotero is already installed, you can keep it.

#### 2. Point Zotero to {{SERVER_NAME}}

This is done once per computer.

1. Open **Edit → Settings** (macOS: **Zotero → Settings**).
2. Go to **Advanced** and click **Config Editor**. Confirm the warning.
3. Add the first setting:
   - Right-click in the list and choose **New → String**. In newer versions, type the name into the search field and click **+** with type **String**.
   - Name: `extensions.zotero.api.url`
   - Value: `{{ZOTERO_API_URL}}`
4. Add the second setting the same way:
   - Name: `extensions.zotero.streaming.url`
   - Value: `{{STREAMING_URL}}`
5. Check both values carefully, including the `/` at the end.
6. **Quit Zotero completely and start it again.**

#### 3. Log in

1. Open **Settings → Account** (older versions: **Sync**) and click **Log In**.
2. Your browser opens the login page. Log in as in the web library (step 2 above).
3. Confirm with **Connect** on the page "Connect Zotero" (German: **Verbinden** on "Zotero verbinden").
4. Return to Zotero. It now syncs with {{SERVER_NAME}}.

**Check:** After clicking *Log In*, the address in your browser must start with
`{{WEB_LIBRARY_URL}}/`. If you see zotero.org instead, step 2 didn't work.
Click **Cancel** in Zotero, check both settings, restart Zotero and try again.

<!-- [SHARED GROUP] -->
### Group "{{SHARED_GROUP_NAME}}"

Every user is a member of this group and can **read** it. Adding or changing entries is limited to selected
people. If you'd like to contribute, contact {{CONTACT}}.
<!-- [END] -->

### Your own groups

To share references with colleagues, create a group: in the web library, open **Groups** in the menu at
the top ({{WEB_LIBRARY_URL}}/settings/groups), then **New group**. Add colleagues by username or email; they appear
once they have logged in at least once. You decide whether all members or only admins may edit. In the
desktop app, the group shows up with the next sync. Don't use **New Group…** in the desktop app: it opens
zotero.org, not this server.

### Good to know

- **Switching from zotero.org:** If your Zotero was connected to a zotero.org account, first choose
  **Unlink Account** in Settings → Account, and keep your local data. Then follow steps 2 and 3. Your local
  library is uploaded to {{SERVER_NAME}} on the first sync. Your data at zotero.org stays there and is no longer
  updated.
- **Links to zotero.org** in the app ("Create account", "Sync with zotero.org", "View online") still point to
  zotero.org. You don't need a zotero.org account.
- **Word and LibreOffice plugins** and the **browser connector** work as usual. They talk to the Zotero app on
  your computer, not to the server.
- **Every computer** needs step 2 once.
- **Web library looks broken after an update:** reload the page with **Ctrl+F5** (macOS: **Cmd+Shift+R**).
- **Questions and problems:** contact {{CONTACT}}.

---

<a id="deutsch"></a>
## Deutsch

Auf {{SERVER_NAME_DE}} läuft ein eigener Zotero-Server. Deine Bibliothek und deine PDFs liegen dort, nicht bei
zotero.org.

<!-- [OIDC] -->
Du meldest dich mit deinem {{OIDC_LABEL}}-Konto an.
<!-- [PASSWORD] -->
Du meldest dich mit dem Benutzernamen und Passwort an, die du von {{CONTACT_DE}} bekommen hast.
<!-- [BOTH] -->
Du meldest dich mit deinem {{OIDC_LABEL}}-Konto an. Wenn du keins hast, bekommst du Benutzername und Passwort
von {{CONTACT_DE}}.
<!-- [END] -->

### Web-Bibliothek (Browser)

1. **{{WEB_LIBRARY_URL}}** öffnen.
2. Anmelden:
   <!-- [OIDC] -->
   Mit dem {{OIDC_LABEL}}-Konto anmelden.
   <!-- [PASSWORD] -->
   Benutzername (oder E-Mail) und Passwort eingeben und auf **Anmelden** klicken.
   <!-- [BOTH] -->
   Auf **Anmelden mit {{OIDC_LABEL}}** klicken. Ohne solches Konto das Formular für Benutzername und Passwort
   unter dem Knopf nutzen.
   <!-- [END] -->
3. Du siehst **My Library**<!-- [SHARED GROUP] --> und die Gruppe **{{SHARED_GROUP_NAME}}**<!-- [END] -->.

<!-- [OIDC] [BOTH] -->
Beim ersten Login wird dein Zotero-Konto automatisch angelegt.
<!-- [END] -->
Deine Bibliothek bleibt leer, bis du die Desktop-App synchronisierst oder Einträge hinzufügst.

### Desktop-App

#### 1. Zotero installieren

Die offizielle Zotero-App von https://www.zotero.org/download/ installieren (Version 10 oder neuer).
Ein bereits installiertes Zotero kannst du weiterverwenden.

#### 2. Zotero auf {{SERVER_NAME_DE}} umstellen

Das ist einmal pro Computer nötig.

1. **Bearbeiten → Einstellungen** öffnen (macOS: **Zotero → Einstellungen**).
2. Zu **Erweitert** wechseln und auf **Config Editor** klicken. Die Warnung bestätigen.
3. Die erste Einstellung anlegen:
   - Rechtsklick in die Liste, dann **Neu → String**. In neueren Versionen den Namen ins Suchfeld tippen und mit Typ **String** auf **+** klicken.
   - Name: `extensions.zotero.api.url`
   - Wert: `{{ZOTERO_API_URL}}`
4. Die zweite Einstellung genauso anlegen:
   - Name: `extensions.zotero.streaming.url`
   - Wert: `{{STREAMING_URL}}`
5. Beide Werte genau prüfen, auch den `/` am Ende.
6. **Zotero komplett beenden und neu starten.**

#### 3. Anmelden

1. **Einstellungen → Benutzerkonto** öffnen (ältere Versionen: **Sync**) und auf **Anmelden** klicken.
2. Der Browser öffnet die Anmeldeseite. Wie bei der Web-Bibliothek anmelden (Schritt 2 oben).
3. Auf der Seite "Zotero verbinden" mit **Verbinden** bestätigen.
4. Zurück zu Zotero wechseln. Zotero synchronisiert jetzt mit {{SERVER_NAME_DE}}.

**Prüfen:** Nach dem Klick auf *Anmelden* muss die Adresse im Browser mit
`{{WEB_LIBRARY_URL}}/` beginnen. Erscheint stattdessen zotero.org, hat Schritt 2 nicht geklappt. Dann in
Zotero **Abbrechen** klicken, beide Einstellungen prüfen, Zotero neu starten und es erneut versuchen.

<!-- [SHARED GROUP] -->
### Gruppe "{{SHARED_GROUP_NAME}}"

Alle Nutzerinnen und Nutzer sind Mitglied dieser Gruppe und können sie **lesen**. Einträge hinzufügen oder
ändern dürfen nur ausgewählte Personen. Wer beitragen möchte, wendet sich an {{CONTACT_DE}}.
<!-- [END] -->

### Eigene Gruppen

Um Literatur mit Kollegen zu teilen, lege eine Gruppe an: In der Web-Bibliothek oben im Menü **Gruppen**
öffnen ({{WEB_LIBRARY_URL}}/settings/groups), dann **Neue Gruppe**. Kollegen fügst du über Benutzernamen oder E-Mail
hinzu; sie erscheinen, sobald sie sich einmal angemeldet haben. Du legst fest, ob alle Mitglieder oder nur
Admins bearbeiten dürfen. In der Desktop-App erscheint die Gruppe mit der nächsten Synchronisation.
**Neue Gruppe…** in der Desktop-App bitte nicht verwenden: Das öffnet zotero.org, nicht diesen Server.

### Gut zu wissen

- **Wechsel von zotero.org:** War dein Zotero mit einem Konto bei zotero.org verbunden, zuerst unter
  Einstellungen → Benutzerkonto **Konto trennen** wählen und die lokalen Daten behalten. Danach die Schritte 2
  und 3 ausführen. Beim ersten Sync wird deine lokale Bibliothek hochgeladen. Deine Daten bei zotero.org
  bleiben dort erhalten, werden aber nicht mehr aktualisiert.
- **Links zu zotero.org** in der App ("Account erstellen", "Sync mit zotero.org", "Online ansehen") zeigen
  weiterhin auf zotero.org. Ein Konto bei zotero.org brauchst du nicht.
- **Word- und LibreOffice-Plugins** sowie der **Browser-Connector** funktionieren wie gewohnt. Sie sprechen mit
  der Zotero-App auf deinem Computer, nicht mit dem Server.
- **Jeder Computer** braucht Schritt 2 einmal.
- **Web-Bibliothek sieht nach einem Update falsch aus:** Seite mit **Strg+F5** neu laden
  (macOS: **Cmd+Shift+R**).
- **Fragen und Probleme:** an {{CONTACT_DE}} wenden.
