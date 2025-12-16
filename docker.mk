include .env

default: up

COMPOSER_ROOT ?= /var/www/html
DRUPAL_ROOT ?= /var/www/html/web
SUFFIX_CONTAINER ?= _civicrm
NAME_CONTAINER=$(PROJECT_NAME)$(SUFFIX_CONTAINER)


SUFFIX_CONTAINER_MYSQL ?= _mysql
NAME_CONTAINER_MYSQL=$(PROJECT_NAME)$(SUFFIX_CONTAINER_MYSQL)

IP_CONTAINER=$(shell docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(NAME_CONTAINER))
IP_CONTAINER_MYSQL=$(shell docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(NAME_CONTAINER_MYSQL))

.PHONY: help
ifneq (,$(wildcard docker.mk))
help : docker.mk
	@sed -n 's/^##//p' $<
else
help : Makefile
	@sed -n 's/^##//p' $<
endif

.PHONY: up
up:
	@echo "Starting up containers for $(PROJECT_NAME)..."
	docker-compose pull
	docker-compose up -d --remove-orphans

.PHONY: mutagen
mutagen:
	mutagen-compose up

.PHONY: down
down: stop

.PHONY: start
start:
	@echo "Starting containers for $(PROJECT_NAME) from where you left off..."
	@docker-compose start

.PHONY: stop
stop:
	@echo "Stopping containers for $(PROJECT_NAME)..."
	@docker-compose stop

.PHONY: prune
prune:
	@echo "Removing containers for $(PROJECT_NAME)..."
	@docker-compose down -v $(filter-out $@,$(MAKECMDGOALS))

.PHONY: ps
ps:
	@docker ps --filter name='$(PROJECT_NAME)*'

.PHONY: shell
shell:
	docker exec -ti -e COLUMNS=$(shell tput cols) -e LINES=$(shell tput lines) $(shell docker ps --filter name='$(PROJECT_NAME)_$(or $(filter-out $@,$(MAKECMDGOALS)), 'php')' --format "{{ .ID }}") sh

.PHONY: composer
composer:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") composer --working-dir=$(COMPOSER_ROOT) $(filter-out $@,$(MAKECMDGOALS))

.PHONY: drush
drush:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") drush --uri=$(PROJECT_NAME).$(DOMAIN) -r $(DRUPAL_ROOT) $(filter-out $@,$(MAKECMDGOALS))

.PHONY: drush_uli
drush_uli:
	@echo "Opening browser with one-time login link..."
	xdg-open $(shell docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") drush --uri=$(PROJECT_NAME).$(DOMAIN) -r $(DRUPAL_ROOT) uli)

.PHONY: cv
cv:
	docker exec -w $(DRUPAL_ROOT) $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") cv $(filter-out $@,$(MAKECMDGOALS))

.PHONY: clean_database_test
clean_database_test:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") mysql -u root -padmin -e "DROP DATABASE IF EXISTS test; CREATE DATABASE test;" $(filter-out $@,$(MAKECMDGOALS))

.PHONY: phpunit_setup
phpunit_setup:
	rm -rf html/phpunit.xml
	cp phpunit.xml.dist html/phpunit.xml
	sed -ri 's/name\=\"SIMPLETEST_DB\"\ value\=\"(.*)\"/name\=\"SIMPLETEST_DB\"\ value\=\"mysql:\/\/root\:admin\@$(PROJECT_NAME)_mysql\:3306\/test\"/g' html/phpunit.xml
	sed -ri 's/name\=\"SIMPLETEST_BASE_URL\"\ value\=\"(.*)\"/name\=\"SIMPLETEST_BASE_URL\"\ value\=\"http\:\/\/$(IP_CONTAINER)\"/g' html/phpunit.xml
	sed -ri 's/name\=\"BROWSERTEST_OUTPUT_BASE_URL\"\ value\=\"(.*)\"/name\=\"BROWSERTEST_OUTPUT_BASE_URL\"\ value\=\"http\:\/\/$(PROJECT_NAME)\.localhost\"/g' html/phpunit.xml
	sed -i 's/ALIAS_SELENIUM/$(PROJECT_NAME)_selenium/g' html/phpunit.xml
	mkdir -p html/web/sites/simpletest/browsertests

.PHONY: phpunit
phpunit:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") sudo -u www-data /var/www/html/vendor/phpunit/phpunit/phpunit -v -c /var/www/html/phpunit.xml $(EXTRA)

.PHONY: clone_repo
clone_repo:
	rm -rf html
	git clone -b ${REPO_DRUPAL_TAG} ${REPO_DRUPAL} html

.PHONY: download_repo
download_repo:
	rm -rf html
	mkdir html
	wget -O html/drupal.zip ${REPO_DRUPAL_ZIP}
	unzip -d html html/drupal.zip
	rm html/drupal.zip
	docker-compose down && docker-compose up -d

.PHONY: install_drupal
install_drupal:
	# Related issue with multisite
	# Check if exist directory settings
	if [ docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") -d $(DRUPAL_ROOT)/sites/default ]; then \
		docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") mkdir $(DRUPAL_ROOT)/sites/default; \
	fi
	# Check if exist file settings.php
	if [ docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") -f $(DRUPAL_ROOT)/sites/default/settings.php ]; then \
		docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") cd $(DRUPAL_ROOT)/sites/default/ && wget https://raw.githubusercontent.com/drupal/drupal/$(REPO_DRUPAL_TAG)/sites/default/default.settings.php; \
	fi
	# Overwrite all set_permissions
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") sudo chmod 777 $(DRUPAL_ROOT)/sites/default
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") mysql -u root -padmin -e "DROP DATABASE IF EXISTS drupal; CREATE DATABASE drupal;"
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") drush -r $(DRUPAL_ROOT) site-install ${PROFILE} --db-url=mysql://root:admin@${PROJECT_NAME}_mysql:3306/drupal --account-pass=admin --uri=http://$(PROJECT_NAME).$(DOMAIN) -y
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") sudo chmod 777 $(DRUPAL_ROOT)/sites/default
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") drush -l http://${PROJECT_NAME}.${DOMAIN} -r $(DRUPAL_ROOT) en $(MODULES) -y
	make set_permissions

.PHONY: uninstall_drupal
uninstall_drupal:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") mysql -u root -padmin -e "DROP DATABASE IF EXISTS drupal;"
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") rm -f $(DRUPAL_ROOT)/sites/default/settings.php
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") rm -f $(DRUPAL_ROOT)/sites/default/civicrm.settings.php
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") rm -rf $(DRUPAL_ROOT)/sites/default/files
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") mkdir files
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") sudo chown -R www-data:www-data $(DRUPAL_ROOT)

.PHONY: add_required_files_install
add_required_files_install:
	cp drupal_files_default/default.settings.php $(DRUPAL_ROOT)/sites/default/default.settings.php
	cp drupal_files_default/default.services.yml $(DRUPAL_ROOT)/sites/default/default.services.yml

.PHONY: set_permissions
set_permissions:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") sudo chown -R www-data:www-data $(DRUPAL_ROOT)

.PHONY: download_drupal_civicrm
download_drupal_civicrm:
	sudo rm -rf html
	mkdir html
	git clone -b ${REPO_DRUPAL_CIVICRM_TAG} ${REPO_DRUPAL_CIVICRM} html
	docker-compose down && docker-compose up -d
#	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") composer install --working-dir=$(COMPOSER_ROOT)



.PHONE: sync_external_db
sync_external_db:
#Pending to set a bigger insert in the external SET GLOBAL bulk_insert_buffer_size = 1024 * 1024 * 256;
	ssh $(SSH_REMOTE_EXTRA_PARAMS) $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST) "mysqldump --skip-triggers -u $(MYSQL_REMOTE_USER) -p$(MYSQL_REMOTE_PASS) -h $(MYSQL_REMOTE_HOST) $(MYSQL_REMOTE_DB)" | gzip > $(MYSQL_REMOTE_DB).sql.gz
	gunzip  $(MYSQL_REMOTE_DB).sql.gz
	docker cp $(MYSQL_REMOTE_DB).sql $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}"):/$(MYSQL_REMOTE_DB).sql
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") mysql -u root -padmin -e "DROP DATABASE IF EXISTS drupal; CREATE DATABASE drupal;"
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") ls /
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") echo $(MYSQL_REMOTE_DB).sql
	docker exec -i $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") mysql -u root -padmin drupal < $(MYSQL_REMOTE_DB).sql $(filter-out $@,$(MAKECMDGOALS))
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") rm $(MYSQL_REMOTE_DB).sql
	sudo rsync -uzva --no-l -e "ssh $(SSH_REMOTE_EXTRA_PARAMS)" $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH)/files/civicrm html/web/sites/default/files/
	sudo rsync -uzva --no-l -e "ssh $(SSH_REMOTE_EXTRA_PARAMS)" $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH)/modules html/web/sites/default
	sudo rsync -uzva --no-l -e "ssh $(SSH_REMOTE_EXTRA_PARAMS)" $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH)/themes html/web/sites/default
	sudo rsync -uzva --no-l -e "ssh $(SSH_REMOTE_EXTRA_PARAMS)" $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH)/libraries html/web/sites/default
	sudo rsync -uzva --no-l -e "ssh $(SSH_REMOTE_EXTRA_PARAMS)" $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH)/vendor html/web/sites/default
	make set_permissions

replace_local_db_with_external_db:
	@read -p "Do you have a database dump file to import directly? [y/N] " USE_EXISTING_DB; \
	if [ "$$USE_EXISTING_DB" = "y" ] || [ "$$USE_EXISTING_DB" = "Y" ]; then \
		read -p "Enter the filename: " DB_FILE; \
		if [ ! -f "$$DB_FILE" ]; then \
			echo "File $$DB_FILE not found!"; \
			exit 1; \
		fi; \
	else \
		RESPONSE_PARAMS_MYSQL=$$(ssh $(SSH_REMOTE_EXTRA_PARAMS) $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST) $(DRUSH_BASH_EXECUTION) sql-connect); \
		echo "Original Connection String: $$RESPONSE_PARAMS_MYSQL"; \
		MYSQL_REMOTE_USER=$$(echo "$$RESPONSE_PARAMS_MYSQL" | grep -Po '(?<=--user=)[^ ]+' || true); \
		MYSQL_REMOTE_PASS=$$(echo "$$RESPONSE_PARAMS_MYSQL" | grep -Po '(?<=--password=)[^ ]+' || true); \
		MYSQL_REMOTE_DB=$$(echo "$$RESPONSE_PARAMS_MYSQL" | grep -Po '(?<=--database=)[^ ]+' || true); \
		MYSQL_REMOTE_HOST=$$(echo "$$RESPONSE_PARAMS_MYSQL" | grep -Po '(?<=--host=)[^ ]+' || true); \
		MYSQL_REMOTE_PORT=$$(echo "$$RESPONSE_PARAMS_MYSQL" | grep -Po '(?<=--port=)[^ ]+' || true); \
		echo "User:     $$MYSQL_REMOTE_USER"; \
		echo "Password: $$MYSQL_REMOTE_PASS"; \
		echo "Database: $$MYSQL_REMOTE_DB"; \
		echo "Host:     $$MYSQL_REMOTE_HOST"; \
		echo "Port:     $$MYSQL_REMOTE_PORT"; \
		ssh $(SSH_REMOTE_EXTRA_PARAMS) $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST) "mysqldump --skip-triggers -u $$MYSQL_REMOTE_USER -p$$MYSQL_REMOTE_PASS -h $$MYSQL_REMOTE_HOST $$MYSQL_REMOTE_DB" | gzip > $$MYSQL_REMOTE_DB.sql.gz; \
		gunzip -f $$MYSQL_REMOTE_DB.sql.gz; \
		DB_FILE=$$MYSQL_REMOTE_DB.sql; \
	fi; \
	docker cp $$DB_FILE $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}"):/$$DB_FILE; \
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") mysql -u root -padmin -e "DROP DATABASE IF EXISTS drupal; CREATE DATABASE drupal;"; \
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") sh -c "mysql -u root -padmin drupal < /$$DB_FILE"; \
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_mysql' --format "{{ .ID }}") rm /$$DB_FILE; \
	read -p "Do you want to delete the database dump file ($$DB_FILE)? [y/N] " DELETE_DB_FILE; \
	if [ "$$DELETE_DB_FILE" = "y" ] || [ "$$DELETE_DB_FILE" = "Y" ]; then \
		rm $$DB_FILE; \
		echo "Database dump file removed."; \
	else \
		echo "Database dump file kept."; \
	fi

# Get the remote files from the remote server with scp, check if not exist the directory html and create
get_remote_files:
	@echo "Getting remote files from $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH) to html"
	@mkdir -p html
	rsync -avz -e "ssh $(SSH_REMOTE_EXTRA_PARAMS)" $(SSH_REMOTE_USER)@$(SSH_REMOTE_HOST):$(SSH_REMOTE_PATH) html
	
# Replace the configuration in the database from the settings.php with regex
# Fixed path to the settings.php file, html/web/sites/default/settings.php
# $databases['default']['default'] = array (
#   'database' => 'xxxx',
#   'username' => 'xxxx',
#   'password' => 'xxxx',
replace_settings:
# Replace database configuration
	@echo "Validating replacement for database settings..."
	@CID=$(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}"); \
	if [ -z "$$CID" ]; then echo "Container not found"; exit 1; fi; \
	\
	CURRENT_DB=$$(docker exec $$CID grep "'database'\s*=>" "$(SETTINGS_FILE)" | grep -v "^\s*\*" || echo "[DB Not Found]"); \
	PROPOSED_DB=$$(docker exec $$CID sed "/^\s*\*/! s|\('database'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_DB)\2|g" "$(SETTINGS_FILE)" | grep "'database'\s*=>" | grep -v "^\s*\*" || echo "[DB Not Found]"); \
	\
	CURRENT_USER=$$(docker exec $$CID grep "'username'\s*=>" "$(SETTINGS_FILE)" | grep -v "^\s*\*" || echo "[User Not Found]"); \
	PROPOSED_USER=$$(docker exec $$CID sed "/^\s*\*/! s|\('username'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_USER)\2|g" "$(SETTINGS_FILE)" | grep "'username'\s*=>" | grep -v "^\s*\*" || echo "[User Not Found]"); \
	\
	CURRENT_PASS=$$(docker exec $$CID grep "'password'\s*=>" "$(SETTINGS_FILE)" | grep -v "^\s*\*" || echo "[Pass Not Found]"); \
	PROPOSED_PASS=$$(docker exec $$CID sed "/^\s*\*/! s|\('password'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_PASS)\2|g" "$(SETTINGS_FILE)" | grep "'password'\s*=>" | grep -v "^\s*\*" || echo "[Pass Not Found]"); \
	\
	CURRENT_HOST=$$(docker exec $$CID grep "'host'\s*=>" "$(SETTINGS_FILE)" | grep -v "^\s*\*" || echo "[Host Not Found]"); \
	PROPOSED_HOST=$$(docker exec $$CID sed "/^\s*\*/! s|\('host'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_HOST)\2|g" "$(SETTINGS_FILE)" | grep "'host'\s*=>" | grep -v "^\s*\*" || echo "[Host Not Found]"); \
	\
	echo "---------------------------------------------------"; \
	echo "Current Database: $$CURRENT_DB"; \
	echo "Proposed Database: $$PROPOSED_DB"; \
	echo "Current User:     $$CURRENT_USER"; \
	echo "Proposed User:    $$PROPOSED_USER"; \
	echo "Current Password: $$CURRENT_PASS"; \
	echo "Proposed Password: $$PROPOSED_PASS"; \
	echo "Current Host:     $$CURRENT_HOST"; \
	echo "Proposed Host:    $$PROPOSED_HOST"; \
	echo "---------------------------------------------------"; \
	\
	read -p "Are these proposed changes correct? [y/N] " CONFIRM; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		docker exec $$CID sed -i "/^\s*\*/! s|\('database'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_DB)\2|g" "$(SETTINGS_FILE)"; \
		docker exec $$CID sed -i "/^\s*\*/! s|\('username'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_USER)\2|g" "$(SETTINGS_FILE)"; \
		docker exec $$CID sed -i "/^\s*\*/! s|\('password'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_PASS)\2|g" "$(SETTINGS_FILE)"; \
		docker exec $$CID sed -i "/^\s*\*/! s|\('host'\s*=>\s*'\)[^']*\('\)|\1$(MYSQL_LOCAL_HOST)\2|g" "$(SETTINGS_FILE)"; \
		echo "All replacements applied."; \
	else \
		echo "Replacement aborted by user."; \
		exit 1; \
	fi

.PHONY connect_vpn:
connect_vpn:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") vpnc-connect --local-port 0 $(VPN_CONFIG_FILE)
# ToDo veifry if exist previously the register in /etc/hosts
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}")  /bin/sh -c "echo $(IP_CONTAINER_MYSQL) $(NAME_CONTAINER_MYSQL) >> /etc/hosts"
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") cat /etc/hosts

.PHONY disconnect_vpn:
disconnect_vpn:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") vpnc-disconnect

.PHONY: import_site
import_site:
	@echo "=== Starting Import Site Workflow ==="
	@echo "Step 1/4: Stopping existing containers..."
	@docker-compose down
	@echo "Step 2/4: Starting fresh containers..."
	@docker-compose pull
	@docker-compose up -d --remove-orphans
	@echo "Waiting for containers to be ready..."
	@sleep 10
	@echo "Step 3/4: Syncing database and files from remote..."
	$(MAKE) sync_external_db
	@echo "Step 4/4: Setting permissions..."
	$(MAKE) set_permissions
	@echo "=== Import Site Workflow Complete ==="
	@echo "Run 'make drush_uli' to get a one-time login link."

.PHONY: logs
logs:
	@docker-compose logs -f $(filter-out $@,$(MAKECMDGOALS))

.PHONY: get_ipv_vpn
get_ipv_vpn:
	docker exec $(shell docker ps --filter name='^/$(PROJECT_NAME)_civicrm' --format "{{ .ID }}") ip addr show tun0 | grep -Po 'inet \K[\d.]+'

# https://stackoverflow.com/a/6273809/1826109
%:
	@: