import {
  readTlsOrigin,
  isUntrustedTls,
  isExternalTlsManaged,
} from '~~/server/utils/TlsInfo';

export default defineEventHandler(async () => {
  const insecure =
    WG_ENV.INSECURE || (await Database.general.getAllowInsecureHttpLogin());
  const wgInterface = await Database.interfaces.get();

  const tlsOrigin = readTlsOrigin();
  const tlsUntrusted = isUntrustedTls(tlsOrigin);
  const tlsManagedExternally = isExternalTlsManaged();

  return {
    currentRelease: RELEASE,
    insecure,
    firewallEnabled: wgInterface.firewallEnabled,
    tlsOrigin,
    tlsUntrusted,
    tlsManagedExternally,
  };
});
