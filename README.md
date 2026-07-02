# Sonda de contexto — pentest autorizado Posit Connect

Contenido Plumber (R) para confirmar alcance de IMDS/ECS/K8s desde el sandbox de ejecución.

## Estructura del repo
- `plumber.R`   — la sonda (entrypoint)
- `manifest.json` — manifiesto de Connect para git deploy (appmode: api, platform 4.3.2)

## Despliegue vía git (en Connect)
1. Publicar → New Content → Import from Git
2. URL del repo: `https://github.com/<tu-cuenta>/<repo>.git`
3. Branch: `main` · subdirectory: `/` (raíz, donde está manifest.json)
4. Connect clona, lee manifest.json, restaura paquetes y arranca el API

## Explotación
Tras el deploy, llamar al endpoint del contenido:
```
GET https://cn.demo.copernicus.aws.corp.com/content/<GUID>/probe
```
La respuesta (texto plano) contiene, por secciones: identidad del pod, IMDSv2
(token+creds), IMDSv1, ECS task role, service-account de K8s, variables de
entorno y montajes.

## Notas
- Si `manifest.json` da checksum mismatch tras editar plumber.R:
  `md5sum plumber.R` y actualizar el campo `files["plumber.R"].checksum`.
- Si el restore de paquetes falla, `curl` suele venir en la imagen base; se
  puede reemplazar por `system2("curl", ...)` como fallback (ver rama alternativa).
