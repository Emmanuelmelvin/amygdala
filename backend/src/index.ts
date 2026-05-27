import 'dotenv/config';
import { buildServer } from './server';
import { env } from './env';

async function main() {
  const server = await buildServer();

  try {
    await server.listen({
      port: env.PORT,
      host: env.HOST,
    });
  } catch (error) {
    server.log.error(error);
    process.exit(1);
  }
}

void main();
