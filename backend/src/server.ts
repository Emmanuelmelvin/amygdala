import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { env } from './env';

export async function buildServer() {
  const server = Fastify({
    logger: true,
  });

  await server.register(cors, {
    origin: true,
  });

  await server.register(jwt, {
    secret: process.env.JWT_SECRET ?? 'dev-secret',
  });

  server.get('/health', async () => ({
    ok: true,
    service: 'backend',
    env: env.NODE_ENV,
  }));

  return server;
}
