## Minimal Dockerfile to run Meilisearch using the official image
## This allows Render (or other platforms) to find a Dockerfile at build time.

FROM getmeili/meilisearch:latest

# Disable anonymous analytics
ENV MEILI_NO_ANALYTICS=true

# Expose default Meilisearch HTTP port
EXPOSE 7700

# Allow the platform to provide MEILI_MASTER_KEY via environment variables
# If none provided, Meilisearch will start without a master key (not recommended for prod)
ENV MEILI_MASTER_KEY="${MEILI_MASTER_KEY:-}"

# Use the image default entrypoint; CMD kept for clarity
CMD ["meilisearch"]
