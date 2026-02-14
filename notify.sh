#!/bin/sh
RESULTS_DIR="/app/results"
SEEN_FILE="/app/seen_domains.txt"
NEW_FILE="/app/new_domains.txt"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/1471764024797433872/WpHl_7qk5u9mocNYd2LbnFBp0qXbff3RXAIsrKVNXspSQJHJOp_e4_XhWOaq4jrSjKtS"

# S'assurer que les fichiers existent
touch "$SEEN_FILE" "$NEW_FILE"

# Extraire tous les domaines des fichiers results
find "$RESULTS_DIR" -type f -exec cat {} \; 2>/dev/null | \
    sort -u > /tmp/all_domains.txt

# Vérifier s'il y a des domaines
if [ ! -s /tmp/all_domains.txt ]; then
    echo "Aucun nouveau domaine à traiter"
    exit 0
fi

# Comparer → nouveaux (ceux qui ne sont PAS déjà dans seen)
comm -13 <(sort "$SEEN_FILE") <(sort /tmp/all_domains.txt) > "$NEW_FILE"

# Si pas de nouveaux
if [ ! -s "$NEW_FILE" ]; then
    echo "Aucun nouveau domaine"
    # Cleanup
    cat /tmp/all_domains.txt >> "$SEEN_FILE"
    sort -u -o "$SEEN_FILE" "$SEEN_FILE"
    > "$NEW_FILE"
    exit 0
fi

# Filtre anti-bruit
grep -v -E 'api\.|media\.|analytic\.|prod-|mta-sts\.|queue\.|digireceipt\.|watsons\.|savers\.|moneyback\.|marionnaud\.' "$NEW_FILE" > "$NEW_FILE.filtered"
mv "$NEW_FILE.filtered" "$NEW_FILE"

# Vérifier après filtrage
if [ ! -s "$NEW_FILE" ]; then
    echo "Tous les domaines filtrés (bruit)"
    # Cleanup
    cat /tmp/all_domains.txt >> "$SEEN_FILE"
    sort -u -o "$SEEN_FILE" "$SEEN_FILE"
    > "$NEW_FILE"
    exit 0
fi

COUNT=$(wc -l < "$NEW_FILE")

if [ "$COUNT" -gt 50 ]; then
    echo "⚠️ Trop de nouveaux ($COUNT) → probablement bruit, skip notification"
    echo "Domaines détectés mais non notifiés :"
    head -10 "$NEW_FILE"
else
    # Préparer le message (échapper les guillemets et retours à la ligne)
    MESSAGE=$(head -500 "$NEW_FILE" | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/ $//')
    
    PAYLOAD="{\"embeds\":[{\"title\":\"🎯 Nouveaux sous-domaines (${COUNT})\",\"description\":\"${MESSAGE}\",\"color\":65280,\"footer\":{\"text\":\"Gungnir CT Monitor\"},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Notification Discord envoyée ($COUNT domaines)"
    else
        echo "❌ Erreur Discord (HTTP $HTTP_CODE)"
        echo "$RESPONSE" | head -n-1
    fi
fi

# Mise à jour seen (ajouter TOUS les domaines traités)
cat /tmp/all_domains.txt >> "$SEEN_FILE"
sort -u -o "$SEEN_FILE" "$SEEN_FILE"

# Vider les fichiers results (déjà traités)
find "$RESULTS_DIR" -type f -exec sh -c '> "$1"' _ {} \;

# Vider new_domains.txt
> "$NEW_FILE"

echo "Cleanup terminé"
