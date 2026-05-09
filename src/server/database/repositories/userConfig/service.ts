import { eq, sql } from 'drizzle-orm';
import { userConfig } from './schema';
import type { UserConfigUpdateType } from './types';
import type { DBType } from '#db/sqlite';

function createPreparedStatement(db: DBType) {
  return {
    get: db.query.userConfig
      .findFirst({ where: eq(userConfig.id, sql.placeholder('interface')) })
      .prepare(),
  };
}

export class UserConfigService {
  #db: DBType;
  #statements: ReturnType<typeof createPreparedStatement>;

  constructor(db: DBType) {
    this.#db = db;
    this.#statements = createPreparedStatement(db);
  }

  async get() {
    const userConfig = await this.#statements.get.execute({ interface: 'wg0' });

    if (!userConfig) {
      throw new Error('User config not found');
    }

    return userConfig;
  }

  // TODO: wrap ipv6 host in square brackets

  updateHost(host: string) {
    return this.#db
      .update(userConfig)
      .set({ host })
      .where(eq(userConfig.id, 'wg0'))
      .execute();
  }

  update(data: Partial<UserConfigUpdateType>) {
    return this.#db
      .update(userConfig)
      .set(data)
      .where(eq(userConfig.id, 'wg0'))
      .execute();
  }
}
