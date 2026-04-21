update:
	shards check || shards update

build: update
	shards build

build-release:
	shards build bigbrother --production --release -Dpreview_mt --stats --time
	strip bin/bigbrother

build-docker:
	docker buildx build  --progress=plain .
