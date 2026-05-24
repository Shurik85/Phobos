export default definePermissionEventHandler('admin', 'any', async () => {
  const wgInterface = await Database.interfaces.get();
  const { privateKey, port, ...rest } = wgInterface;
  void privateKey;
  void port;
  return {
    ...rest,
    privateKey: undefined,
  };
});
