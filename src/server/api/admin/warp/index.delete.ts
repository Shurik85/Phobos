export default definePermissionEventHandler('admin', 'any', async () => {
  await WarpInterface.delete();
  return { success: true };
});
