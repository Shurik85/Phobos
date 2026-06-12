export default definePermissionEventHandler('admin', 'any', async () => {
  if (!(await Database.warp.isRegistered())) {
    throw createError({
      statusCode: 400,
      statusMessage: 'WARP is not registered.',
    });
  }

  const warp = await Database.warp.get();
  return WarpInterface.buildUserConfig(warp, !WG_ENV.DISABLE_IPV6);
});
