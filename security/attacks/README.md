# security/attacks — démonstrations d'attaque

Manifestes volontairement malveillants, pour prouver ce que la défense bloque. À n'exécuter
que sur le cluster kind local, qui est jetable (`make infra-up` le reconstruit).

## hostpath-escape : évasion par montage du nœud

Le même pod est soumis à deux namespaces. Terraform a posé les Pod Security Standards
`restricted` sur `ssf` (module `namespace`), et n'a rien posé sur `default`.

```bash
make attack-escape
```

Résultat attendu :

- **`default`** (non durci) : le pod démarre. Il lit `/host/etc/shadow` du nœud — soit la prise
  de contrôle de la machine hôte depuis un simple droit de création de pod.
- **`ssf`** (durci par Terraform) : l'API server **refuse** le pod à l'admission. Aucun conteneur
  n'est créé. Le message liste chaque règle violée.

C'est la valeur de Terraform, démontrée : la différence entre les deux namespaces n'est pas dans
l'application, elle est dans trois labels que Terraform a posés sur l'un et pas sur l'autre.
