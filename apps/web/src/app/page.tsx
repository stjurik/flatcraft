import Link from "next/link";

import { SpinningCube } from "../components/spinning-cube";

export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-5xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <h1 className="text-4xl font-bold tracking-tight text-zinc-50" data-testid="hero-title">
          flatcraft
        </h1>
        <p className="text-lg text-zinc-400">
          Параметричний CAD для виробів з листового металу. DXF · PDF · STEP — безкоштовно, без
          CAD-навичок.
        </p>
        <p className="text-sm text-zinc-500" data-testid="phase-marker">
          Phase 0.5 hello-world · react-three-fiber
        </p>
        <Link
          href="/templates"
          data-testid="cta-templates"
          className="mt-2 inline-flex w-fit items-center gap-2 rounded-lg bg-emerald-700 px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-emerald-600"
        >
          Переглянути шаблони →
        </Link>
      </header>

      <section
        className="rounded-2xl border border-zinc-800 bg-zinc-900/50 p-2"
        data-testid="viewport-frame"
      >
        <div className="aspect-video w-full overflow-hidden rounded-xl">
          <SpinningCube />
        </div>
      </section>
    </main>
  );
}
