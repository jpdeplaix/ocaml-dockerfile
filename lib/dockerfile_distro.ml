(*
 * Copyright (c) 2016 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

(** Distro selection for various OPAM combinations *)
open Dockerfile
open Dockerfile_opam

type t = [ 
  | `Alpine of [ `V3_3 ]
  | `CentOS of [ `V6 | `V7 ]
  | `Debian of [ `Stable | `Testing | `Unstable ]
  | `Fedora of [ `V21 | `V22 | `V23 ]
  | `OracleLinux of [ `V7 ]
  | `Ubuntu of [ `V12_04 | `V14_04 | `V15_04 | `V15_10 | `V16_04 ]
] with sexp
 
let distros = [ (`Ubuntu `V12_04); (`Ubuntu `V14_04); (`Ubuntu `V15_10); (`Ubuntu `V16_04);
                (`Debian `Stable); (`Debian `Testing); (`Debian `Unstable);
                (`Fedora `V22); (`Fedora `V23);
                (`CentOS `V6); (`CentOS `V7);
                (`OracleLinux `V7);
                (`Alpine `V3_3) ]
let ocaml_versions = [ "4.00.1"; "4.01.0"; "4.02.3"; "4.03.0+trunk" ]
let opam_versions = [ "1.2.2" ]

(* The distro-supplied version of OCaml *)
let builtin_ocaml_of_distro = function
  |`Debian `Stable -> Some "4.01.0"
  |`Debian `Testing -> Some "4.02.3"
  |`Debian `Unstable -> Some "4.02.3"
  |`Ubuntu `V12_04 -> Some "3.12.1"
  |`Ubuntu `V14_04 -> Some "4.01.0"
  |`Ubuntu `V15_04 -> Some "4.01.0"
  |`Ubuntu `V15_10 -> Some "4.01.0"
  |`Ubuntu `V16_04 -> Some "4.02.3"
  |`Alpine `V3_3 -> Some "4.02.3"
  |`Fedora `V21 -> None (* TODO check *)
  |`Fedora `V22 -> Some "4.02.0"
  |`Fedora `V23 -> Some "4.02.2"
  |`CentOS `V6 | `CentOS `V7 -> None (* TODO check *)
  |`OracleLinux `V7 -> None

(* The Docker tag for this distro *)
let tag_of_distro = function
  |`Ubuntu `V12_04 -> "ubuntu-12.04"
  |`Ubuntu `V14_04 -> "ubuntu-14.04"
  |`Ubuntu `V15_04 -> "ubuntu-15.04"
  |`Ubuntu `V15_10 -> "ubuntu-15.10"
  |`Ubuntu `V16_04 -> "ubuntu-16.04"
  |`Debian `Stable -> "debian-stable"
  |`Debian `Unstable -> "debian-unstable"
  |`Debian `Testing -> "debian-testing"
  |`CentOS `V6 -> "centos-6"
  |`CentOS `V7 -> "centos-7"
  |`Fedora `V21 -> "fedora-21"
  |`Fedora `V22 -> "fedora-22"
  |`Fedora `V23 -> "fedora-23"
  |`OracleLinux `V7 -> "oraclelinux-7"
  |`Alpine `V3_3 -> "alpine-3.3"

let opam_tag_of_distro distro ocaml_version =
  (* Docker rewrites + to _ in tags *)
  let ocaml_version = Str.(global_replace (regexp_string "+") "_" ocaml_version) in
  Printf.sprintf "%s_ocaml-%s"
    (tag_of_distro distro) ocaml_version

(* Build the OPAM distributions from the OCaml base *)
let add_comment ?compiler_version tag =
  comment "OPAM for %s with %s" tag
  (match compiler_version with
      | None -> "system OCaml compiler"
      | Some v -> "local switch of OCaml " ^ v)

(* Apt based Dockerfile *)
let apt_opam ?compiler_version distro tag =
    add_comment ?compiler_version tag @@
    header "ocaml/ocaml" tag @@
    Linux.Apt.install "aspcud" @@
    install_opam_from_source () @@
    Linux.Apt.add_user ~sudo:true "opam" @@
    Linux.Git.init () @@
    onbuild (run "sudo apt-get update && sudo apt-get -y upgrade") @@
    opam_init ?compiler_version () @@
    run_as_opam "opam install -y depext travis-opam" @@
    entrypoint_exec ["opam";"config";"exec";"--"]

(* Yum RPM based Dockerfile *)
let yum_opam ?compiler_version distro tag =
    add_comment ?compiler_version tag @@
    header "ocaml/ocaml" tag @@
    Linux.RPM.dev_packages ~extra:"which tar" () @@
    install_opam_from_source ~prefix:"/usr" () @@
    run "sed -i.bak '/LC_TIME LC_ALL LANGUAGE/aDefaults    env_keep += \"OPAMYES OPAMJOBS OPAMVERBOSE\"' /etc/sudoers" @@
    Linux.RPM.add_user ~sudo:true "opam" @@
    Linux.Git.init () @@
    opam_init ?compiler_version () @@
    run_as_opam "opam install -y depext travis-opam" @@
    entrypoint_exec ["opam";"config";"exec";"--"]

(* Apk (alpine) Dockerfile *)
let apk_opam ?compiler_version tag =
    add_comment ?compiler_version tag @@
    header "ocaml/ocaml" tag @@
    Linux.Apk.install "opam aspcud rsync" @@
    Linux.Apk.add_user ~sudo:true "opam" @@
    Linux.Git.init () @@
    opam_init ?compiler_version () @@
    run_as_opam "opam install -y depext travis-opam" @@
    entrypoint_exec ["opam";"config";"exec";"--"]

(* Construct a Dockerfile for a distro/ocaml combo, using the
   system OCaml if possible, or a custom OPAM switch otherwise *)
let to_dockerfile ~ocaml_version ~distro =
  let tag = tag_of_distro distro in
  let compiler_version =
    match builtin_ocaml_of_distro distro with
    | Some v when v = ocaml_version -> None (* use builtin *)
    | None | Some _ (* when v <> ocaml_version *) -> Some ocaml_version
  in
  match distro with
  | `Ubuntu _ | `Debian _ -> apt_opam ?compiler_version distro tag
  | `CentOS _ | `Fedora _ | `OracleLinux _ -> yum_opam ?compiler_version distro tag
  | `Alpine _ -> apk_opam ?compiler_version tag

(* Build up the matrix of Dockerfiles *)
let dockerfile_matrix =
  List.map (fun opam_version ->
    List.map (fun ocaml_version ->
      List.map (fun distro ->
        distro,
        ocaml_version,
        to_dockerfile ~ocaml_version ~distro
      ) distros
    ) ocaml_versions
  ) opam_versions |> List.flatten |> List.flatten

let map_tag fn =
  List.map (fun (distro,ocaml_version,_) ->
   fn ~distro ~ocaml_version) dockerfile_matrix

let map ?(org="ocaml/opam") fn =
  map_tag (fun ~distro ~ocaml_version ->
   let tag = opam_tag_of_distro distro ocaml_version in
   let base = from org ~tag in
   fn ~distro ~ocaml_version base)

open Printf

let run_command fmt =
  ksprintf (fun cmd ->
    eprintf "Exec: %s\n%!" cmd;
    match Sys.command cmd with
    | 0 -> ()
    | _ -> raise (Failure cmd)
  ) fmt

let write_to_file ~crunch file dfile =
  let dfile = if crunch then Dockerfile.crunch dfile else dfile in
  eprintf "Open: %s\n%!" file;
  let fout = open_out file in
  output_string fout (string_of_t dfile);
  close_out fout

let generate_dockerfiles ?(crunch=true) d output_dir =
  List.iter (fun (name, docker) ->
    printf "Generating: %s/%s/Dockerfile\n" output_dir name;
    run_command "mkdir -p %s/%s" output_dir name;
    write_to_file ~crunch (output_dir ^ "/" ^ name ^ "/Dockerfile") docker
  ) d

let generate_dockerfiles_in_git_branches ?(crunch=true) d output_dir =
  List.iter (fun (name, docker) ->
    printf "Switching to branch %s in %s\n" name output_dir;
    run_command "git -C \"%s\" checkout -q -B %s master" output_dir name;
    let file = output_dir ^ "/Dockerfile" in
    write_to_file ~crunch file docker;
    run_command "git -C \"%s\" add Dockerfile" output_dir;
    run_command "git -C \"%s\" commit -q -m \"update %s Dockerfile\" -a" output_dir name
  ) d;
  run_command "git -C \"%s\" checkout -q master" output_dir

