open Internal_pervasives

module Specification = struct
  type t =
    | Kube of Kube_job.Specification.t
  [@@deriving yojson, show]
end

module Status = struct
  type t = [
    | `Submitted
    | `Started of float
    | `Finished of float * [ `Failed | `Succeeded | `Killed ]
    | `Error of string
  ] [@@deriving yojson,show ] 
end

type t = {
  id: string;
  specification: Specification.t [@main ];
  mutable status: Status.t [@default `Submitted];
  mutable update_errors : string list;
  mutable start_errors : string list;
}
[@@deriving yojson, show, make]

let id t = t.id
let status t = t.status
let set_status t s = t.status <- s

let start_errors t = t.start_errors
let set_start_errors t l = t.start_errors <- l

let update_errors t = t.update_errors
let set_update_errors t l = t.update_errors <- l

let fresh spec =
  let id = Uuidm.(v5 (create `V4) "coclojobs" |> to_string ~upper:false) in
  make ~id spec


let make_path id =
  (* TODO: use this in Kube_jobs uses of `~section` *)
  function
  | `Specification -> ["job"; id; "specification.json"]
  | `Status -> ["job"; id; "status.json"]
  | `Describe_output -> ["job"; id; "describe.out"]
  | `Logs_output -> ["job"; id; "logs.out"]

let save st job =
  Storage.Json.save_jsonable st
    ~path:(make_path (id job) `Specification)
    (Specification.to_yojson job.specification)
  >>= fun () ->
  Storage.Json.save_jsonable st
    ~path:(make_path (id job) `Status)
    (Status.to_yojson job.status)

let get st job_id =
  Storage.Json.get_json st
    ~path:(make_path job_id `Specification)
    ~parse:Specification.of_yojson
  >>= fun specification ->
  Storage.Json.get_json st
    ~path:(make_path job_id `Status)
    ~parse:Status.of_yojson
  >>= fun status ->
  return {id = job_id; specification; status;
          update_errors = []; start_errors = []}

let kind t =
  match t.specification with
  | Specification.Kube _ -> `Kube

let get_logs ~storage ~log t =
  match kind t with
  | `Kube ->
    let save_path = make_path t.id `Logs_output in
    Kube_job.get_logs ~storage ~log ~id:t.id ~save_path

let describe ~storage ~log t =
  match kind t with
  | `Kube ->
    let save_path = make_path t.id `Describe_output in
    Kube_job.describe ~storage ~log ~id:t.id ~save_path

let kill ~log t =
  match kind t with
  | `Kube ->
    Kube_job.kill ~log ~id:t.id

let start ~log t =
  match t.specification with
  | Specification.Kube specification ->
    Kube_job.start ~log ~id:t.id ~specification

let get_update ~log t =
  match kind t with
  | `Kube ->
    Kube_job.get_status_json ~log ~id:t.id
    >>= fun blob ->
    Kube_job.Kube_status.of_json blob
    >>= fun stat ->
    let open Kube_job.Kube_status in
    begin match stat with
    | { phase = `Pending }
    | { phase = `Unknown }
    | { phase = `Running } ->
      return `Running
    | { phase = (`Failed | `Succeeded as phase)} ->
      return phase
    end
