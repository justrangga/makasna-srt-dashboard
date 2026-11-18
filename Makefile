.PHONY: check test install

check:
	python3 -m compileall -q app.py
	bash -n scripts/install.sh

install:
	sudo bash scripts/install.sh

test:
	python3 -m unittest discover -s tests -v
