.PHONY: install test debug run

install:
	./hyper_index.sh doctor

test:
	./hyper_index.sh auto-test

debug:
	./hyper_index.sh auto-debug

run:
	./hyper_index.sh serve --host 0.0.0.0
