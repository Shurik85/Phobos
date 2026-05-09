import { gt } from 'semver';
import {
  readTlsOrigin,
  isUntrustedTls,
  isExternalTlsManaged,
} from '~~/server/utils/TlsInfo';

export default defineEventHandler(async () => {
  const latestRelease = await cachedFetchLatestRelease();
  const updateAvailable = gt(latestRelease.version, RELEASE);
  const insecure =
    WG_ENV.INSECURE || (await Database.general.getAllowInsecureHttpLogin());
  const wgInterface = await Database.interfaces.get();

  const envPort = Number(process.env.OBF_PORT);
  const obfuscatorPortPinned =
    Number.isFinite(envPort) && envPort >= 1024 && envPort <= 65535;

  const tlsOrigin = readTlsOrigin();
  const tlsUntrusted = isUntrustedTls(tlsOrigin);
  const tlsManagedExternally = isExternalTlsManaged();

  return {
    currentRelease: RELEASE,
    latestRelease: latestRelease,
    updateAvailable,
    insecure,
    firewallEnabled: wgInterface.firewallEnabled,
    obfuscatorPortPinned,
    tlsOrigin,
    tlsUntrusted,
    tlsManagedExternally,
  };
});
