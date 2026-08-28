# redis-backup bundles the three tools the Redis strategy Pod needs and that no
# single stock image carries together: redis-cli (dump + replay), curl (SigV4 S3
# transport), and an RDB->RESP converter for the restore replay. The spotahome
# operator ships no backup CRD, so the strategy runs this image as a one-shot Job.
FROM golang:1.26-alpine AS rdbtool

ARG TARGETOS
ARG TARGETARCH

# hdt3213/rdb converts an RDB snapshot to an AOF (RESP) stream that redis-cli
# --pipe can replay. Preferred over redis-rdb-tools because it tracks newer RDB
# versions, which matter for the redis 7/8 the app deploys.
ARG RDB_VERSION=v0.1.9
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH CGO_ENABLED=0 \
	go install github.com/hdt3213/rdb@${RDB_VERSION}

FROM alpine:3.20

RUN apk add --no-cache redis curl ca-certificates

COPY --from=rdbtool /go/bin/rdb /usr/local/bin/rdb

USER 65532:65532
