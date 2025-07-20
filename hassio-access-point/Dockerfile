ARG BUILD_FROM
FROM $BUILD_FROM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG C.UTF-8

RUN apk update && \
apk add --no-cache bash iw hostapd bridge-utils networkmanager networkmanager-cli net-tools sudo iptables && \
rm -rf /var/cache/apk/*

COPY hostapd.conf /

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
