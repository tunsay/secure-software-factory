import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api, type Health, type Item } from "./api";

export function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [name, setName] = useState("");
  const [quantity, setQuantity] = useState(1);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const [h, list] = await Promise.all([api.health(), api.listItems()]);
      setHealth(h);
      setItems(list);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "erreur inconnue");
    }
  }, []);

  useEffect(() => {
    let active = true;
    Promise.all([api.health(), api.listItems()])
      .then(([h, list]) => {
        if (!active) return;
        setHealth(h);
        setItems(list);
        setError(null);
      })
      .catch((e: unknown) => {
        if (active) setError(e instanceof Error ? e.message : "erreur inconnue");
      });
    return () => {
      active = false;
    };
  }, []);

  async function onSubmit(ev: FormEvent) {
    ev.preventDefault();
    if (!name.trim()) return;
    try {
      await api.createItem(name.trim(), quantity);
      setName("");
      setQuantity(1);
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "erreur inconnue");
    }
  }

  async function onDelete(id: string) {
    try {
      await api.deleteItem(id);
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "erreur inconnue");
    }
  }

  return (
    <main>
      <header>
        <h1>Secure Software Factory</h1>
        <p className="status">
          API :{" "}
          {health ? (
            <span className="ok">
              {health.status} · v{health.version} · {health.env}
            </span>
          ) : (
            <span className="ko">indisponible</span>
          )}
        </p>
      </header>

      {error && <p className="error">{error}</p>}

      <form onSubmit={onSubmit}>
        <input
          id="item-name"
          placeholder="nom"
          value={name}
          maxLength={80}
          onChange={(e) => setName(e.target.value)}
        />
        <input
          id="item-qty"
          type="number"
          min={0}
          max={10000}
          value={quantity}
          onChange={(e) => setQuantity(Number(e.target.value))}
        />
        <button type="submit">Ajouter</button>
      </form>

      <ul>
        {items.map((it) => (
          <li key={it.id}>
            <span>
              {it.name} × {it.quantity}
            </span>
            <button type="button" onClick={() => void onDelete(it.id)} aria-label={`supprimer ${it.name}`}>
              ×
            </button>
          </li>
        ))}
        {items.length === 0 && <li className="empty">Aucun item — le stockage est en mémoire, c'est voulu.</li>}
      </ul>
    </main>
  );
}
