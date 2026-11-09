// Supabase Edge Function "send-confirmation".
// Sends a short, neutral confirmation e-mail to the customer for two website forms:
//   * hot tub requests      (site_requests.kind = 'Hot tub request')
//   * withdrawal notices    (site_requests.kind starts with 'Withdrawal notice')
// It is called by a Database Webhook on INSERT into public.site_requests (see the setup steps).
// Secrets (Edge Functions -> Secrets): RESEND_API_KEY, WEBHOOK_SECRET.
// The e-mail holds no text typed by the visitor except the order number of a withdrawal,
// so the form cannot be misused to send someone else a message through our domain.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") ?? "";
const FROM = "Forest Kings Tub <info@forestkings.com>";
const REPLY_TO = "info@forestkings.com";

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const clean = (s: unknown, max: number) => String(s ?? "").replace(/[^A-Za-z0-9\-\/ .]/g, "").trim().slice(0, max);

Deno.serve(async (req) => {
  if (!WEBHOOK_SECRET || req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  const { type, record } = await req.json().catch(() => ({}));
  if (type !== "INSERT" || !record) return new Response("ignored");

  const kind = String(record.kind ?? "");
  const d = record.data ?? {};
  const to = String(d.email ?? "").trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to) || to.length > 200) return new Response("no valid e-mail");

  let subject: string;
  let lines: string[];
  if (kind === "Hot tub request") {
    const ref = clean(d.order?.order_id, 40);
    subject = "We received your hot tub request";
    lines = [
      "Hello,",
      `thank you for your hot tub request${ref ? ` (reference ${ref})` : ""}. We have received it and will reply by e-mail within 24 hours with the final price, delivery cost and date.`,
      "If you would like to add anything, simply reply to this e-mail.",
      "Kind regards,\nForest Kings Tub\ninfo@forestkings.com · forestkings.com",
    ];
  } else if (kind.startsWith("Withdrawal notice")) {
    const order = clean(d.order_no, 40);
    const date = clean(d.date_of_notice, 20);
    subject = "We received your withdrawal notice";
    lines = [
      "Hello,",
      `we confirm that we received your notice of withdrawal${order ? ` for order ${order}` : ""}${date ? `, sent on ${date}` : ""}.`,
      "We will contact you by e-mail about the next steps (return of the goods and refund).",
      "If you have any questions, simply reply to this e-mail.",
      "Kind regards,\nForest Kings Tub\ninfo@forestkings.com · forestkings.com",
    ];
  } else {
    return new Response("ignored");
  }

  const text = lines.join("\n\n");
  const html = lines.map((l) => `<p>${esc(l).replace(/\n/g, "<br>")}</p>`).join("");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [to], reply_to: REPLY_TO, subject, text, html }),
  });
  if (!res.ok) {
    console.error("Resend error", res.status, await res.text());
    return new Response("send failed", { status: 502 });
  }
  return new Response("sent");
});
