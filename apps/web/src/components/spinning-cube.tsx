"use client";

import dynamic from "next/dynamic";

// R3F вантажить three.js + WebGL — це suspendable на SSR (canvas/window не існує).
// dynamic({ ssr: false }) гарантує, що компонент рендериться лише на клієнті.
const Scene = dynamic(() => import("./scene").then((m) => m.Scene), {
  ssr: false,
  loading: () => (
    <div
      className="flex h-full w-full items-center justify-center text-sm text-zinc-500"
      data-testid="cube-loading"
    >
      Завантаження 3D…
    </div>
  ),
});

export function SpinningCube() {
  return <Scene />;
}
