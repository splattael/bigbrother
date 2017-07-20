FROM debian:sid-slim

RUN apt-get update && apt-get install -yy ca-certificates && apt-get clean

ADD bin/bigbrother /

ENTRYPOINT ["/bigbrother"]
