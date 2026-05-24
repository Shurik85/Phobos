import { writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import debug from 'debug';

import type { InterfaceType } from '#db/repositories/interface/types';
import type { ObfuscatorPresetType } from '#db/repositories/obfuscatorPreset/types';
import { OBFUSCATOR_PORT_MIN } from '#db/repositories/obfuscatorPreset/types';

const OBFUSCATOR_DEBUG = debug('Obfuscator');

const CONFIG_PATH = '/run/wg-obfuscator.conf';
const SERVICE_DIR = '/run/service/wg-obfuscator';
const DEFAULT_KEY_LENGTH = 16;

function isPrivateIp(ip: string): boolean {
  return /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|127\.|169\.254\.)/.test(ip);
}

export function generateObfuscatorKey(length: number = DEFAULT_KEY_LENGTH): string {
  if (length < 1 || length > 255) {
    throw new Error('Key length must be 1..255');
  }
  return randomBytes(length * 2)
    .toString('base64')
    .replace(/[+/=]/g, '')
    .slice(0, length);
}

class ObfuscatorService {
  buildSection(preset: ObfuscatorPresetType, wgPort: number): string {
    return [
      `[preset-${preset.id}]`,
      'source-if = 0.0.0.0',
      `source-lport = ${preset.extPort}`,
      `target = 127.0.0.1:${wgPort}`,
      `key = ${preset.key}`,
      `masking = ${preset.masking}`,
      'verbose = INFO',
      `idle-timeout = ${preset.idle}`,
      `max-dummy = ${preset.dummy}`,
      '',
    ].join('\n');
  }

  buildConfigFile(presets: ObfuscatorPresetType[], wgPort: number): string {
    return presets.map((p) => this.buildSection(p, wgPort)).join('\n');
  }

  async writeConfig(presets: ObfuscatorPresetType[], wgPort: number): Promise<void> {
    const content = this.buildConfigFile(presets, wgPort);
    await writeFile(CONFIG_PATH, content, { mode: 0o600 });
    OBFUSCATOR_DEBUG(`wrote ${presets.length} instances to ${CONFIG_PATH}`);
  }

  async restart(): Promise<void> {
    if (!existsSync(SERVICE_DIR)) {
      OBFUSCATOR_DEBUG('s6 service not available, skipping restart');
      return;
    }
    await exec(`/command/s6-svc -r ${SERVICE_DIR}`);
    OBFUSCATOR_DEBUG('s6-svc -r issued');
  }

  async applyAll(): Promise<void> {
    const presets = await Database.obfuscatorPresets.list();
    if (presets.length === 0) {
      OBFUSCATOR_DEBUG('no presets configured, skipping apply');
      return;
    }
    const iface = await Database.interfaces.get();
    await this.writeConfig(presets, iface.port);
    await this.restart();
  }

  async detectPublicIpV4(): Promise<string> {
    const envIp = process.env.WG_HOST;
    if (envIp && /^\d+\.\d+\.\d+\.\d+$/.test(envIp)) return envIp;

    const route = await exec('ip route');
    const iface = route.match(/^default.+dev\s+(\S+)/m)?.[1];
    if (iface) {
      const out = await exec(`ip -4 addr show dev ${iface} scope global`);
      const ip = out.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/)?.[1];
      if (ip && !isPrivateIp(ip)) return ip;
    }

    const pub = await exec('curl -sf --max-time 5 https://api.ipify.org').catch(() => '');
    if (pub && /^\d+\.\d+\.\d+\.\d+$/.test(pub.trim())) return pub.trim();

    throw new Error('Cannot detect public IPv4. Set WG_HOST env variable.');
  }

  async detectPublicIpV6(): Promise<string | null> {
    try {
      const route = await exec('ip route');
      const iface = route.match(/^default.+dev\s+(\S+)/m)?.[1];
      if (!iface) return null;

      const out = await exec(`ip -6 addr show dev ${iface} scope global`);
      const ipv6 = out
        .match(/inet6\s+([0-9a-f:]+)/gi)
        ?.map((l) => l.replace(/^inet6\s+/i, ''))
        .find((addr) => !/^f[cd]/i.test(addr));
      return ipv6 ?? null;
    } catch {
      return null;
    }
  }

  buildClientObfConf(preset: ObfuscatorPresetType, iface: InterfaceType): string {
    return [
      '[instance]',
      'source-if = 127.0.0.1',
      `source-lport = ${preset.clientWgLocalPort}`,
      `target = ${iface.serverPublicIpV4}:${preset.extPort}`,
      `key = ${preset.key}`,
      `masking = ${preset.masking}`,
      'verbose = INFO',
      `idle-timeout = ${preset.idle}`,
      `max-dummy = ${preset.dummy}`,
      '',
    ].join('\n');
  }

  async Startup(): Promise<void> {
    OBFUSCATOR_DEBUG('Starting Obfuscator...');

    const iface = await Database.interfaces.get();

    if (!iface.serverPublicIpV4) {
      const ipv4 = await this.detectPublicIpV4().catch(() => '');
      const ipv6 = iface.serverPublicIpV6 ?? (await this.detectPublicIpV6());
      if (ipv4 || ipv6 !== iface.serverPublicIpV6) {
        await Database.interfaces.update({
          serverPublicIpV4: ipv4,
          serverPublicIpV6: ipv6,
        });
      }
    }

    await Database.obfuscatorPresets.ensureDefault({
      extPort: OBFUSCATOR_PORT_MIN,
      key: generateObfuscatorKey(),
      masking: 'STUN',
      idle: 300,
      dummy: 10,
      clientWgLocalPort: 13255,
    });

    await this.applyAll();

    OBFUSCATOR_DEBUG('Obfuscator started');
  }
}

export const Obfuscator = new ObfuscatorService();

export default Obfuscator;
