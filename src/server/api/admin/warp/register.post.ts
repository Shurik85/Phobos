import { maskWarp } from '#db/repositories/warp/service';

export default definePermissionEventHandler('admin', 'any', async () => {
  try {
    await WarpInterface.register();
  } catch (e) {
    throw createError({
      statusCode: 400,
      statusMessage: (e as Error).message,
    });
  }

  const warp = await Database.warp.get();
  return maskWarp(warp);
});
