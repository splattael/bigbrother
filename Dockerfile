FROM crystallang/crystal:1.17-alpine

WORKDIR /code

COPY . .
RUN make build-release

ENTRYPOINT ["./bin/bigbrother"]
