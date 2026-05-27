# Backend

Fastify + TypeScript backend for Amygdala.

## Scripts

- `npm run dev` - start the server in watch mode
- `npm run build` - compile TypeScript into `dist/`
- `npm start` - run the compiled server
- `npm run lint` - run ESLint

## Environment

Copy `.env.example` to `.env` and adjust values as needed.

- `PORT` - HTTP port, default `3001`
- `HOST` - bind host, default `0.0.0.0`
- `NODE_ENV` - runtime mode, default `development`

## Current API

- `GET /health` - health check endpoint
