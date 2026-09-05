FROM node:22-slim

RUN npm install -g @switchbot/openapi-cli

EXPOSE 8080

CMD ["switchbot", "mcp", "serve", "--port", "8080", "--bind", "0.0.0.0"]
