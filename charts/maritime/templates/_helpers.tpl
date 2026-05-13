{{/*
DATABASE_URL composé depuis le Secret CNPG `pg-data-app`. CNPG génère ce
Secret automatiquement quand le Cluster est ready, avec username/password
aléatoires + clé `uri` = postgres://USER:PASS@HOST:5432/DB toute prête.
*/}}
{{- define "maritime.dbUrlEnv" -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: pg-data-app
      key: uri
{{- end }}

{{/*
RABBITMQ_URL composé depuis le Secret `rmq-default-user` généré par
RabbitMQ Cluster Operator. Le secret expose username/password/host/port
séparément. On construit l'URL via 4 env vars + une 5ème qui les
concatène — pattern K8s "value composition via env var references".
*/}}
{{- define "maritime.rmqEnv" -}}
- name: RMQ_USER
  valueFrom:
    secretKeyRef: { name: rmq-default-user, key: username }
- name: RMQ_PASS
  valueFrom:
    secretKeyRef: { name: rmq-default-user, key: password }
- name: RMQ_HOST
  # Hostname court : le DNS search path inclut .maritime.svc.cluster.local
  # et le FQDN complet déclenche un bug CoreDNS k3s observé. Court = OK.
  value: rmq
- name: RMQ_PORT
  value: "5672"
- name: RABBITMQ_URL
  value: "amqp://$(RMQ_USER):$(RMQ_PASS)@$(RMQ_HOST):$(RMQ_PORT)"
{{- end }}
