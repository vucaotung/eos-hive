FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev
COPY server.js ./
USER node
ENV NODE_ENV=production
EXPOSE 8090
CMD ["node", "server.js"]
