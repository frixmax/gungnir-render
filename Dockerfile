# =============================================================================
# Dockerfile - Gungnir CT Monitor (crt.sh polling + page web + Discord alerts)
# =============================================================================

FROM python:3.11-alpine

# Install dépendances système minimales
RUN apk add --no-cache curl jq bash

# Répertoire de travail
WORKDIR /app

# Install Python deps
RUN pip install --no-cache-dir requests

# Copie les fichiers essentiels
COPY domains.txt .
COPY certstream_monitor.py .
COPY server.py .
COPY notify.sh .
COPY start.sh .

# Rendre les scripts exécutables
RUN chmod +x start.sh notify.sh

# Créer les dossiers persistants (results + fichiers de state)
RUN mkdir -p /app/results \
    && touch /app/seen_domains.txt \
    && touch /app/new_domains.txt \
    && touch /app/.first_run_complete

# Exposer le port de la page web
EXPOSE 8080

# Healthcheck (optionnel mais utile pour Docker)
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Point d'entrée : le script de démarrage
CMD ["./start.sh"]
