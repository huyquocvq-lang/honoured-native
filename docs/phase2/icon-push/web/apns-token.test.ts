import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { apnsSecretsPresent, apnsSettings, mintApnsProviderToken } from "@/lib/apns-token.server";

const NAMES = ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_PRIVATE_KEY", "APNS_TOPIC", "APNS_ENVIRONMENT"];
let saved: Record<string, string | undefined> = {};

function fromBase64Url(value: string): Uint8Array {
  return new Uint8Array(Buffer.from(value.replace(/-/g, "+").replace(/_/g, "/"), "base64"));
}

async function keyPair() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----`;
  return { publicKey: pair.publicKey, pem };
}

beforeEach(() => {
  saved = Object.fromEntries(NAMES.map((name) => [name, process.env[name]]));
  for (const name of NAMES) delete process.env[name];
});

afterEach(() => {
  for (const name of NAMES) {
    if (saved[name] === undefined) delete process.env[name];
    else process.env[name] = saved[name];
  }
});

describe("APNs settings", () => {
  it("needs the team, key, private key and at least one topic", () => {
    expect(apnsSettings()).toBeNull();
    process.env.APNS_TEAM_ID = "TEAM123456";
    process.env.APNS_KEY_ID = "KEY1234567";
    process.env.APNS_PRIVATE_KEY = "pem";
    expect(apnsSettings()).toBeNull();
    process.env.APNS_TOPIC = " com.example.app , com.example.other ";
    expect(apnsSettings()).toEqual({
      teamId: "TEAM123456",
      keyId: "KEY1234567",
      topics: ["com.example.app", "com.example.other"],
      environments: ["sandbox", "production"],
    });
    expect(apnsSecretsPresent()).toEqual({
      APNS_TEAM_ID: true,
      APNS_KEY_ID: true,
      APNS_PRIVATE_KEY: true,
      APNS_TOPIC: true,
      APNS_ENVIRONMENT: false,
    });
  });

  it("reads the allowed gateways", () => {
    Object.assign(process.env, { APNS_TEAM_ID: "T", APNS_KEY_ID: "K", APNS_PRIVATE_KEY: "pem", APNS_TOPIC: "com.example.app" });
    process.env.APNS_ENVIRONMENT = "Sandbox";
    expect(apnsSettings()?.environments).toEqual(["sandbox"]);
    process.env.APNS_ENVIRONMENT = "sandbox, production";
    expect(apnsSettings()?.environments).toEqual(["sandbox", "production"]);
    process.env.APNS_ENVIRONMENT = "both";
    expect(apnsSettings()?.environments).toEqual(["sandbox", "production"]);
  });
});

describe("APNs provider token", () => {
  it("is an ES256 JWT the team's public key verifies, from a PEM with literal \\n", async () => {
    const { publicKey, pem } = await keyPair();
    Object.assign(process.env, {
      APNS_TEAM_ID: "TEAM123456",
      APNS_KEY_ID: "KEYSIGN001",
      APNS_TOPIC: "com.example.app",
      APNS_PRIVATE_KEY: pem.replace(/\n/g, "\\n"),
    });
    const token = await mintApnsProviderToken(apnsSettings()!, 1791280800);
    const [header, claims, signature] = token.split(".");
    const decode = (part: string) => JSON.parse(new TextDecoder().decode(fromBase64Url(part)));
    expect(decode(header)).toEqual({ alg: "ES256", kid: "KEYSIGN001" });
    expect(decode(claims)).toEqual({ iss: "TEAM123456", iat: 1791280800 });
    const raw = fromBase64Url(signature);
    expect(raw.length).toBe(64);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      raw,
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });
});
