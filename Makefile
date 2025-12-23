
# Como usar: make push-auth branch=feature/minha-feature
branch ?= develop

# --- PULL (Geralmente puxamos da develop) ---
pull-auth:
	git subtree pull --prefix=services/auth remote-auth $(branch) --squash

pull-orders:
	git subtree pull --prefix=services/orders remote-orders $(branch) --squash

pull-tracking:
	git subtree pull --prefix=services/tracking remote-tracking $(branch) --squash

	
# --- PUSH (Enviamos para features) ---
push-auth:
	git subtree push --prefix=services/auth remote-auth $(branch)

push-orders:
	git subtree push --prefix=services/orders remote-orders $(branch)

push-tracking:
	git subtree push --prefix=services/tracking remote-tracking $(branch)