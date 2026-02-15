#!/bin/sh
set -e

RESULTS_DIR="/app/results"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/1472487929862684703/a4vMYqiwQO6c1VLRXNpv4w09kC2yTq-Rtdm4VkEBjsca6hfKZ6ARalPq4dvpTYoYHniu"

# Vérifier s'il y a des résultats
if [ ! -d "$RESULTS_DIR" ] || [ -z "$(find $RESULTS_DIR -type f -size +0 2>/dev/null | head -1)" ]; then
    echo "ℹ️ No results to notify"
    exit 0
fi

# Extraire les données complètes (domain|dns_ip|http_status|dangling_flag)
ALL_DATA=$(find "$RESULTS_DIR" -type f -exec cat {} \; 2>/dev/null | sort -u)

if [ -z "$ALL_DATA" ]; then
    echo "ℹ️ No domains found"
    exit 0
fi

# Compter les domaines
COUNT=$(echo "$ALL_DATA" | wc -l)

# Séparer par catégorie
DANGLING=$(echo "$ALL_DATA" | grep "DANGLING" | cut -d'|' -f1)
DANGLING_COUNT=$(echo "$DANGLING" | grep -c . || echo "0")

ACTIVE=$(echo "$ALL_DATA" | grep -E "\|20[0-9]\|" | cut -d'|' -f1)
ACTIVE_COUNT=$(echo "$ACTIVE" | grep -c . || echo "0")

NXDOMAIN=$(echo "$ALL_DATA" | grep "N/A|N/A" | cut -d'|' -f1)
NXDOMAIN_COUNT=$(echo "$NXDOMAIN" | grep -c . || echo "0")

OTHERS=$(echo "$ALL_DATA" | grep -v "DANGLING" | grep -v -E "\|20[0-9]\|" | grep -v "N/A|N/A" | cut -d'|' -f1)
OTHERS_COUNT=$(echo "$OTHERS" | grep -c . || echo "0")

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Message 1: Header avec stats
cat > /tmp/payload1.json <<EOF
{
  "embeds": [{
    "title": "🎯 New Subdomains Found",
    "description": "**Total:** $COUNT\n**✅ Active (HTTP 200):** $ACTIVE_COUNT\n**⚠️ Dangling DNS:** $DANGLING_COUNT\n**❌ Not Responding:** $NXDOMAIN_COUNT\n**🟡 Other Status:** $OTHERS_COUNT",
    "color": 65280,
    "footer": {"text": "Gungnir CT Monitor"},
    "timestamp": "$TIMESTAMP"
  }]
}
EOF

# Envoyer message 1
HTTP_CODE=$(curl -s -o /tmp/response.txt -w "%{http_code}" \
    -X POST "$DISCORD_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d @/tmp/payload1.json 2>/dev/null || echo "0")

if [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Discord error on header (HTTP $HTTP_CODE)"
    exit 1
fi

sleep 1

# ===== MESSAGE 2: DANGLING DNS (PRIORITÉ) =====
if [ "$DANGLING_COUNT" -gt 0 ]; then
    CHUNK_NUM=2
    
    echo "$DANGLING" | while read -r domain; do
        if [ -z "$domain" ]; then
            continue
        fi
        
        # Chercher les détails dans les fichiers results
        FULL_LINE=$(grep "^$domain|" "$RESULTS_DIR"/* 2>/dev/null | head -1)
        DNS_IP=$(echo "$FULL_LINE" | cut -d'|' -f2)
        HTTP_STATUS=$(echo "$FULL_LINE" | cut -d'|' -f3)
        
        echo "\`$domain\` (DNS: $DNS_IP, HTTP: $HTTP_STATUS)" >> /tmp/dangling.txt
    done
    
    if [ -f /tmp/dangling.txt ]; then
        CHUNK_CONTENT=$(cat /tmp/dangling.txt | paste -sd '\n' -)
        CHUNK_CONTENT=$(echo "$CHUNK_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n')
        
        cat > /tmp/payload_chunk.json <<PAYLOAD
{
  "embeds": [{
    "title": "🔴 DANGLING DNS (TAKEOVER POSSIBLE)",
    "description": "$CHUNK_CONTENT",
    "color": 16711680,
    "footer": {"text": "Gungnir CT Monitor - Part $CHUNK_NUM"}
  }]
}
PAYLOAD
        
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d @/tmp/payload_chunk.json > /dev/null 2>&1
        
        echo "✅ Sent Dangling DNS ($DANGLING_COUNT)"
        sleep 1
    fi
fi

# ===== MESSAGE 3: ACTIVE (HTTP 200) =====
if [ "$ACTIVE_COUNT" -gt 0 ]; then
    CHUNK_NUM=3
    
    echo "$ACTIVE" | while read -r domain; do
        if [ -z "$domain" ]; then
            continue
        fi
        
        FULL_LINE=$(grep "^$domain|" "$RESULTS_DIR"/* 2>/dev/null | head -1)
        DNS_IP=$(echo "$FULL_LINE" | cut -d'|' -f2)
        HTTP_STATUS=$(echo "$FULL_LINE" | cut -d'|' -f3)
        
        echo "\`$domain\` (DNS: $DNS_IP, HTTP: $HTTP_STATUS)" >> /tmp/active.txt
    done
    
    if [ -f /tmp/active.txt ]; then
        CHUNK_CONTENT=$(cat /tmp/active.txt | paste -sd '\n' -)
        CHUNK_CONTENT=$(echo "$CHUNK_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n')
        
        cat > /tmp/payload_chunk.json <<PAYLOAD
{
  "embeds": [{
    "title": "✅ ACTIVE (HTTP 200)",
    "description": "$CHUNK_CONTENT",
    "color": 65280,
    "footer": {"text": "Gungnir CT Monitor - Part $CHUNK_NUM"}
  }]
}
PAYLOAD
        
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d @/tmp/payload_chunk.json > /dev/null 2>&1
        
        echo "✅ Sent Active domains ($ACTIVE_COUNT)"
        sleep 1
    fi
fi

# ===== MESSAGE 4: OTHER STATUS (403, 404, 500, etc) =====
if [ "$OTHERS_COUNT" -gt 0 ]; then
    CHUNK_NUM=4
    
    echo "$OTHERS" | while read -r domain; do
        if [ -z "$domain" ]; then
            continue
        fi
        
        FULL_LINE=$(grep "^$domain|" "$RESULTS_DIR"/* 2>/dev/null | head -1)
        DNS_IP=$(echo "$FULL_LINE" | cut -d'|' -f2)
        HTTP_STATUS=$(echo "$FULL_LINE" | cut -d'|' -f3)
        
        echo "\`$domain\` (DNS: $DNS_IP, HTTP: $HTTP_STATUS)" >> /tmp/others.txt
    done
    
    if [ -f /tmp/others.txt ]; then
        CHUNK_CONTENT=$(cat /tmp/others.txt | paste -sd '\n' -)
        CHUNK_CONTENT=$(echo "$CHUNK_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n')
        
        cat > /tmp/payload_chunk.json <<PAYLOAD
{
  "embeds": [{
    "title": "🟡 OTHER STATUS (403, 404, 500, etc)",
    "description": "$CHUNK_CONTENT",
    "color": 16776960,
    "footer": {"text": "Gungnir CT Monitor - Part $CHUNK_NUM"}
  }]
}
PAYLOAD
        
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d @/tmp/payload_chunk.json > /dev/null 2>&1
        
        echo "✅ Sent Other status domains ($OTHERS_COUNT)"
        sleep 1
    fi
fi

# ===== MESSAGE 5: NOT RESPONDING (DNS OK but no HTTP) =====
if [ "$NXDOMAIN_COUNT" -gt 0 ]; then
    CHUNK_NUM=5
    
    echo "$NXDOMAIN" | while read -r domain; do
        if [ -z "$domain" ]; then
            continue
        fi
        
        echo "\`$domain\`" >> /tmp/nxdomain.txt
    done
    
    if [ -f /tmp/nxdomain.txt ]; then
        CHUNK_CONTENT=$(cat /tmp/nxdomain.txt | paste -sd '\n' -)
        CHUNK_CONTENT=$(echo "$CHUNK_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n')
        
        cat > /tmp/payload_chunk.json <<PAYLOAD
{
  "embeds": [{
    "title": "❌ NOT RESPONDING (NXDOMAIN)",
    "description": "$CHUNK_CONTENT",
    "color": 16711680,
    "footer": {"text": "Gungnir CT Monitor - Part $CHUNK_NUM"}
  }]
}
PAYLOAD
        
        curl -s -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d @/tmp/payload_chunk.json > /dev/null 2>&1
        
        echo "✅ Sent NXDOMAIN ($NXDOMAIN_COUNT)"
        sleep 1
    fi
fi

echo "✅ All notifications sent"

# Cleanup results
find "$RESULTS_DIR" -type f ! -name ".gitkeep" -exec sh -c '> "$1"' _ {} \;

# Cleanup temp
rm -f /tmp/payload*.json /tmp/response.txt /tmp/dangling.txt /tmp/active.txt /tmp/others.txt /tmp/nxdomain.txt
