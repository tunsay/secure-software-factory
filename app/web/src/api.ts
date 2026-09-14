// Client API minimal. Aucune dépendance : fetch natif + validation légère.

export interface Item {
  id: string;
  name: string;
  quantity: number;
}

export interface Health {
  status: string;
  version: string;
  env: string;
}

const BASE = "/api";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  if (!res.ok) throw new Error(`${init?.method ?? "GET"} ${path} → ${res.status}`);
  return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
}

export const api = {
  health: () => request<Health>("/health"),
  listItems: () => request<Item[]>("/items"),
  createItem: (name: string, quantity: number) =>
    request<Item>("/items", { method: "POST", body: JSON.stringify({ name, quantity }) }),
  deleteItem: (id: string) => request<void>(`/items/${encodeURIComponent(id)}`, { method: "DELETE" }),
};
