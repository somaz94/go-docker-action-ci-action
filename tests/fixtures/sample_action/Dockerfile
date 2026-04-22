FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/sample_action ./cmd

FROM gcr.io/distroless/static-debian12:nonroot
ARG FIXTURE_BUILD_ARG=default
LABEL fixture.build_arg=${FIXTURE_BUILD_ARG}
COPY --from=build /out/sample_action /sample_action
ENTRYPOINT ["/sample_action"]
