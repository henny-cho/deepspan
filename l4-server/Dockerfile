# SPDX-License-Identifier: Apache-2.0
FROM gcr.io/distroless/static:nonroot
COPY deepspan-server /
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/deepspan-server"]
