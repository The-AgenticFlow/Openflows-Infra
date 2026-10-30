{{- define "manager.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "manager.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "manager.selectorLabels" -}}
app.kubernetes.io/name: openflows-manager
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* The image reference: the digest wins, the tag is a fallback. */}}
{{- define "manager.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ required "image.tag or image.digest is required" .Values.image.tag }}
{{- end -}}
{{- end }}

{{/* Environment shared by the serve and setup containers. */}}
{{- define "manager.env" -}}
- name: OPENFLOWS_DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.managerSecret }}
      key: databaseUrl
- name: OPENFLOWS_PUBLIC_URL
  value: {{ required "publicUrl is required" .Values.publicUrl | quote }}
{{- range $key, $value := .Values.config }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}

{{- define "manager.securityContext" -}}
runAsNonRoot: true
runAsUser: {{ .Values.runAs }}
runAsGroup: {{ .Values.runAs }}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end }}
