/**
 * chamaeu.app — WAF / edge hardening (geo BR + bot settings).
 *
 * Usage:
 *   CLOUDFLARE_API_TOKEN=... node scripts/configure-chamaeu-cloudflare-waf.mjs
 *
 * Token needs: Zone WAF Write (Custom rules) + Zone Settings Edit (optional bots/security).
 *
 * Strategy:
 * - Panels: Block if country != BR (defense in depth on top of Access)
 * - Public apps: Managed Challenge if country != BR, except webhook/health paths
 *   (Mercado Pago and similar providers often call from outside BR)
 */
const ZONE_NAME = process.env.CLOUDFLARE_ZONE_NAME || "chamaeu.app";
const TOKEN = process.env.CLOUDFLARE_API_TOKEN || process.env.CLOUDFLARE_TOKEN;

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
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json();
  if (!data.success) {
    throw new Error(`${method} ${path}: ${JSON.stringify(data.errors || data, null, 2)}`);
  }
  return data.result;
}

const PANEL_HOSTS = [
  "grafana.chamaeu.app",
  "portainer.chamaeu.app",
  "dozzle.chamaeu.app",
  "uptimekuma.chamaeu.app",
  "traefik.chamaeu.app",
];

const PUBLIC_HOSTS = ["chamaeu.app", "www.chamaeu.app", "api.chamaeu.app", "adm.chamaeu.app"];

function hostExpr(hosts) {
  return `http.host in {${hosts.map((h) => `"${h}"`).join(" ")}}`;
}

const RULES = [
  {
    ref: "chamaeu_panels_block_non_br",
    description: "ChamaEu panels — block non-BR",
    expression: `(${hostExpr(PANEL_HOSTS)} and ip.geoip.country ne "BR")`,
    action: "block",
  },
  {
    ref: "chamaeu_public_challenge_non_br",
    description: "ChamaEu public — challenge non-BR (allow webhooks/health)",
    expression: `(${hostExpr(PUBLIC_HOSTS)} and ip.geoip.country ne "BR" and not starts_with(http.request.uri.path, "/pagamento/webhook") and http.request.uri.path ne "/health" and not starts_with(http.request.uri.path, "/api/health"))`,
    action: "managed_challenge",
  },
];

async function upsertCustomFirewallRules(zoneId) {
  const phase = "http_request_firewall_custom";
  let entry;
  try {
    entry = await api("GET", `/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`);
  } catch (e) {
    // No entrypoint yet — create via PUT with rules
    entry = null;
  }

  const existingRules = entry?.rules || [];
  const byRef = new Map(existingRules.filter((r) => r.ref).map((r) => [r.ref, r]));

  const nextRules = [...existingRules.filter((r) => !RULES.some((n) => n.ref === r.ref))];
  for (const rule of RULES) {
    const prev = byRef.get(rule.ref);
    nextRules.push({
      ...(prev?.id ? { id: prev.id } : {}),
      ref: rule.ref,
      description: rule.description,
      expression: rule.expression,
      action: rule.action,
      enabled: true,
    });
  }

  if (entry?.id) {
    await api("PUT", `/zones/${zoneId}/rulesets/${entry.id}`, {
      rules: nextRules,
    });
    console.log("Updated custom WAF ruleset", entry.id, `(${nextRules.length} rules)`);
  } else {
    const created = await api("PUT", `/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`, {
      rules: RULES.map((rule) => ({
        ref: rule.ref,
        description: rule.description,
        expression: rule.expression,
        action: rule.action,
        enabled: true,
      })),
    });
    console.log("Created custom WAF entrypoint", created.id);
  }
}

async function patchSetting(zoneId, setting, value) {
  try {
    const r = await api("PATCH", `/zones/${zoneId}/settings/${setting}`, { value });
    console.log("Setting", setting, "=", r.value);
  } catch (e) {
    console.warn(`Setting ${setting} skip:`, e.message.split("\n")[0]);
  }
}

async function main() {
  const zones = await api("GET", `/zones?name=${ZONE_NAME}`);
  const zone = zones[0];
  if (!zone) throw new Error(`Zone ${ZONE_NAME} not found`);
  console.log("ZONE", zone.id, ZONE_NAME);

  await upsertCustomFirewallRules(zone.id);

  // Edge hardening (best-effort; plan features vary)
  await patchSetting(zone.id, "security_level", "high");
  await patchSetting(zone.id, "browser_check", "on");
  await patchSetting(zone.id, "email_obfuscation", "on");
  await patchSetting(zone.id, "server_side_exclude", "on");
  await patchSetting(zone.id, "hotlink_protection", "off");
  await patchSetting(zone.id, "challenge_ttl", 1800);
  await patchSetting(zone.id, "bot_fight_mode", "on");

  console.log("DONE — panels blocked outside BR; public apps challenged outside BR (webhooks/health skipped).");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
