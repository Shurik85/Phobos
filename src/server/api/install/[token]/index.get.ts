import { InstallTokenParamSchema } from '#db/repositories/installLink/types';

export default defineEventHandler(async (event) => {
  const { token } = await getValidatedRouterParams(
    event,
    validateZod(InstallTokenParamSchema, event)
  );

  const link = await Database.installLinks.getByToken(token);
  if (!link) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Install link not found',
    });
  }

  if (new Date(link.expiresAt).getTime() < Date.now()) {
    throw createError({
      statusCode: 410,
      statusMessage: 'Install link expired',
    });
  }

  const origin = getRequestURL(event).origin;
  const script = await PhobosPackage.installScript(token, origin);

  setHeader(event, 'Content-Type', 'text/x-shellscript; charset=utf-8');
  setHeader(event, 'Cache-Control', 'no-store');
  return script;
});
