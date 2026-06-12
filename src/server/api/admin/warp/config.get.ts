export default definePermissionEventHandler('admin', 'any', async () => {
  if (!(await Database.warp.isRegistered())) {
    throw createError({
      statusCode: 400,
      statusMessage: 'WARP is not registered.',
    });
  }

  try {
    return await WarpInterface.remoteConfig();
  } catch (e) {
    throw createError({
      statusCode: 400,
      statusMessage: (e as Error).message,
    });
  }
});
