proxy-up:
	docker compose up -d

proxy-down:
	docker compose down

netprobe:
	bash ./netprobe.sh

cert-check:
	openssl s_client -connect pulsestack.local:443 </dev/null 2>/dev/null | openssl x509 -noout -dates