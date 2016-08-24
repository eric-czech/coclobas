
open Internal_pervasives

let to_string =
  let exn = Printexc.to_string in
  function
  | `Shell (cmd, ex) ->
    sprintf "Shell-command failed: %S" cmd
  | `Storage e -> Storage.Error.to_string e
  | `IO (`Write_file_exn (path, e)) ->
    sprintf "Writing file %S: %s" path (exn e)
  | `IO (`Read_file_exn (path, e)) ->
    sprintf "Reading file %S: %s" path (exn e)
  | `Job e -> Kube_job.Error.to_string e
  | `Start_server (`Exn e) ->
    sprintf "Starting Cohttp server: %s" (exn e)