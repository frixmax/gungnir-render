#!/bin/sh
RESULTS_DIR="/app/results"
SEEN_FILE="/app/seen_domains.txt"
NEW_FILE="/app/new_domains.txt"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/1471764024797433872/WpHl_7qk5u9mocNYd2LbnFBp0qXbff3RXAIsrKVNXspSQJHJOp_e4_XhWOaq4jrSjKtS"

touch "$SEEN_FILE" "$NEW_FILE"

# Extraire tous les domaines
find "$RESULTS_DIR" -type f -exec cat {} \; 2>/dev/null | \
    sort -u > /tmp/all_domains.txt

# Comparer → nouveaux
comm -13 "$SEEN_FILE" /tmp/all_domains.txt > "$NEW_FILE"

# Filtre anti-bruit
grep -v -E 'api\.|media\.|analytic\.|prod-|mta-sts\.|queue\.|digireceipt\.|watsons\.|savers\.|moneyback\.|marionnaud\.' "$NEW_FILE" > "$NEW_FILE.filtered"
mv "$NEW_FILE.filtered" "$NEW_FILE"

if [ -s "$NEW_FILE" ]; then
    COUNT=$(wc -l < "$NEW_FILE")
    if [ "$COUNT" -gt 30 ]; then
        echo "Trop de nouveaux ($COUNT) → probablement bruit, skip"
    else
        MESSAGE=$(head -500 "$NEW_FILE" | tr '\n' ' ')
        PAYLOAD="{\"embeds\":[{\"title\":\"🎯 Nouveaux sous-domaines (${COUNT})\",\"description\":\"${MESSAGE}\",\"color\":65280,\"footer\":{\"text\":\"Gungnir CT Monitor\"},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}"
        curl -s -X POST "$DISCORD_WEBHOOK" -H "Content-Type: application/json" -d "$PAYLOAD"
        echo "Notification envoyée"
    fi
fi

# Mise à jour seen
cat /tmp/all_domains.txt >> "$SEEN_FILE"
sort -u -o "$SEEN_FILE" "$SEEN_FILE"
