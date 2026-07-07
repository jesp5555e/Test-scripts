#!/bin/bash

# ==============================================================================
# Script: join-LXC-ad.sh
# Formål: Join LXC (Ubuntu/Debian) til AD og opsæt DDNS
# Forfatter: Lars (JesperHDgaming IT)
# ==============================================================================

# --- KONFIGURATION ---
DOMAIN="AD.JesperHDgaming.dk"
ADMIN_USER="Administrator"
# ---------------------

# Tjek om scriptet køres som root
if [ "$EUID" -ne 0 ]; then 
  echo "Fejl: Dette script skal køres som root eller med sudo."
  exit 1
fi

echo "--- Starter AD Join proces for $(hostname) ---"

# 1. Opdatering og installation af pakker
echo "[1/5] Installerer nødvendige pakker..."
apt-get update -y
apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin packagekit

# 2. Tjek om maskinen allerede er joinet
if realm list | grep -q "$DOMAIN"; then
    echo "Info: Maskinen er allerede joinet til $DOMAIN. Springer join over."
else
    # 3. Join domænet
    echo "[2/5] Joiner domænet $DOMAIN..."
    echo "Du vil nu blive bedt om password til $ADMIN_USER"
    realm join -U "$ADMIN_USER" "$DOMAIN"
    
    if [ $? -eq 0 ]; then
        echo "Succes: Maskinen er nu joinet til $DOMAIN."
    else
        echo "Fejl: Kunne ikke joine domænet. Tjek DNS og password."
        exit 1
    fi
fi
# 4. Implementering Rettigheds-politik
# Her definerer vi reglen: <Hostname>-ADMIN gruppen får fuld sudo uden password
echo "[Policy] Konfigurerer automatiske rettigheder..."
sudo_rule="%$(hostname)-admin@$DOMAIN ALL=(ALL:ALL) ALL"

echo "$sudo_rule" > /etc/sudoers.d/ad-policy
chmod 440 /etc/sudoers.d/ad-policy

# Vi gør det samme for SSH-gruppen, hvis du vil have dem til at kunne logge ind via SSH
# (Dette kræver at sshd er konfigureret til at tillade AD-brugere)
echo "AllowGroups $(hostname)-ssh@$DOMAIN $(hostname)-admin@$DOMAIN" > /etc/ssh/sshd_config.d/ad-access.conf
systemctl restart ssh

sudo sed -i '/session\s*.*pam_unix.so/i session required        pam_mkhomedir.so' /etc/pam.d/common-session

# 5. DDNS Opdatering
echo "[3/5] Opdaterer DNS-record i AD..."
adcli update --domain="$DOMAIN"

if [ $? -eq 0 ]; then
    echo "Succes: DNS-record er opdateret."
else
    echo "Advarsel: Kunne ikke opdatere DNS-record."
fi

# 6. Opsætning af automatisk DDNS ved boot
echo "[4/5] Opsætter automatisk DNS-opdatering ved boot..."
CRON_JOB="@reboot /usr/bin/adcli update --domain=$DOMAIN"
# Tjek om jobbet allerede findes i crontab for at undgå dubletter
(crontab -l 2>/dev/null | grep -F "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "[5/5] Færdig! Maskinen $(hostname) er nu klar."
echo "--------------------------------------------------"
