# --- build stage ---
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/server main.go

# --- runtime stage ---
FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=build /out/server ./server
COPY static ./static
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
