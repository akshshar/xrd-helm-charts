{{/*
Expand the name of the chart.
*/}}
{{- define "xrd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "xrd.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "xrd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "xrd.labels" -}}
helm.sh/chart: {{ include "xrd.chart" . }}
{{ include "xrd.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "xrd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "xrd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "xrd.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "xrd.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Default repository to use for each platform
*/}}
{{- define "xrd.defaultRepository" -}}
{{- if eq .Values.platform "ControlPlane" -}}
localhost:5000/xrd-control-plane
{{- else if eq .Values.platform "vRouter" -}}
localhost:5000/xrd-vrouter
{{- else -}}
{{ fail "Invalid XRd platform: %s" | printf .Values.platform }}
{{- end }}
{{- end }}

{{/*
Image repository to use
*/}}
{{- define "xrd.repository" -}}
{{- if .Values.image.repository }}
{{- .Values.image.repository }}
{{- else }}
{{- include "xrd.defaultRepository" . }}
{{- end }}
{{- end }}

{{/*
Container resources including defaults if applicable
*/}}
{{- define "xrd.resources" -}}
{{- /*
XRd Control Plane has no default resources
XRd vRouter has a default of 5Gi memory, 3Gi of 1Gi hugepages (8Gi in total).
*/}}
{{- $default := dict }}
{{- $resources := default dict .Values.resources }}
{{- if eq .Values.platform "ControlPlane" }}
{{- else if eq .Values.platform "vRouter" }}
{{- /*
Iterate through the limits and requests and check if any hugepage
or memory configuration is specified.
If so, don't include that in the default limits.
*/}}
{{- $limits := get $resources "limits" }}
{{- $requests := get $resources "requests" }}
{{- $hasHugepage := false }}
{{- $hasMemory := false }}
{{- range tuple $limits $requests }}
{{- if kindIs "map" . }}
{{- range $k := keys . }}
{{- if hasPrefix "hugepages" $k }}
{{- $hasHugepage = true }}
{{- end }}
{{- if eq $k "memory" }}
{{- $hasMemory = true }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- /*
Construct the default limits based on the contents of any resource config
*/}}
{{- $defaultLimits := dict }}
{{- if not $hasHugepage }}
{{- $_ := set $defaultLimits "hugepages-1Gi" "3Gi" }}
{{- end }}
{{- if not $hasMemory }}
{{- $_ := set $defaultLimits "memory" "5Gi" }}
{{- end }}
{{- $_ := set $default "limits" $defaultLimits }}
{{- else }}
{{ fail "Invalid XRd platform: %s" | printf .Values.platform }}
{{- end }}
{{- /*
Output the merged resources if there's any configuration or defaults.
*/}}
{{- if or $resources $default -}}
resources:
{{ merge $resources $default | toYaml | indent 2 }}
{{- end }}
{{- end }}

{{- define "xrd.hugepages" -}}
{{- /*
XRd Control Plane has no default resources
XRd vRouter has a default of 3Gi of 1Gi hugepages.
*/}}
{{- $default := dict }}
{{- $resources := default dict .Values.resources }}
{{- if eq .Values.platform "ControlPlane" }}
{{- else if eq .Values.platform "vRouter" }}
{{- /*
Iterate through the limits and requests and check if any hugepage
or memory configuration is specified.
If so, don't include that in the default limits.
*/}}
{{- $limits := get $resources "limits" }}
{{- $requests := get $resources "requests" }}
{{- $hugepage := "" }}
{{- range $m := tuple $limits $requests }}
{{- if kindIs "map" $m }}
{{- range $k := keys $m }}
{{- if hasPrefix "hugepages" $k }}
{{- $hugepage = get $m $k }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $hugepage -}}
{{ $hugepage }}
{{- else -}}
3Gi
{{- end }}
{{- end }}
{{- end }}

{{/*
Storage helpers
*/}}
{{- define "xrd.storageEnabled" -}}
{{- $enabled := true }}
{{- with .Values.storage }}
{{- if .disabled -}}
{{ $enabled = false }}
{{- end }}
{{- end }}
{{- if $enabled -}}
{{- /* Value doesn't matter, non-empty evaluates to true */ -}}
1
{{- end -}}
{{- end -}}

{{- define "xrd.storagePath" -}}
{{- $config := "" -}}
{{- with .Values.storage -}}
{{ $config = .pathOverride }}
{{- end -}}
{{ default (include "xrd.fullname" . | printf "\"/var/run/pv-%s\"") $config }}
{{- end -}}

{{- define "xrd.storageSize" -}}
{{- $config := "" -}}
{{- with .Values.storage -}}
{{ $config = .size }}
{{- end -}}
{{ default "5Gi" $config }}
{{- end -}}

{{- define "xrd.storagePersistName" -}}
{{ include "xrd.fullname" . }}-persist
{{- end -}}

{{- define "xrd.storagePersistClaimName" -}}
{{ include "xrd.fullname" . }}-persist-claim
{{- end -}}

{{- /* Misc helpers */ -}}
{{- define "xrd.toMiB" -}}
{{- /*
Convert a k8s resource specification of Mi or Gi into MiB for XR env vars.
*/ -}}
{{- if hasSuffix "Mi" . -}}
{{ trimSuffix "Mi" . }}
{{- else if hasSuffix "Gi" . -}}
{{ . | trimSuffix "Gi" | int | mul 1024 | toString }}
{{- end -}}
{{- end -}}
