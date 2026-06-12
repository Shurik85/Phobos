export default definePermissionEventHandler('admin', 'any', async () => {
  await WireGuard.Restart();
  await Obfuscator.applyAll();
  await WarpInterface.reapply();
  PhobosPackage.invalidate();

  return { success: true };
});
