#!/bin/bash

# ==============================================================================
# Script: ssl_npm_updater.sh
# Autor: Matthias Obereder
# Beschreibung: Sucht auf dem NPM-LXC das SSL-Zertifikat für Mailcow, kopiert
#               es per SCP, startet die Container neu, führt einen Live-Test
#               durch und sendet einen Statusbericht per interner Mail.
#               WICHTIG: Es müssen vorher die ssh-Keys ausgetauscht werden und 
#               in NPM das reuse-key aktiviert werden!
# Lizenz: MIT
# ==============================================================================

# ----------------- Konfiguration -----------------
NPM_IP="10.0.0.5"                    # Die IP des Nginx Proxy Manager LXC
MAIL_DOMAIN="mail.exampel.com"       # Deine exakte Mail-Domain
ADMIN_MAIL="admin@exampel.com"       # Empfängeradresse für den Bericht
MAILCOW_DIR="/opt/mailcow-dockerized"
MAILCOW_SSL_DIR="${MAILCOW_DIR}/data/assets/ssl"
LOG_FILE="/var/log/mailcow_ssl_update.log"
# -------------------------------------------------

# Hilfsfunktion für sauberes Logging
log_msg() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_msg "Starte SSL-Zertifikat Update für ${MAIL_DOMAIN}..."

# 1. Den RICHTIGEN npm-Ordner auf dem NPM-LXC anhand der Domain ermitteln
NPM_FOLDER=$(ssh -q root@${NPM_IP} "for d in /etc/letsencrypt/live/npm-*/; do if openssl x509 -in \"\${d}cert.pem\" -noout -text 2>/dev/null | grep -q \"${MAIL_DOMAIN}\"; then basename \"\$d\"; break; fi; done")

# Sicherheitsprüfung 1: Ordner gefunden?
if [ -z "$NPM_FOLDER" ]; then
    log_msg "FEHLER: Konnte kein Zertifikat für ${MAIL_DOMAIN} auf dem NPM (${NPM_IP}) finden!"
    exit 1
fi

NPM_SSL_DIR="/etc/letsencrypt/live/${NPM_FOLDER}"
log_msg "Zertifikats-Verzeichnis auf NPM gefunden: ${NPM_SSL_DIR}"

# 2. Zertifikate kopieren
scp -q root@${NPM_IP}:${NPM_SSL_DIR}/privkey.pem ${MAILCOW_SSL_DIR}/key.pem
scp -q root@${NPM_IP}:${NPM_SSL_DIR}/fullchain.pem ${MAILCOW_SSL_DIR}/cert.pem

# Sicherheitsprüfung 2: Kopieren erfolgreich?
if [ $? -eq 0 ]; then
    log_msg "Kopieren erfolgreich. Starte Mailcow-Container neu..."
    cd ${MAILCOW_DIR} || exit
    docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow
    
    # Kurze Pause, damit die Container sauber hochfahren können
    sleep 15
    
    # 3. SSL-Test von außen simulieren (prüft den echten SMTP-Port 25)
    log_msg "Führe SSL-Test auf Port 25 durch..."
    SSL_EXPIRY=$(echo -n | openssl s_client -connect ${MAIL_DOMAIN}:25 -starttls smtp 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
    
    if [ -n "$SSL_EXPIRY" ]; then
        STATUS_MSG="Erfolgreich! Das Zertifikat ist live und gueltig bis: $SSL_EXPIRY"
        log_msg "Test bestanden: Zertifikat gültig bis $SSL_EXPIRY"
    else
        STATUS_MSG="WARNUNG: Zertifikate wurden kopiert, aber der SSL-Test auf Port 25 schlug fehl!"
        log_msg "FEHLER: SSL-Test schlug fehl. Liefert Postfix das Zertifikat korrekt aus?"
    fi

    # 4. E-Mail-Bericht versenden (OHNE Passwörter, direkt über docker compose exec)
    cat <<EOF | docker compose exec -T postfix-mailcow sendmail -t
To: ${ADMIN_MAIL}
From: mailcow-system@${MAIL_DOMAIN}
Subject: SSL-Update Status fuer ${MAIL_DOMAIN}

Servus,

das automatische SSL-Update-Script auf dem Mailserver wurde soeben ausgefuehrt.

Ergebnis des Live-Tests:
${STATUS_MSG}

Das detaillierte Logfile findest du auf dem Server unter: ${LOG_FILE}

Gruesse von deinem Server!
EOF

    log_msg "Update komplett abgeschlossen. Status-E-Mail wurde versendet."

else
    log_msg "FEHLER: Dateien konnten nicht vom NPM kopiert werden!"
    exit 1
fi
