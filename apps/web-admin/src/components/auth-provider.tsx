"use client";

import { createContext, useContext, type ReactNode } from "react";

import type { components } from "@/api/generated/identity";

export type Me = components["schemas"]["Me"];

const AuthContext = createContext<Me | null>(null);

/** Holds the server-resolved user (`/auth/me`) for client components (header user menu). */
export function AuthProvider({
  user,
  children,
}: {
  user: Me;
  children: ReactNode;
}) {
  return <AuthContext.Provider value={user}>{children}</AuthContext.Provider>;
}

export function useAuth(): Me {
  const user = useContext(AuthContext);
  if (!user) throw new Error("useAuth must be used within an AuthProvider");
  return user;
}
