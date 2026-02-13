FROM golang:1.21-alpine

RUN apk add --no-cache git python3 curl ca-certificates

# Installer Gungnir avec les bonnes options Git
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" && \
    git config --global advice.detachedHead false && \
    go env -w GOPRIVATE="" && \
    go install github.com/opencyber-fr/gungnir@latest

WORKDIR /app

COPY domains.txt .
COPY start.sh .
COPY notify.sh .
COPY server.py .

RUN chmod +x start.sh notify.sh

EXPOSE 8080

CMD ["./start.sh"]
