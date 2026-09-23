.PHONY: compile test clean

compile:
	erlc -o erlang erlang/startup.erl

test: compile
	./tests/probar.sh

clean:
	rm -f erlang/*.beam
	rm -rf .tmp tests/salidas
