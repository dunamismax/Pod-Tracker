FROM oven/bun:1.2 AS deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install

FROM deps AS build
WORKDIR /app
COPY . .
RUN bun run build

FROM oven/bun:1.2 AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/build ./build
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/scripts ./scripts

EXPOSE 3000

CMD ["bun", "run", "start"]
