# role: docker

**Що робить:** ставить Docker Engine 24+ і compose plugin v2 з офіційного Debian репо.

## Кроки

1. Додає Docker apt repository з `download.docker.com/linux/debian` (Bookworm stable channel) і їхній GPG-ключ.
2. Ставить `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`, `docker-buildx-plugin`.
3. Налаштовує `/etc/docker/daemon.json`:
   - `log-driver: json-file` з `max-size: 10m`, `max-file: 3` — гарантує, що балакучий контейнер не з'їсть 40 GB диск MS21.
   - `live-restore: true` — контейнери продовжують працювати при перезавантаженні dockerd (мінімізує downtime при apt-upgrade).
4. Додає `deploy` юзера в `docker` групу — `docker compose pull/up -d` без `sudo` під час re-deploy.
5. Робить `docker login ghcr.io` від root і від deploy-юзера. Credentials з vault: `vault_ghcr_username` + `vault_ghcr_token` (Personal Access Token з `read:packages` scope).

## Чому окрема роль (не вмонтовано у base)

- Docker репо змінюється рідше за base-пакети — можна re-run `--tags docker` коли треба оновити Engine.
- Інші проєкти у hart-стилі легко reuse'ять.

## Безпека

- **deploy ∈ docker == root-equivalent.** Юзер у docker-групі може запустити `docker run --privileged -v /:/host` і отримати весь хост. На staging — прийнятно. На production варто перейти на rootless docker або обмежити sudoers лише `docker compose` (TODO post-Phase 5.10).
- **GHCR token у no_log:** Ansible не друкує токен у stdout при run'і; його видно лише у vault'і.
