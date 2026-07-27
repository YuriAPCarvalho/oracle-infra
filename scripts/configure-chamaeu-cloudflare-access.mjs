/**
 * chamaeu.app — DNS (painéis) + Cloudflare Access (Zero Trust).
 *
 * Usage:
 *   CLOUDFLARE_API_TOKEN=... node scripts/configure-chamaeu-cloudflare-access.mjs
 *
 * Token needs: Zone DNS Edit, Account Access (Applications + Policies), optional Zone Settings Write (SSL strict).
 *
 * Env:
 *   CLOUDFLARE_ZONE_NAME=chamaeu.app
 *   ORIGIN_IP=129.146.161.65
 *   ALLOWED_EMAILS=yuri.apcarvalho@gmail.com,other@example.com
 */
const ZONE_NAME = process.env.CLOUDFLARE_ZONE_NAME || "chamaeu.app";
const ORIGIN_IP = process.env.ORIGIN_IP || "129.146.161.65";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN || process.env.CLOUDFLARE_TOKEN;
const ALLOWED_EMAILS = (process.env.ALLOWED_EMAILS || "yuri.apcarvalho@gmail.com")
  .split(",")
  .map((e) => e.trim())
  .filter(Boolean);

if (!TOKEN) {
  console.error("Set CLOUDFLARE_API_TOKEN or CLOUDFLARE_TOKEN");
  process.exit(1);
}

async function api(method, path, body) {
  const res = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!data.success) {
    const err = JSON.stringify(data.errors || data, null, 2);
    throw new Error(`${method} ${path} failed: ${err}`);
  }
  return data.result;
}

/** Subdomínios A → VPS (proxied). Não inclui @, api, adm (app público). */
const PANEL_DNS_HOSTS = ["uptimekuma", "dozzle", "portainer", "traefik"];

const ACCESS_APPS = [
  ["Uptime Kuma", "uptimekuma.chamaeu.app"],
  ["Dozzle", "dozzle.chamaeu.app"],
  ["Portainer", "portainer.chamaeu.app"],
  ["Traefik", "traefik.chamaeu.app"],
];

async function main() {
  const zones = await api("GET", `/zones?name=${ZONE_NAME}`);
  const zone = zones[0];
  if (!zone) throw new Error(`Zone ${ZONE_NAME} not found`);
  const accountId = zone.account?.id || process.env.CLOUDFLARE_ACCOUNT_ID;
  if (!accountId) throw new Error("Could not resolve Cloudflare account id");
  console.log("ZONE", zone.id, ZONE_NAME);
  console.log("ACCOUNT", accountId);

  try {
    const ssl = await api("PATCH", `/zones/${zone.id}/settings/ssl`, { value: "strict" });
    console.log("SSL", ssl.value);
  } catch (e) {
    console.warn("SSL skip (need Zone Settings Write):", e.message);
  }

  const existing = await api("GET", `/zones/${zone.id}/dns_records?per_page=100`);
  for (const name of PANEL_DNS_HOSTS) {
    const fqdn = `${name}.${ZONE_NAME}`;
    const found = existing.find((r) => r.type === "A" && r.name === fqdn);
    const body = { type: "A", name, content: ORIGIN_IP, ttl: 1, proxied: true };
    if (found) {
      await api("PUT", `/zones/${zone.id}/dns_records/${found.id}`, body);
      console.log("DNS update", fqdn);
    } else {
      await api("POST", `/zones/${zone.id}/dns_records`, body);
      console.log("DNS create", fqdn);
    }
  }

  const idps = await api("GET", `/accounts/${accountId}/access/identity_providers`);
  let cfIdp = idps.find((p) => p.type === "cloudflare");
  if (!cfIdp) {
    cfIdp = await api("POST", `/accounts/${accountId}/access/identity_providers`, {
      name: "Cloudflare",
      type: "cloudflare",
      config: { restrict_to_account_members: true },
    });
    console.log("Created Cloudflare IdP", cfIdp.id);
  } else {
    console.log("Cloudflare IdP", cfIdp.id);
  }

  let otpIdp = idps.find((p) => p.type === "onetimepin");
  if (!otpIdp) {
    otpIdp = await api("POST", `/accounts/${accountId}/access/identity_providers`, {
      name: "One-time PIN",
      type: "onetimepin",
      config: {},
    });
    console.log("Created OTP IdP", otpIdp.id);
  } else {
    console.log("OTP IdP", otpIdp.id);
  }

  const apps = await api("GET", `/accounts/${accountId}/access/apps?per_page=100`);
  const include = ALLOWED_EMAILS.map((email) => ({ email: { email } }));

  for (const [appName, domain] of ACCESS_APPS) {
    let app = apps.find(
      (a) => a.domain === domain || (a.self_hosted_domains || []).includes(domain),
    );
    const appBody = {
      name: `${appName} (ChamaEu)`,
      domain,
      type: "self_hosted",
      session_duration: "24h",
      auto_redirect_to_identity: false,
      allowed_idps: [cfIdp.id, otpIdp.id],
    };
    if (app) {
      app = await api("PUT", `/accounts/${accountId}/access/apps/${app.id}`, appBody);
      console.log("Access app update", domain, app.id);
    } else {
      app = await api("POST", `/accounts/${accountId}/access/apps`, appBody);
      console.log("Access app create", domain, app.id);
    }

    const policies = await api(
      "GET",
      `/accounts/${accountId}/access/apps/${app.id}/policies`,
    );
    const policyBody = {
      name: "Allow ChamaEu ops",
      decision: "allow",
      precedence: 1,
      include,
    };
    if (!policies.length) {
      await api("POST", `/accounts/${accountId}/access/apps/${app.id}/policies`, policyBody);
      console.log("Access policy create", domain);
    } else {
      const policy = policies[0];
      await api(
        "PUT",
        `/accounts/${accountId}/access/apps/${app.id}/policies/${policy.id}`,
        policyBody,
      );
      console.log("Access policy update", domain);
    }
  }

  console.log("DONE — configure VPS compose .env SERVICE_HOST and recreate stacks.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
