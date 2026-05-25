#!/bin/bash

domains=("google.com" "github.com" "pulsestack.local")
pairs=("google.com:443" "github.com:443" "localhost:8000")
tls_pairs=("google.com:443" "github.com:443" "pulsestack.local:443")
urls=("https://google.com" "https://github.com")

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== DNS Resolution ==="

for domain in "${domains[@]}"; do
    result=$(dscacheutil -q host -a name "$domain" 2>/dev/null | awk '/ip_address/{print $2; exit}')
    [ -z "$result" ] && result=$(dig +short "$domain" | head -1)

    if [ -z "$result" ]; then
        result="${RED}FAILED${NC}"
    fi

    echo -e "$domain -> $result"
done

echo "=== Port Connectivity ==="

for pair in "${pairs[@]}"; do
    host=$(echo "$pair" | cut -d: -f1)
    port=$(echo "$pair" | cut -d: -f2)

    if nc -z "$host" "$port" 2>/dev/null; then
        echo -e "$host:$port -> ${GREEN}OK${NC}"
    else
        echo -e "$host:$port -> ${RED}FAILED${NC}"
    fi
done

echo "=== TLS Cert Expiry ==="

for pair in "${tls_pairs[@]}"; do
    not_after=$(openssl s_client -connect "$pair" </dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep notAfter)

    echo "$pair -> $not_after"
done

echo "=== HTTP Timing ==="

for url in "${urls[@]}"; do
    time_total=$(curl -w %{time_total} $url -o /dev/null -s)

    echo "$url -> $time_total"
done

echo "=== Listening Ports ===" 
netstat -an | grep LISTEN