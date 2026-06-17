"use client";

/**
 * R3FErrorBoundary (Hotfix 2.9.f, ADR-026) — backstop для R3F-сцен.
 *
 * Render-gate у viewport'ах (apps/web) не рендерить `<Canvas>` при невалідних
 * параметрах, тож у штатному редагуванні цей boundary НЕ спрацьовує. Він —
 * остання лінія оборони: будь-який неочікуваний throw усередині R3F-піддерева
 * (нова геометрія, WebGL-контекст, edge-case у залежності) ловиться тут і
 * показує дружній fallback замість white-screen «Application error».
 *
 * Класовий компонент — у React (вкл. 19) error boundary можливий лише через
 * `getDerivedStateFromError` + `componentDidCatch` (хуків-аналога немає). Ловить
 * synchronous render-throw (саме наш кейс через `build*ShapeCommands` у useMemo).
 */
import { Component, type ErrorInfo, type ReactNode } from "react";

const IS_DEV = process.env.NODE_ENV !== "production";

interface R3FErrorBoundaryProps {
  readonly children: ReactNode;
  /** Опційний колбек для телеметрії/логів (за замовчуванням console.error). */
  readonly onError?: (error: Error, info: ErrorInfo) => void;
}

interface R3FErrorBoundaryState {
  readonly hasError: boolean;
  readonly error?: Error | undefined;
}

interface R3FErrorFallbackProps {
  readonly error?: Error | undefined;
  readonly onRetry: () => void;
}

/** Pure fallback-UI (експортується окремо — простіше тестувати без mount'у). */
export function R3FErrorFallback({ error, onRetry }: R3FErrorFallbackProps) {
  return (
    <div
      role="alert"
      data-testid="r3f-error-fallback"
      className="bg-warning-subtle text-fg flex h-full w-full flex-col items-center justify-center gap-3 p-6 text-center"
    >
      <span aria-hidden className="text-3xl">
        ⚠️
      </span>
      <p className="text-sm font-medium">3D-прев'ю тимчасово недоступне</p>
      <button
        type="button"
        onClick={onRetry}
        data-testid="r3f-error-retry"
        className="border-border bg-surface hover:bg-surface-hover rounded-md border px-3 py-1.5 text-sm"
      >
        Спробувати знову
      </button>
      {IS_DEV && error ? (
        <details className="text-fg-muted max-w-full text-left text-xs">
          <summary className="cursor-pointer">Деталі (dev)</summary>
          <pre className="overflow-auto whitespace-pre-wrap">{error.stack ?? error.message}</pre>
        </details>
      ) : null}
    </div>
  );
}

export class R3FErrorBoundary extends Component<R3FErrorBoundaryProps, R3FErrorBoundaryState> {
  constructor(props: R3FErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false };
    this.handleRetry = this.handleRetry.bind(this);
  }

  static getDerivedStateFromError(error: Error): R3FErrorBoundaryState {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, info: ErrorInfo): void {
    if (this.props.onError) {
      this.props.onError(error, info);
    } else {
      // Без PII — лише повідомлення/стек помилки геометрії (CLAUDE.md §8).
      console.error("[R3FErrorBoundary] caught render error:", error);
    }
  }

  handleRetry(): void {
    this.setState({ hasError: false, error: undefined });
  }

  override render(): ReactNode {
    if (this.state.hasError) {
      return <R3FErrorFallback error={this.state.error} onRetry={this.handleRetry} />;
    }
    return this.props.children;
  }
}
