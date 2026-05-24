export default definePermissionEventHandler('admin', 'any', async () => {
  const [presets, counts] = await Promise.all([
    Database.obfuscatorPresets.list(),
    Database.obfuscatorPresets.clientCounts(),
  ]);
  return presets.map((p) => ({ ...p, clientCount: counts[p.id] ?? 0 }));
});
