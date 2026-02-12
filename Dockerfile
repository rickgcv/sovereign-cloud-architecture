# Build context: repository root (so we can copy both website/ and images/)
# Use unprivileged nginx image (listens on 8080, runs as non-root) for OpenShift
FROM nginxinc/nginx-unprivileged:1.25-alpine

# Remove default config and static content; then copy our config
USER root
RUN rm -rf /usr/share/nginx/html/* /etc/nginx/conf.d/default.conf
COPY website/nginx.conf /etc/nginx/conf.d/default.conf
RUN chown 101:101 /etc/nginx/conf.d/default.conf
USER 101

# Copy website assets (HTML, CSS) and image
COPY --chown=101:101 website/ /usr/share/nginx/html/
COPY --chown=101:101 images/sovereign-cloud-overview.png /usr/share/nginx/html/images/

# Unprivileged image already listens on 8080 and runs as non-root
EXPOSE 8080
