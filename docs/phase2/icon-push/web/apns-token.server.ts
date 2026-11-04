/**
 * APNs provider token for the Icon push job (Honoured V1.2 M2-07).
 *
 * The database sends the Icon card pushes itself (pg_net speaks the HTTP/2
 * APNs requires) but cannot sign ES256. This mints the token APNs expects from
 * the team's .p8 key: header { alg: ES256, kid: APNS_KEY_ID }, claims
 * { iss: APNS_TEAM_ID, iat }. A token is valid for an hour and may be renewed
 * at most every 20 minutes; the database asks for a new one about every 40.
 *
 * Nothing here logs key material or the token.
 */

export type ApnsEnvironment = "sandbox" | "production";

export interface ApnsSettings {
  teamId: string;
  keyId: string;
  /** Bundle ids the key may push to (APNS_TOPIC, comma-separated). */
  topics: string[];
  /** Gateways it may use (APNS_ENVIRONMENT: sandbox, production or both; unset means both). */
  environments: ApnsEnvironment[];
}

const SECRET_NAMES = ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_PRIVATE_KEY", "APNS_TOPIC", "APNS_ENVIRONMENT"];

function env(name: string): string | undefined {
  const value = process.env[name];
  return value && value.trim() ? value.trim() : undefined;
}

function list(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

/** Null until every required secret is set. */
export function apnsSettings(): ApnsSettings | null {
  const teamId = env("APNS_TEAM_ID");
  const keyId = env("APNS_KEY_ID");
  const topics = list(env("APNS_TOPIC"));
  if (!teamId || !keyId || !env("APNS_PRIVATE_KEY") || topics.length === 0) return null;
  const named = list(env("APNS_ENVIRONMENT")?.toLowerCase());
  const environments: ApnsEnvironment[] =
    named.length === 0 || named.includes("both")
      ? ["sandbox", "production"]
      : named.filter((e): e is ApnsEnvironment => e === "sandbox" || e === "production");
  return { teamId, keyId, topics, environments };
}

/** Which secrets are set; never their values. */
export function apnsSecretsPresent(): Record<string, boolean> {
  return Object.fromEntries(SECRET_NAMES.map((name) => [name, Boolean(env(name))]));
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedKey: { keyId: string; key: CryptoKey } | null = null;

async function signingKey(keyId: string): Promise<CryptoKey> {
  if (cachedKey?.keyId === keyId) return cachedKey.key;
  // The .p8 is a PKCS#8 PEM. Environment plumbing often turns its newlines
  // into literal backslash-n, so both forms are accepted.
  const pem = (env("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  if (!body) throw new Error("APNS_PRIVATE_KEY is not a PEM private key");
  const raw = atob(body);
  const der = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) der[i] = raw.charCodeAt(i);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  cachedKey = { keyId, key };
  return key;
}

/** An ES256 provider token issued at `issuedAt` (Unix seconds). */
export async function mintApnsProviderToken(settings: ApnsSettings, issuedAt: number): Promise<string> {
  const encoder = new TextEncoder();
  const header = base64Url(encoder.encode(JSON.stringify({ alg: "ES256", kid: settings.keyId })));
  const claims = base64Url(encoder.encode(JSON.stringify({ iss: settings.teamId, iat: issuedAt })));
  // WebCrypto returns the raw r||s form JOSE expects — no DER re-encoding.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await signingKey(settings.keyId),
    encoder.encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
}
