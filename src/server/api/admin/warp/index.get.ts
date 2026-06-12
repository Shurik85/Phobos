import { maskWarp } from '#db/repositories/warp/service';

export default definePermissionEventHandler('admin', 'any', async () => {
  const [warp, wgInterface] = await Promise.all([
    Database.warp.get(),
    Database.interfaces.get(),
  ]);

  return {
    ...maskWarp(warp),
    egressMode: wgInterface.egressMode,
  };
});
