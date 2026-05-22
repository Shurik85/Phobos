import { ClientGetSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'view',
  async ({ event, checkPermissions }) => {
    const { clientId } = await getValidatedRouterParams(
      event,
      validateZod(ClientGetSchema, event)
    );

    const client = await Database.clients.get(clientId);
    checkPermissions(client);

    const config = await WireGuard.getClientFullConfig({ clientId });
    setHeader(event, 'Content-Type', 'text/plain; charset=utf-8');
    return config;
  }
);
