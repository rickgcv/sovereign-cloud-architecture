# Build context: repository root (so we can copy both website/ and images/)
# Use unprivileged nginx image (listens on 8080, runs as non-root) for OpenShift
FROM nginxinc/nginx-unprivileged:1.25-alpine

# Remove default config and static content; copy our config and site files
USER root
RUN rm -rf /usr/share/nginx/html/* && \
    rm -f /etc/nginx/conf.d/default.conf
COPY website/nginx.conf /etc/nginx/conf.d/default.conf
COPY website/ /usr/share/nginx/html/
COPY images/sovereign-cloud-overview.png /usr/share/nginx/html/images/

# OpenShift runs containers with a random UID; make everything readable (and dirs executable) by any user
RUN chown -R 101:101 /usr/share/nginx/html /etc/nginx/conf.d && \
    chmod -R a+rX /usr/share/nginx/html && \
    chmod a+r /etc/nginx/conf.d/default.conf

USER 101

# Unprivileged image already listens on 8080 and runs as non-root
EXPOSE 8080
