#!/bin/sh
set -e

RESULTS_DIR="/app/results"
SEEN_FILE="/app/seen_domains.txt"
NEW_FILE="/app/new_domains.txt"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/1471764024797433872/WpHl_7qk5u9mocNYd2LbnFBp0qXbff3RXAIsrKVNXspSQJHJOp_e4_XhWOaq4jrSjKtS"

# S'assurer que les fichiers existent
touch "$SEEN_FILE" "$NEW_FILE"

# Extraire tous les domaines des fichiers results
find "$RESULTS_DIR" -type f -exec cat {} \; 2>/dev/null | \
    grep -v '^$' | \
    sort -u > /tmp/all_domains.txt

# Vérifier s'il y a des domaines
if [ ! -s /tmp/all_domains.txt ]; then
    echo "ℹ️ Aucun domaine à traiter"
    exit 0
fi

# CORRECTION #1: Comparaison correcte avec comm
sort -u "$SEEN_FILE" > /tmp/seen_sorted.txt
comm -13 /tmp/seen_sorted.txt /tmp/all_domains.txt > "$NEW_FILE" 2>/dev/null || true

# Si pas de nouveaux domaines
if [ ! -s "$NEW_FILE" ]; then
    echo "ℹ️ Aucun nouveau domaine détecté"
    # Mettre à jour seen avec tous les domaines actuels
    cat "$SEEN_FILE" /tmp/all_domains.txt | sort -u > /tmp/seen_updated.txt
    mv /tmp/seen_updated.txt "$SEEN_FILE"
    exit 0
fi

# CORRECTION #2: Filtre anti-bruit amélioré
grep -v -E 'api\.|media\.|analytic\.|prod-|mta-sts\.|queue\.|digireceipt\.|watsons\.|savers\.|moneyback\.|marionnaud\.|internal\.|test-|dev-|staging-' "$NEW_FILE" > "$NEW_FILE.filtered" 2>/dev/null || true

if [ -s "$NEW_FILE.filtered" ]; then
    mv "$NEW_FILE.filtered" "$NEW_FILE"
else
    echo "ℹ️ Tous les nouveaux domaines filtrés (bruit détecté)"
    cat "$SEEN_FILE" /tmp/all_domains.txt | sort -u > /tmp/seen_updated.txt
    mv /tmp/seen_updated.txt "$SEEN_FILE"
    exit 0
fi

# CORRECTION #3: Vérifier après filtrage
if [ ! -s "$NEW_FILE" ]; then
    echo "ℹ️ Aucun domaine après filtrage"
    cat "$SEEN_FILE" /tmp/all_domains.txt | sort -u > /tmp/seen_updated.txt
    mv /tmp/seen_updated.txt "$SEEN_FILE"
    exit 0
fi

# Compter les nouveaux domaines
COUNT=$(wc -l < "$NEW_FILE")

# CORRECTION #4: Seuil élevé pour éviter les faux positifs
if [ "$COUNT" -gt 100 ]; then
    echo "⚠️ Trop de nouveaux domaines ($COUNT) → probablement bruit, skip notification"
    echo "Premiers domaines détectés :"
    head -20 "$NEW_FILE"
    # Mettre à jour seen quand même
    cat "$SEEN_FILE" /tmp/all_domains.txt | sort -u > /tmp/seen_updated.txt
    mv /tmp/seen_updated.txt "$SEEN_FILE"
    exit 0
fi

# CORRECTION #5: Construire le message de façon sûre (éviter les injections)
MESSAGE=$(head -500 "$NEW_FILE" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ //;s/ $//')

# Construire le payload JSON proprement (avec jq serait mieux mais pas dispo en sh)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > /tmp/payload.json <<PAYLOAD
{
  "embeds": [{
    "title": "🎯 Nouveaux sous-domaines (${COUNT})",
    "description": "${MESSAGE}",
    "color": 65280,
    "footer": {"text": "Gungnir CT Monitor"},
    "timestamp": "${TIMESTAMP}"
  }]
}
PAYLOAD

# CORRECTION #6: Vérifier la syntaxe JSON avant d'envoyer
if ! grep -q '{' /tmp/payload.json 2>/dev/null; then
    echo "❌ Erreur construction JSON"
    exit 1
fi

# Envoyer à Discord
HTTP_CODE=$(curl -s -o /tmp/discord_response.txt -w "%{http_code}" \
    -X POST "$DISCORD_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d @/tmp/payload.json 2>/dev/null)

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Notification Discord envoyée ($COUNT domaines)"
else
    echo "❌ Erreur Discord (HTTP $HTTP_CODE)"
    if [ -s /tmp/discord_response.txt ]; then
        head -5 /tmp/discord_response.txt
    fi
fi

# Mise à jour seen_domains avec tous les domaines actuels
cat "$SEEN_FILE" /tmp/all_domains.txt | sort -u > /tmp/seen_updated.txt
mv /tmp/seen_updated.txt "$SEEN_FILE"

# Vider les fichiers results (éviter de retraiter les mêmes)
find "$RESULTS_DIR" -type f ! -name ".gitkeep" -exec sh -c '> "$1"' _ {} \;

# Cleanup
rm -f "$NEW_FILE" /tmp/payload.json /tmp/discord_response.txt /tmp/seen_sorted.txt /tmp/all_sorted.txt /tmp/all_domains.txt /tmp/seen_updated.txt

echo "✅ Cleanup terminé"
