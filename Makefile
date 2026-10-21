# PHP2Shell lab — convenience wrapper. The raw docker compose + python
# commands in README.md are first-class (Windows hosts often lack make);
# these just chain them. Exit codes are documented in the writeups/.

PYTHON ?= python
LAB_PORT ?= 8088
LAB_FIXED_PORT ?= 8089
UAF_STOCK_PORT ?= 8099
UAF_ABLATED_PORT ?= 8098
export LAB_PORT LAB_FIXED_PORT UAF_STOCK_PORT UAF_ABLATED_PORT

.PHONY: help up poc109619 fixed uaf poc109618-ablated poc109618-stock mitigate-check verify down clean

help:
	@echo "make up                 build+start PixelVault lab on :$(LAB_PORT)"
	@echo "make poc109619          CVE-2026-109619 chain PoC      (expect exit 0: RCE)"
	@echo "make fixed              same app, upload_progress OFF (:$(LAB_FIXED_PORT))"
	@echo "make uaf                build+start valgrind PHP stock(:$(UAF_STOCK_PORT)) + ablated(:$(UAF_ABLATED_PORT))"
	@echo "make poc109618-ablated  UAF trigger vs ablated  (expect exit 0: heap use after free)"
	@echo "make poc109618-stock    UAF trigger vs stock    (expect exit 1: clean)"
	@echo "make verify             all of the above in order"
	@echo "make down               stop containers"

up:
	docker compose up -d --build lab

poc109619:
	$(PYTHON) poc/cve-2026-109619.py --url http://127.0.0.1:$(LAB_PORT)

fixed:
	docker compose --profile fixed up -d lab-fixed

uaf:
	docker compose --profile uaf up -d --build

poc109618-ablated:
	$(PYTHON) poc/cve-2026-109618.py --url http://127.0.0.1:$(UAF_ABLATED_PORT)/index.php --container php84-uaf-ablated

poc109618-stock:
	-$(PYTHON) poc/cve-2026-109618.py --url http://127.0.0.1:$(UAF_STOCK_PORT)/index.php --container php84-uaf-stock

mitigate-check:
	docker exec php2shell-lab-fixed php -r 'echo ini_get("session.upload_progress.enabled") ? "ON" : "OFF", "\n";'

verify: up fixed uaf
	sleep 3
	$(MAKE) poc109619 poc109618-ablated poc109618-stock mitigate-check

down:
	docker compose down --remove-orphans

clean: down
	docker rmi -f php2shell-lab:latest php84-uaf:latest 2>/dev/null || true
