import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { env } from './env';
import { fastifyTRPCPlugin } from '@trpc/server/adapters/fastify';
import { clerkPlugin, getAuth } from '@clerk/fastify';
import { appRouter } from '@amygdala/types';

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

  // Automatically parses Clerk tokens into the `req` context bridging it
  await server.register(clerkPlugin);

  server.get('/health', async () => ({
    ok: true,
    service: 'backend',
    env: env.NODE_ENV,
  }));

  await server.register(fastifyTRPCPlugin, {
    prefix: '/trpc',
    trpcOptions: {
      router: appRouter,
      createContext: ({ req }: any) => {
        // extract clerk user info seamlessly injected from `clerkPlugin`
        const auth = getAuth(req);
        return {
          clerkAuth: auth ? { userId: auth.userId } : null,
        };
      },
    },
  });

  return server;
}
