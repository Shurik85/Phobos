import {
  readTlsOrigin,
  isUntrustedTls,
  isExternalTlsManaged,
} from '~~/server/utils/TlsInfo';

export default defineEventHandler(async () => {
  const wgInterface = await Database.interfaces.get();

  const tlsOrigin = readTlsOrigin();
  const tlsUntrusted = isUntrustedTls(tlsOrigin);
  const tlsManagedExternally = isExternalTlsManaged();

  return {
    currentRelease: RELEASE,
    firewallEnabled: wgInterface.firewallEnabled,
    tlsOrigin,
    tlsUntrusted,
    tlsManagedExternally,
  };
});
