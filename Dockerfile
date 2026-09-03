FROM ruby:alpine

WORKDIR /app

# Install webrick and cli_class_tool gems
RUN gem install webrick cli_class_tool

# Copy application code
COPY lib/ ./lib/
COPY bin/cve-api-server ./bin/cve-api-server

# Expose WEBrick port
EXPOSE 4567

# Default environment variables
ENV PORT=4567
ENV CVE_DATA_DIR=/data

# Run the API server
CMD ["ruby", "./bin/cve-api-server"]
