# Let's configure some redis instances SUSE style

follow pillar.example

## Required salt master config:

```
file_roots:
  base:
    - {{ salt_base_dir }}/salt
    - {{ formulas_base_dir }}/radieschen/salt
```

## License

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)

