async function verifyBrowserIdentity(page, approval, timeout = 30_000) {
  await page.waitForFunction(() => Boolean(window.Xrm?.Utility?.getGlobalContext()?.userSettings?.userId),
    null, { timeout });
  const identity = await page.evaluate(async ({ origin, organizationId, expectedUpn, expectedActorId }) => {
    const globalContext = window.Xrm.Utility.getGlobalContext();
    const normalize = value => String(value || "").replace(/[{}]/g, "").toLowerCase();
    const whoResponse = await fetch(`${origin}/api/data/v9.2/WhoAmI`, { credentials: "same-origin" });
    if (!whoResponse.ok) return { error: "UAT_WHOAMI_FAILED" };
    const who = await whoResponse.json();
    const userResponse = await fetch(
      `${origin}/api/data/v9.2/systemusers(${who.UserId})?$select=internalemailaddress,isdisabled,accessmode`,
      { credentials: "same-origin" });
    if (!userResponse.ok) return { error: "UAT_BSO_IDENTITY_READ_FAILED" };
    const user = await userResponse.json();
    const roles = globalContext.userSettings.roles.getAll().map(role => role.name);
    return {
      userId: normalize(who.UserId),
      target: globalContext.getClientUrl().replace(/\/$/, "") === origin &&
        normalize(who.OrganizationId) === normalize(organizationId),
      account: normalize(who.UserId) === normalize(globalContext.userSettings.userId) &&
        (!expectedActorId || normalize(who.UserId) === normalize(expectedActorId)) &&
        String(user.internalemailaddress || "").toLowerCase() === expectedUpn.toLowerCase() &&
        user.isdisabled === false && user.accessmode === 0,
      bsoRole: roles.includes("BSO-RS Support - BSO"),
      elevated: roles.some(role => /^System (Administrator|Customizer)$/i.test(role))
    };
  }, approval);
  if (identity.error) throw new Error(identity.error);
  if (!identity.target) throw new Error("UAT_ORGANIZATION_MISMATCH");
  if (!identity.account) throw new Error("UAT_BSO_IDENTITY_MISMATCH");
  if (approval.identityScope === "BSO_ONLY") {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      approval.expectedActorId || "")) {
      throw new Error("UAT_EXPECTED_BSO_ACTOR_REQUIRED");
    }
    if (identity.elevated) throw new Error("UAT_ELEVATED_IDENTITY_NOT_BSO_ACCEPTANCE");
    if (!identity.bsoRole) throw new Error("UAT_REQUIRED_BSO_ROLE_MISSING");
  }
  return identity;
}

module.exports = { verifyBrowserIdentity };
