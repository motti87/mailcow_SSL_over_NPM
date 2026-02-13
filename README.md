# Mailcow SSL Sync via Nginx Proxy Manager (NPM)

Dieses Script automatisiert die Aktualisierung von SSL-Zertifikaten (Let's Encrypt) für eine Mailcow-Instanz, die sich hinter einem Nginx Proxy Manager (NPM) befindet. 

Da bei einer Umgebung mit nur einer öffentlichen IPv4-Adresse Port 80 und 443 vom NPM belegt werden, holt NPM die Zertifikate. Dieses Script holt sich die Zertifikate dynamisch vom NPM-LXC, kopiert sie sicher zur Mailcow, startet die nötigen Container neu und versendet einen Statusbericht per E-Mail.

## Features
- **Dynamische Zertifikatssuche:** Findet automatisch den richtigen `npm-XX` Ordner anhand der Domain (mittels `openssl`).
- **TLSA/DANE Kompatibilität:** Ermöglicht Key-Pinning (Wiederverwendung des Private Keys), damit DANE-Records bei der Zertifikatserneuerung nicht brechen.
- **Integrierter Live-Test:** Prüft nach dem Neustart direkt auf Port 25, ob das neue Zertifikat von Postfix korrekt ausgeliefert wird.
- **Passwortloser Mail-Versand:** Nutzt den internen Docker-Socket der Mailcow, um Status-E-Mails zu versenden (keine Klartext-Passwörter im Script nötig!).

---

## 🚀 Einrichtung & Installation

### 1. DANE/TLSA absichern (Key-Reuse im NPM aktivieren)
Damit der private Schlüssel bei der Erneuerung gleich bleibt und dein TLSA-Record dauerhaft gültig bleibt:
1. Auf dem **NPM-LXC** als `root` anmelden.
2. Die Konfigurationsdatei des Zertifikats öffnen (Ordnernummer anpassen, z. B. `npm-123`):  
   `nano /etc/letsencrypt/renewal/npm-123.conf`
3. Im Block `[renewalparams]` folgende Zeile hinzufügen:  
   `reuse_key = True`  
   WICHTIG: einen Unterstich `_` verwenden, keinen Bindestrich `-` !
4. Speichern und schließen.

### 2. SSH-Keys austauschen (Passwortloses SCP)
Der Mailcow-LXC muss die Berechtigung haben, Dateien vom NPM-LXC ohne Passwort abzurufen.
Auf dem **Mailcow-LXC** als `root` ausführen:  
1. SSH-Schlüssel generieren (Passwort bei der Abfrage einfach leer lassen!):  
   `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""`
2. Schlüssel auf den NPM-LXC kopieren (IP-Adresse deines NPM eintragen):  
   `ssh-copy-id -i ~/.ssh/id_ed25519.pub root@10.0.0.5`
3. Verbindung testen (sollte nun ohne Passwort klappen):  
   `ssh root@10.0.0.5 'echo "Verbindung erfolgreich!"'`

### 3. Script installieren
Lege das Script `ssl_npm_updater.sh` auf dem Mailcow-LXC im Helper-Scripts Ordner ab:  

`nano /opt/mailcow-dockerized/helper-scripts/ssl_npm_updater.sh`

Kopiere den Code aus der Datei in diesem Repository hinein und passe im oberen Bereich die Variablen (`NPM_IP`, `MAIL_DOMAIN`, `ADMIN_MAIL`) an deine Umgebung an.

Anschließend das Script ausführbar machen:  
`chmod +x /opt/mailcow-dockerized/helper-scripts/ssl_npm_updater.sh`

### 4. Automatisierung per Cronjob
Damit das Script z. B. jeden Montag um 04:00 Uhr früh läuft, richte einen Cronjob auf dem **Mailcow-LXC** ein:  
`crontab -e`

Folgende Zeile am Ende einfügen:  
`0 4 * * 1 /opt/mailcow-dockerized/helper-scripts/ssl_npm_updater.sh > /dev/null 2>&1`

---

## 📜 Logs & Überwachung
Das Script legt detaillierte Logs unter `/var/log/mailcow_ssl_update.log` an. Bei jedem Lauf wird das Ergebnis des SSL-Tests zusätzlich an die konfigurierte E-Mail-Adresse geschickt.

## Autor
**Matthias Obereder**

## Lizenz
Dieses Projekt ist unter der MIT-Lizenz lizenziert. Weitere Details findest du in der `LICENSE` Datei.
