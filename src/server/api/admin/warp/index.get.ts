import { maskWarp } from '#db/repositories/warp/service';

export default definePermissionEventHandler('admin', 'any', async () => {
  const [warp, wgInterface, status] = await Promise.all([
    Database.warp.get(),
    Database.interfaces.get(),
    WarpInterface.status(),
  ]);

  return {
    ...maskWarp(warp),
    egressMode: wgInterface.egressMode,
    online: status.online,
    lastHandshakeAt: status.lastHandshakeAt,
  };
});
