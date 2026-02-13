#!/bin/sh
# Détecte et notifie les nouveaux sous-domaines via Discord

RESULTS_DIR="/app/results"
SEEN_FILE="/app/seen_domains.txt"
NEW_FILE="/app/new_domains.txt"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/1471764024797433872/WpHl_7qk5u9mocNYd2LbnFBp0qXbff3RXAIsrKVNXspSQJHJOp_e4_XhWOaq4jrSjKtS"

# Créer les fichiers si n'existent pas
touch "$SEEN_FILE"
> "$NEW_FILE"

# Extraire tous les domaines des résultats
if [ -d "$RESULTS_DIR" ] && [ "$(ls -A $RESULTS_DIR 2>/dev/null)" ]; then
    find "$RESULTS_DIR" -type f -exec cat {} \; 2>/dev/null | \
        grep -oE '[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.(com|net|org|io|fr|edu|gov|co|uk|de|jp|br|in|ru|cn|au|ca|nl|ch|se|no|dk|fi|be|at|nz|sg|hk|tw|kr|mx|ar|cl|za|il|ae|sa|eg|pk|bd|ng|ke|gh|ug|tz|ma|dz|tn|ly|et|sn|ci|cm|cd|ao|mz|zw|zm|bw|na|mu|re|sc|mg|km|so|dj|er|ss|sd|mr|ml|ne|bf|gn|sl|lr|gm|gw|cv|st|ga|cg|cf|td|bi|rw)' | \
        sort -u > /tmp/all_domains.txt
    
    # Comparer avec les domaines déjà vus
    if [ -s /tmp/all_domains.txt ]; then
        comm -13 "$SEEN_FILE" /tmp/all_domains.txt > "$NEW_FILE"
        
        # Si nouveaux domaines trouvés
        if [ -s "$NEW_FILE" ]; then
            COUNT=$(wc -l < "$NEW_FILE")
            echo "🔥 $COUNT NEW DOMAINS FOUND AT $(date):"
            cat "$NEW_FILE"
            echo "---"
            
            # Préparer le message Discord (échapper proprement pour JSON)
            MESSAGE=$(cat "$NEW_FILE" | head -25 | while read domain; do
                echo "• $domain"
            done | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            
            # Footer si trop de domaines
            if [ "$COUNT" -gt 25 ]; then
                FOOTER="\\n\\n... et $((COUNT - 25)) autres domaines"
            else
                FOOTER=""
            fi
            
            # Créer le payload JSON avec jq pour un échappement parfait
            if command -v jq >/dev/null 2>&1; then
                # Utiliser jq si disponible (meilleur échappement)
                PAYLOAD=$(jq -n \
                    --arg count "$COUNT" \
                    --arg message "$MESSAGE" \
                    --arg footer "$FOOTER" \
                    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                    '{
                        embeds: [{
                            title: "🎯 Nouveaux sous-domaines détectés",
                            description: ("**" + $count + "** nouveaux domaines trouvés"),
                            color: 65280,
                            fields: [{
                                name: "Domaines",
                                value: ("```\n" + $message + $footer + "\n```")
                            }],
                            footer: {
                                text: "Gungnir CT Monitor"
                            },
                            timestamp: $timestamp
                        }]
                    }')
            else
                # Fallback sans jq (échappement basique)
                MESSAGE_ESCAPED=$(echo "$MESSAGE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
                PAYLOAD="{\"embeds\":[{\"title\":\"🎯 Nouveaux sous-domaines détectés\",\"description\":\"**${COUNT}** nouveaux domaines trouvés\",\"color\":65280,\"fields\":[{\"name\":\"Domaines\",\"value\":\"\`\`\`\\n${MESSAGE_ESCAPED}${FOOTER}\\n\`\`\`\"}],\"footer\":{\"text\":\"Gungnir CT Monitor\"},\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}"
            fi
            
            # Envoyer à Discord
            RESPONSE=$(curl -s -X POST "$DISCORD_WEBHOOK" \
                -H "Content-Type: application/json" \
                -d "$PAYLOAD")
            
            if echo "$RESPONSE" | grep -q "code"; then
                echo "❌ Discord error: $RESPONSE"
            else
                echo "✅ Discord notification sent!"
            fi
        fi
        
        # Mettre à jour la liste des domaines vus
        cat /tmp/all_domains.txt > "$SEEN_FILE"
    fi
else
    echo "⏳ Waiting for results directory to populate..."
fi
