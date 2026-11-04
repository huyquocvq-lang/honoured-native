import { createFileRoute } from "@tanstack/react-router";

/**
 * Mints the APNs provider token for the Icon push job (V1.2 M2-07) and stores
 * it in public.apns_provider_tokens with the allowed bundle ids and gateways.
 * The database (public.icon_push_request_token) calls this with the
 * icon_push_cron_secret from Vault; the token is never returned.
 */
export const Route = createFileRoute("/api/internal/apns-token")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data: authorised, error } = await supabaseAdmin.rpc("icon_push_secret_ok", {
          p_secret: request.headers.get("x-cron-secret") ?? "",
        });
        if (error) return Response.json({ ok: false, error: "secret check failed" }, { status: 500 });
        if (authorised !== true) return new Response("Unauthorized", { status: 401 });

        const { apnsSecretsPresent, apnsSettings, mintApnsProviderToken } = await import("@/lib/apns-token.server");
        const settings = apnsSettings();
        if (!settings) {
          return Response.json(
            { ok: false, error: "APNs is not configured", secrets: apnsSecretsPresent() },
            { status: 500 },
          );
        }

        const issuedAt = Math.floor(Date.now() / 1000);
        let token: string;
        try {
          token = await mintApnsProviderToken(settings, issuedAt);
        } catch (err) {
          console.error("apns-token: could not sign", err instanceof Error ? err.name : "error");
          return Response.json({ ok: false, error: "could not sign" }, { status: 500 });
        }

        const { error: saveError } = await supabaseAdmin.from("apns_provider_tokens").upsert({
          key_id: settings.keyId,
          token,
          issued_at: new Date(issuedAt * 1000).toISOString(),
          team_id: settings.teamId,
          topics: settings.topics,
          environments: settings.environments,
          rejected_at: null,
        });
        if (saveError) {
          console.error("apns-token: could not store", saveError.message);
          return Response.json({ ok: false, error: "could not store" }, { status: 500 });
        }
        return Response.json({ ok: true, issuedAt, topics: settings.topics, environments: settings.environments });
      },
    },
  },
});
