
up:
	docker-compose up -d

down:
	docker-compose down -v

ssh:
	docker exec -it totp-postgres /bin/bash

install:
	docker exec totp-postgres /sql-bin/install.sh

  