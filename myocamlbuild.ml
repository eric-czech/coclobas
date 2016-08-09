open Printf
open Solvuu_build.Std

let project_name = "coclobas"
let version = "master"

let findlib_deps = [
  "nonstd";
  "sosa";
]

let lib : Project.item =
  Project.lib project_name
    ~findlib_deps
    ~dir:"src/lib"
    ~pack_name:project_name
    ~pkg:project_name

let app : Project.item =
  Project.app project_name
  ~file:"src/app/main.ml"
  ~internal_deps:[lib]

let ocamlinit_postfix = [
  sprintf "open %s" (String.capitalize project_name);
]

let () =
  Project.basic1 ~project_name ~version [lib;app]
    ~ocamlinit_postfix
