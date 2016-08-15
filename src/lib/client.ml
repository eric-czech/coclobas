open Internal_pervasives

type t = {
  base_url: string [@main];
} [@@deriving yojson, show, make]

let wrap_io d =
  Deferred_result.wrap_deferred d
    ~on_exn:(fun e -> `Client (`IO_exn e))

let wrap_parsing d =
  Deferred_result.wrap_deferred d
    ~on_exn:(fun e -> `Client (`Json_exn e))

let do_get uri =
  wrap_io Lwt.(fun () ->
      Cohttp_lwt_unix.Client.get uri
      >>= fun (resp, body) ->
      Cohttp_lwt_body.to_string body
      >>= fun b ->
      return (resp, b)
    )

let uri_of_ids base_url path ids =
  Uri.with_query
    (Uri.with_path (Uri.of_string base_url) path)
    ["id", ids]

let response_is_ok ~uri ~meth resp =
  begin match Cohttp.Response.status resp with
  | `OK -> return ()
  | other -> fail (`Client (`Response (meth, uri, resp)))
  end

let submit_kube_job {base_url} spec =
  let uri =
    Uri.with_path (Uri.of_string base_url) "job/submit" in
  let body =
    Cohttp_lwt_body.of_string
      (Kube_job.Specification.to_yojson spec |> Yojson.Safe.pretty_to_string) 
  in
  wrap_io (fun () -> Cohttp_lwt_unix.Client.post uri ~body)
  >>= fun (resp, body) ->
  response_is_ok  resp ~meth:`Post ~uri

let get_kube_job_statuses {base_url} ids =
  let uri = uri_of_ids base_url "job/status" ids in
  do_get uri
  >>= fun (resp, body) ->
  begin match Cohttp.Response.status resp with
  | `OK ->
    wrap_parsing (fun () -> Lwt.return (Yojson.Safe.from_string body))
    >>= fun json ->
    begin match json with
    | `List l ->
      Deferred_list.while_sequential l ~f:(function
        | `Assoc ["id", `String id; "status", stjson] ->
          wrap_parsing Lwt.(fun () ->
              match Kube_job.Status.of_yojson stjson with
              | `Ok s -> return (id, s)
              | `Error e -> fail (Failure e)
            )
        | other -> fail (`Client (`Json_parsing (uri, other)))
        )
    | other -> fail (`Client (`Json_parsing (uri, other)))
    end
  | other -> fail (`Client (`Response (`Post, uri, resp)))
  end

let kill_kube_jobs {base_url} ids =
  let uri = uri_of_ids base_url "job/status" ids in
  do_get uri
  >>= fun (resp, body) ->
  response_is_ok resp ~meth:`Get ~uri
  

module Error = struct
  let to_string =
    function
    | `IO_exn e -> sprintf "Client.IO: %s" (Printexc.to_string e)
    | `Json_exn e -> sprintf "Client.Json-parsing: %s" (Printexc.to_string e)
    | `Json_parsing (uri, json) ->
      sprintf "Client.Json-parsing: URI: %s content: %s"
        (Uri.to_string uri)
        (Yojson.Safe.pretty_to_string json)
    | `Response (meth, uri, resp) ->
      sprintf "Client.Response: URI: %s, Meth: %s, Resp: %s"
        (Uri.to_string uri)
        begin match meth with
        | `Post -> "POST"
        | `Get -> "GET"
        end
        (Cohttp.Response.sexp_of_t resp |> Sexplib.Sexp.to_string_hum)
end
