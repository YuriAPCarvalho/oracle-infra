/**
 * Configure marca7.tech DNS + Access via Cloudflare API.
 * Usage: CLOUDFLARE_API_TOKEN=... node scripts/configure-marca7-tech-cloudflare.mjs
 */
const ACCOUNT_ID = process.env.CLOUDFLARE_ACCOUNT_ID || "20f799331aa75509ff16ec3b68aa2064";
const ZONE_NAME = process.env.CLOUDFLARE_ZONE_NAME || "marca7.tech";
const ORIGIN_IP = process.env.ORIGIN_IP || "179.197.238.11";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
if (!TOKEN) {
  console.error("Set CLOUDFLARE_API_TOKEN");
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

const HOSTS = [
  "gestoragro",
  "gestoragro-api",
  "s3",
  "minio",
  "uptimekuma",
  "dozzle",
  "portainer",
  "traefik",
];

const ACCESS_APPS = [
  ["MinIO Console", "minio.marca7.tech"],
  ["Uptime Kuma", "uptimekuma.marca7.tech"],
  ["Dozzle", "dozzle.marca7.tech"],
  ["Portainer", "portainer.marca7.tech"],
  ["Traefik", "traefik.marca7.tech"],
];

async function main() {
  const zones = await api("GET", `/zones?name=${ZONE_NAME}`);
  const zone = zones[0];
  if (!zone) throw new Error(`Zone ${ZONE_NAME} not found`);
  console.log("ZONE", zone.id);

  try {
    const ssl = await api("PATCH", `/zones/${zone.id}/settings/ssl`, { value: "strict" });
    console.log("SSL", ssl.value);
  } catch (e) {
    console.warn("SSL skip (need Zone Settings Write):", e.message);
  }

  const existing = await api("GET", `/zones/${zone.id}/dns_records?per_page=100`);
  for (const name of HOSTS) {
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

  const idps = await api("GET", `/accounts/${ACCOUNT_ID}/access/identity_providers`);
  let cfIdp = idps.find((p) => p.type === "cloudflare");
  if (!cfIdp) {
    cfIdp = await api("POST", `/accounts/${ACCOUNT_ID}/access/identity_providers`, {
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
    otpIdp = await api("POST", `/accounts/${ACCOUNT_ID}/access/identity_providers`, {
      name: "One-time PIN",
      type: "onetimepin",
      config: {},
    });
    console.log("Created OTP IdP", otpIdp.id);
  } else {
    console.log("OTP IdP", otpIdp.id);
  }

  const apps = await api("GET", `/accounts/${ACCOUNT_ID}/access/apps?per_page=100`);
  for (const [appName, domain] of ACCESS_APPS) {
    let app = apps.find(
      (a) => a.domain === domain || (a.self_hosted_domains || []).includes(domain)
    );
    const appBody = {
      name: appName,
      domain,
      type: "self_hosted",
      session_duration: "24h",
      auto_redirect_to_identity: false,
      allowed_idps: [cfIdp.id, otpIdp.id],
    };
    if (app) {
      app = await api("PUT", `/accounts/${ACCOUNT_ID}/access/apps/${app.id}`, appBody);
      console.log("Access app update", domain, app.id);
    } else {
      app = await api("POST", `/accounts/${ACCOUNT_ID}/access/apps`, appBody);
      console.log("Access app create", domain, app.id);
    }

    const policies = await api(
      "GET",
      `/accounts/${ACCOUNT_ID}/access/apps/${app.id}/policies`
    );
    if (!policies.length) {
      await api("POST", `/accounts/${ACCOUNT_ID}/access/apps/${app.id}/policies`, {
        name: "Allow Marca7 admins",
        decision: "allow",
        precedence: 1,
        include: [
          { email: { email: "yuri.apcarvalho@gmail.com" } },
          { email: { email: "monica@marca7.com.br" } },
        ],
      });
      console.log("Access policy create", domain);
    } else {
      console.log("Access policies exist", domain, policies.length);
    }

    // keep local list fresh for next iterations
    if (!apps.find((a) => a.id === app.id)) apps.push(app);
  }

  console.log("DONE");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
