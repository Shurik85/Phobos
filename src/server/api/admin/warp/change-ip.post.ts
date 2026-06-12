import { maskWarp } from '#db/repositories/warp/service';

export default definePermissionEventHandler('admin', 'any', async () => {
  if (!(await Database.warp.isRegistered())) {
    throw createError({
      statusCode: 400,
      statusMessage: 'WARP is not registered.',
    });
  }

  try {
    await WarpInterface.changeIp();
  } catch (e) {
    throw createError({
      statusCode: 400,
      statusMessage: (e as Error).message,
    });
  }

  const warp = await Database.warp.get();
  return maskWarp(warp);
});
