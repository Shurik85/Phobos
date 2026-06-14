export default definePermissionEventHandler('admin', 'any', async () => {
  if (!(await Database.warp.isRegistered())) {
    throw createError({
      statusCode: 400,
      statusMessage: 'WARP is not registered.',
    });
  }

  const online = await WarpInterface.connectivityCheck();
  return { online };
});
