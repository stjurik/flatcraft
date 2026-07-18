/**
 * /terms/en — Terms of Service (EN, draft). Companion to /terms (UA).
 */
import Link from "next/link";

import { localeAlternates } from "../../../i18n/hreflang";

export const metadata = {
  title: "Terms of Service · hart.crimea.ua",
  description: "Non-profit social project; free use within a monthly quota; drawings are advisory.",
  alternates: localeAlternates("en", "/terms", "/terms/en"),
};

interface Section {
  readonly id: string;
  readonly title: string;
  readonly body: string;
}

const SECTIONS: ReadonlyArray<Section> = [
  {
    id: "about",
    title: "1. About the service",
    body:
      "hart.crimea.ua is a non-profit social platform for parametric configuration of standard sheet-metal " +
      "parts and free download of drawings (DXF + PDF + STEP). The source code is open under the MIT licence " +
      "on GitHub.",
  },
  {
    id: "usage",
    title: "2. Usage terms",
    body:
      "Sign-up is not required at this stage. The export quota is up to 10 exports per month free of charge " +
      "(further use can be unlocked by a voluntary donation to Ukrainian Armed Forces funds; the donation goes " +
      "to the fund, not to the platform). The quota may change — see the interface for the current number.",
  },
  {
    id: "acceptable-use",
    title: "3. Acceptable use",
    body:
      "The platform is for constructive design of standard parts. Prohibited: (a) creating or forwarding " +
      "automated infrastructure that deliberately overloads the server; (b) circumventing technical limits " +
      "(export quota, rate limit); (c) using the platform to design items that violate Ukrainian law. We " +
      "reserve the right to block IPs on abuse.",
  },
  {
    id: "drawings-liability",
    title: "4. Liability for drawings",
    body:
      "Generated drawings are an advisory starting point for a laser-cutting and bending order, not a " +
      "finished engineering document. Before manufacturing, a human who understands material, bending, and " +
      "the specifics of the particular machine must verify the drawing. We are NOT liable for defects, " +
      "injuries, financial or other losses caused by a mismatch between generated parameters and the real " +
      "production process. Use at your own risk.",
  },
  {
    id: "donations",
    title: "5. Donations go directly to funds",
    body:
      "The platform does NOT accept any funds. «Support Armed Forces» links go directly to Monobank Banka and " +
      "UNITED24. We only proxy the link; all reporting is on the fund's side. A donation creates no legal " +
      "obligation between you and the platform.",
  },
  {
    id: "ip",
    title: "6. Intellectual property",
    body:
      "Platform code — MIT (github.com/stjurik/flatcraft). Design, page copy, and logo remain our property. " +
      "Drawings you generated from your parameters are yours (unrestricted use, including commercial).",
  },
  {
    id: "changes",
    title: "7. Changes to the terms",
    body:
      "We may update these terms (add pages, adjust limits, change our approach to paid features if/when they " +
      "appear). Material changes will be announced in the Discord community and the GitHub repository. " +
      "Continued use after a change means acceptance of the new terms.",
  },
  {
    id: "uptime",
    title: "8. Best-effort uptime, no SLA",
    body:
      "This is a social project on a single server. We try to keep the platform available, but do not " +
      "guarantee response time, uptime, data integrity, or long-term durability of stored artefacts. Use " +
      "local CAD software if your process requires an SLA.",
  },
];

export default function TermsPageEn() {
  return (
    <div className="bg-bg mx-auto flex w-full max-w-3xl flex-col gap-8 px-4 py-10 md:py-16">
      <div
        data-testid="terms-draft-banner"
        className="border-warning bg-warning-surface rounded-lg border-2 p-4"
      >
        <p className="text-warning-foreground text-sm font-semibold">
          Draft. Not legal advice; the final version follows a lawyer review (Roadmap 5.4).
        </p>
      </div>

      <header data-testid="terms-hero" className="flex flex-col gap-3">
        <h1 className="text-fg text-3xl font-bold md:text-4xl">Terms of Service</h1>
        <p className="text-fg-muted">
          Minimum formalities, maximum alignment with the platform's real state. Українська:{" "}
          <Link href="/terms" className="underline">
            /terms
          </Link>
          .
        </p>
      </header>

      <div className="flex flex-col gap-6">
        {SECTIONS.map((section) => (
          <section
            key={section.id}
            id={section.id}
            data-testid={`terms-section-${section.id}`}
            className="flex flex-col gap-2"
          >
            <h2 className="text-fg text-xl font-semibold">{section.title}</h2>
            <p className="text-fg-muted leading-relaxed">{section.body}</p>
          </section>
        ))}
      </div>

      <footer className="border-border border-t pt-6">
        <p className="text-fg-subtle text-sm">
          Last updated: 2026-07-12. Privacy Policy —{" "}
          <Link href="/privacy/en" className="underline">
            /privacy/en
          </Link>
          .
        </p>
      </footer>
    </div>
  );
}
