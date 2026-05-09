import { UserConfigSetupSchema } from '#db/repositories/userConfig/types';

export default defineSetupEventHandler(4, async ({ event }) => {
  const { host } = await readValidatedBody(
    event,
    validateZod(UserConfigSetupSchema, event)
  );

  await Database.userConfigs.updateHost(host);

  await Database.general.setSetupStep(5);
  return { success: true };
});
