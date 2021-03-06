# Build image container
FROM golang:1.13.4 AS build
ARG K8S_VERSION=v1.15.2
ARG HELM_VERSION=3.3.1
WORKDIR /build
COPY . /build

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o kubot .

RUN curl https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz --output /tmp/helm.tar.gz \
	&& tar -zxvf /tmp/helm.tar.gz -C /tmp \
	&& mv /tmp/linux-amd64/helm /usr/local/bin/helm \
	&& rm -rf /tmp/linux-amd64 \
	&& rm /tmp/helm.tar.gz

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kubectl \
	&& chmod +x ./kubectl \
	&& mv ./kubectl /usr/local/bin/kubectl


# CA Certificates
FROM alpine:latest AS alpine-base
RUN apk --update --no-cache add ca-certificates

# Production image container
FROM alpine:latest
LABEL Description="Deployment bot"
ARG MSSQL_VERSION=17.5.2.1-1

ENV KUBOT_CONFIG=/conf/kubot.yml

RUN apk --update --no-cache add bash curl git jq

RUN apk add --no-cache gnupg --virtual .build-dependencies -- && \
    # Download mssql-tools and msodbcsql
    curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/msodbcsql17_${MSSQL_VERSION}_amd64.apk && \
    curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/mssql-tools_${MSSQL_VERSION}_amd64.apk && \
    # Verifying signature
    curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/msodbcsql17_${MSSQL_VERSION}_amd64.sig && \
    curl -O https://download.microsoft.com/download/e/4/e/e4e67866-dffd-428c-aac7-8d28ddafb39b/mssql-tools_${MSSQL_VERSION}_amd64.sig && \
    # Importing gpg key
    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --import - && \
    gpg --verify msodbcsql17_${MSSQL_VERSION}_amd64.sig msodbcsql17_${MSSQL_VERSION}_amd64.apk && \
    gpg --verify mssql-tools_${MSSQL_VERSION}_amd64.sig mssql-tools_${MSSQL_VERSION}_amd64.apk && \
    # Installing packages
    echo y | apk add --allow-untrusted msodbcsql17_${MSSQL_VERSION}_amd64.apk mssql-tools_${MSSQL_VERSION}_amd64.apk && \
    # Deleting packages
    apk del .build-dependencies && rm -f ms*.sig ms*.apk && \
	# Create symbolic links
	ln -s /opt/mssql-tools/bin/bcp /usr/local/bin/bcp && \
	ln -s /opt/mssql-tools/bin/sqlcmd /usr/local/bin/sqlcmd

COPY --from=alpine-base /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /build/kubot /opt/kubot/
COPY --from=build /usr/local/bin/helm /usr/local/bin
COPY --from=build /usr/local/bin/kubectl /usr/local/bin

VOLUME ["/opt/kubot/log"]

ENTRYPOINT [ "/opt/kubot/kubot" ]
