SHELL := /usr/bin/env bash

.PHONY: install check sync logs backup dots dots-local validate reload

install:
	./install.sh

check:
	./post-install-check.sh

sync:
	./sync.sh

logs:
	./logs.sh

backup:
	./backup.sh

dots:
	./bootstrap-dotfiles.sh

dots-local:
	./bootstrap-dotfiles.sh --local

validate:
	niri validate

reload:
	niri msg action reload-config || true
