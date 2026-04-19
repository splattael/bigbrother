update:
	shards check || shards update

build: update
	shards build

build-release:
	shards build --production
	strip bin/bigbrother

build-docker:
	docker buildx build  --progress=plain .
