import { initTRPC, TRPCError } from '@trpc/server';

export interface Context {
  clerkAuth?: {
    userId: string | null;
  } | null;
}

const t = initTRPC.context<Context>().create();

export const publicProcedure = t.procedure;

export const protectedProcedure = t.procedure.use(({ ctx, next }) => {
  if (!ctx.clerkAuth?.userId) {
    throw new TRPCError({ code: 'UNAUTHORIZED' });
  }
  return next({
    ctx: {
      clerkAuth: ctx.clerkAuth,
    },
  });
});

export const router = t.router;

export const appRouter = router({
  health: publicProcedure.query(() => {
    return { ok: true, status: 'healthy', time: new Date() };
  }),
  me: protectedProcedure.query(({ ctx }) => {
    return { userId: ctx.clerkAuth.userId };
  })
});

export type AppRouter = typeof appRouter;
