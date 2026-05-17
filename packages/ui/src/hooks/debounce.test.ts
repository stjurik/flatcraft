import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createDebouncer } from "./debounce.js";

describe("createDebouncer", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("firing'ає onFire після delayMs з останнім значенням", () => {
    const onFire = vi.fn();
    const d = createDebouncer<number>(100, onFire);
    d.schedule(1);
    vi.advanceTimersByTime(99);
    expect(onFire).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(onFire).toHaveBeenCalledTimes(1);
    expect(onFire).toHaveBeenCalledWith(1);
  });

  it("rapid schedule — лише останнє значення доходить", () => {
    const onFire = vi.fn();
    const d = createDebouncer<number>(100, onFire);
    d.schedule(1);
    d.schedule(2);
    d.schedule(3);
    vi.advanceTimersByTime(99);
    d.schedule(4);
    vi.advanceTimersByTime(100);
    expect(onFire).toHaveBeenCalledTimes(1);
    expect(onFire).toHaveBeenCalledWith(4);
  });

  it("cancel() скасовує заплановане спрацювання", () => {
    const onFire = vi.fn();
    const d = createDebouncer<number>(100, onFire);
    d.schedule(1);
    d.cancel();
    vi.advanceTimersByTime(500);
    expect(onFire).not.toHaveBeenCalled();
  });

  it("кидає на від'ємному delayMs", () => {
    expect(() => createDebouncer(-1, () => {})).toThrow(/delayMs/);
  });

  it("delayMs=0 — fire після поточного тіка, не sync", () => {
    const onFire = vi.fn();
    const d = createDebouncer<number>(0, onFire);
    d.schedule(42);
    expect(onFire).not.toHaveBeenCalled();
    vi.advanceTimersByTime(0);
    expect(onFire).toHaveBeenCalledWith(42);
  });

  it("повторне schedule після fire — нова сесія", () => {
    const onFire = vi.fn();
    const d = createDebouncer<number>(100, onFire);
    d.schedule(1);
    vi.advanceTimersByTime(100);
    d.schedule(2);
    vi.advanceTimersByTime(100);
    expect(onFire).toHaveBeenCalledTimes(2);
    expect(onFire).toHaveBeenNthCalledWith(1, 1);
    expect(onFire).toHaveBeenNthCalledWith(2, 2);
  });
});
