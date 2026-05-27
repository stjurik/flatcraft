# role: firewall

**Що робить:** конфігурує UFW (Uncomplicated Firewall) у режимі default-deny incoming + explicit allow для SSH і Cloudflare-proxied HTTP/HTTPS.

## Стратегія

```
Internet → Cloudflare (DDoS + WAF) → UFW allow only-from-CF → Caddy (TLS) → web/api containers
```

Cloudflare виступає єдиним legitimate джерелом HTTP-трафіку на наш origin. UFW режеть прямі підключення в обхід CF, а origin-IP ми не публікуємо у DNS (всі записи proxied).

## Правила

| Port | Proto | Allow from         | Призначення           |
| ---- | ----- | ------------------ | --------------------- |
| 22   | tcp   | `ssh_allowed_ips`  | SSH (key-only auth)   |
| 80   | tcp   | Cloudflare IPv4+v6 | HTTP → HTTPS redirect |
| 443  | tcp   | Cloudflare IPv4+v6 | HTTPS                 |
| 443  | udp   | Cloudflare IPv4+v6 | HTTP/3 (QUIC)         |

Все інше → DROP.

## Cloudflare IP ranges

Зберігаємо у файлах `cloudflare_ipv4.txt` / `cloudflare_ipv6.txt`. CF змінює список ~1-2 рази/рік.

**Як оновити:**

```bash
curl -s https://www.cloudflare.com/ips-v4/ > infra/ansible/roles/firewall/files/cloudflare_ipv4.txt
curl -s https://www.cloudflare.com/ips-v6/ > infra/ansible/roles/firewall/files/cloudflare_ipv6.txt
# (звичайно cf повертає бінарний/без коментарів — додай header вручну)
ansible-playbook site.yml --tags firewall -i inventory.staging.ini
```

## SSH allowlist

`ssh_allowed_ips` у `group_vars/all.yml`. На staging — `0.0.0.0/0` для зручності розробки. На production обов'язково звузити до конкретних IP розробників/CI runners — інакше fail2ban лишається єдиним бар'єром перед brute-force.

## Зауваження

- `community.general.ufw` ідемпотентний — re-running після зміни CF IPs додає нові allow і не видаляє старі. Для повного rebuild: `ufw --force reset && ansible-playbook --tags firewall`.
- UFW логи у `/var/log/ufw.log` (rate-limited `low` рівнем).
