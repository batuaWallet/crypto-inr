SHELL=/bin/bash # shell make will use to execute commands
VPATH=.flags # prerequisite search path
$(shell mkdir -p $(VPATH))

root=$(shell cd "$(shell dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
project=$(shell cat $(root)/package.json | grep '"name":' | head -n 1 | cut -d '"' -f 4 | tr '-' '_')
commit=$(shell git rev-parse HEAD | head -c 8)

# If Linux, give the container our uid & gid so we know what to reset permissions to.
# If Mac, the docker-VM takes care of this for us so we'll pass in root's id (ie noop)
id=$(shell if [[ "`uname`" == "Darwin" ]]; then echo 0:0; else echo "`id -u`:`id -g`"; fi)
interactive=$(shell if [[ -t 0 && -t 2 ]]; then echo "--interactive"; else echo ""; fi)
find_options=-type f -not -path "*/node_modules/*" -not -name "address-book.json" -not -name "*.swp" -not -path "*/.*" -not -path "*/cache/*" -not -path "*/build/*" -not -path "*/dist/*" -not -name "*.log"

docker_run=docker run --name=$(project)_builder $(interactive) --tty --rm --volume=$(root):/root $(project)_builder $(id)

# Helper & Logging utils
startTime=.flags/.startTime
totalTime=.flags/.totalTime
log_start=@echo "=============";echo "[Makefile] => Start building $@"; date "+%s" > $(startTime)
log_finish=@echo $$((`date "+%s"` - `cat $(startTime)`)) > $(totalTime); rm $(startTime); echo "[Makefile] => Finished building $@ in `cat $(totalTime)` seconds";echo "=============";echo

########################################
## Alias Rules

default: transpiled-ts

########################################
## Command & Control Rules

start-oracle:
	bash ops/start-oracle.sh
restart-oracle: stop-oracle
	bash ops/start-oracle.sh
stop-oracle:
	bash ops/stop.sh oracle

clean:
	rm -rf .flags/*
	rm -rf artifacts/*
	rm -rf dist/*

########################################
## Build Rules

builder: $(shell find ops/builder $(find_options))
	$(log_start)
	docker build --file ops/builder/Dockerfile --tag $(project)_builder ops/builder
	docker tag ${project}_builder ${project}_builder:$(commit)
	$(log_finish) && mv -f $(totalTime) .flags/$@

node-modules: builder package.json
	$(log_start)
	$(docker_run) "npm install"
	$(log_finish) && mv -f $(totalTime) .flags/$@

compiled-sol: node-modules $(shell find src.sol $(find_options))
	$(log_start)
	$(docker_run) "npm run compile"
	$(log_finish) && mv -f $(totalTime) .flags/$@

transpiled-ts: node-modules compiled-sol $(shell find src.ts $(find_options))
	$(log_start)
	$(docker_run) "npm run transpile"
	$(log_finish) && mv -f $(totalTime) .flags/$@