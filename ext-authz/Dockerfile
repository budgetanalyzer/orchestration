FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -o ext-authz .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/ext-authz /ext-authz
USER nonroot:nonroot
EXPOSE 9001 8090
ENTRYPOINT ["/ext-authz"]
