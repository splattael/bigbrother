update:
	shards check || shards update

build: update
	shards build

build-release:
	shards build --production
	strip bin/bigbrother
