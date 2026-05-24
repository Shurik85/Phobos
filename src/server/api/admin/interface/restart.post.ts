export default definePermissionEventHandler('admin', 'any', async () => {
  await WireGuard.Restart();
  await Obfuscator.applyAll();
  PhobosPackage.invalidate();

  return { success: true };
});
