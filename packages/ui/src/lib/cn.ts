import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** Tailwind-aware class merger: `cn("p-2", isActive && "bg-primary")` */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
