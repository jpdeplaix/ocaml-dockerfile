(*
 * Copyright (c) 2015 Anil Madhavapeddy <anil@recoil.org>
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

(** OPAM-specific Dockerfile rules *)

open Dockerfile
module Linux = Dockerfile_linux
module Windows = Dockerfile_windows
module D = Dockerfile_distro
module OV = Ocaml_version

let personality ?arch distro =
  match arch with
  | None -> None
  | Some arch -> D.personality (D.os_family_of_distro distro) arch

let run_as_opam fmt = Linux.run_as_user "opam" fmt

let install_opam_from_source ?(add_default_link=true) ?(prefix= "/usr/local") ?(enable_0install_solver=false) ~branch () =
  run "git clone -b %s git://github.com/ocaml/opam /tmp/opam" branch @@
  (if enable_0install_solver then
     run "git clone git://github.com/ocaml-opam/opam-0install-solver /tmp/opam/opam-0install-solver" @@
     run "git clone git://github.com/0install/0install /tmp/opam/0install"
   else
     empty
  ) @@
  Linux.run_sh
       "cd /tmp/opam && make cold && mkdir -p %s/bin && cp /tmp/opam/opam %s/bin/opam-%s && chmod a+x %s/bin/opam-%s && rm -rf /tmp/opam" prefix prefix branch prefix branch @@
  if add_default_link then
    run "ln %s/bin/opam-%s %s/bin/opam" prefix branch prefix
  else empty

(* Can't satisfy the typechecker... *)
let install_opam_from_source_cygwin ?(add_default_link=true) ?(prefix= "/usr/local") ?(enable_0install_solver=false) ~branch () =
  let open Dockerfile_windows.Cygwin in
  run_sh "git clone -b %s git://github.com/ocaml/opam /tmp/opam" branch @@
  (if enable_0install_solver then
     run_sh "git clone git://github.com/ocaml-opam/opam-0install-solver /tmp/opam/opam-0install-solver" @@
     run_sh "git clone git://github.com/0install/0install /tmp/opam/0install"
   else
     empty
  )
  @@ run_sh
       "cd /tmp/opam && make cold && mkdir -p %s/bin && cp /tmp/opam/opam %s/bin/opam-%s && chmod a+x %s/bin/opam-%s && rm -rf /tmp/opam" prefix prefix branch prefix branch
  @@ if add_default_link then
       run_sh "ln %s/bin/opam-%s %s/bin/opam" prefix branch prefix
     else empty

let install_bubblewrap_from_source ?(prefix="/usr/local") () =
  let rel = "0.4.1" in
  let file = Fmt.strf "bubblewrap-%s.tar.xz" rel in
  let url = Fmt.strf "https://github.com/projectatomic/bubblewrap/releases/download/v%s/bubblewrap-%s.tar.xz" rel rel in
  run "curl -fOL %s" url @@
  run "tar xf %s" file @@
  run "cd bubblewrap-%s && ./configure --prefix=%s && make && sudo make install" rel prefix @@
  run "rm -rf %s bubblewrap-%s" file rel

let install_bubblewrap_wrappers =
  (* Enable bubblewrap *)
  run "echo 'wrap-build-commands: []' > ~/.opamrc-nosandbox" @@
  run "echo 'wrap-install-commands: []' >> ~/.opamrc-nosandbox" @@
  run "echo 'wrap-remove-commands: []' >> ~/.opamrc-nosandbox" @@
  run "echo 'required-tools: []' >> ~/.opamrc-nosandbox" @@
  run "echo '#!/bin/sh' > /home/opam/opam-sandbox-disable" @@
  run "echo 'cp ~/.opamrc-nosandbox ~/.opamrc' >> /home/opam/opam-sandbox-disable" @@
  run "echo 'echo --- opam sandboxing disabled' >> /home/opam/opam-sandbox-disable" @@
  run "chmod a+x /home/opam/opam-sandbox-disable" @@
  run "sudo mv /home/opam/opam-sandbox-disable /usr/bin/opam-sandbox-disable" @@
  (* Disable bubblewrap *)
  run "echo 'wrap-build-commands: [\"%%{hooks}%%/sandbox.sh\" \"build\"]' > ~/.opamrc-sandbox" @@
  run "echo 'wrap-install-commands: [\"%%{hooks}%%/sandbox.sh\" \"install\"]' >> ~/.opamrc-sandbox" @@
  run "echo 'wrap-remove-commands: [\"%%{hooks}%%/sandbox.sh\" \"remove\"]' >> ~/.opamrc-sandbox" @@
  run "echo '#!/bin/sh' > /home/opam/opam-sandbox-enable" @@
  run "echo 'cp ~/.opamrc-sandbox ~/.opamrc' >> /home/opam/opam-sandbox-enable" @@
  run "echo 'echo --- opam sandboxing enabled' >> /home/opam/opam-sandbox-enable" @@
  run "chmod a+x /home/opam/opam-sandbox-enable" @@
  run "sudo mv /home/opam/opam-sandbox-enable /usr/bin/opam-sandbox-enable"

let header ?arch ?maintainer ?img ?tag d =
  let platform =
    match arch with
    | Some `I386 -> Some "386"
    | Some `Aarch32 -> Some "arm"
    | _ -> None in
  let shell =
    match personality ?arch d with
    | Some pers -> shell [pers; "/bin/bash"; "-c"]
    | None -> empty in
  let maintainer =
    match maintainer with
    | Some t -> Dockerfile.maintainer "%s" t
    | None -> empty in
  let escape =
    match D.os_family_of_distro d with
    | `Windows | `Cygwin -> parser_directive (`Escape '`')
    | _ -> empty in
  let img, tag =
    let dimg, dtag = D.base_distro_tag ?arch d in
    let value default = function None -> default | Some str -> str in
    value dimg img, value dtag tag
  in
  escape @@
  comment "Autogenerated by OCaml-Dockerfile scripts" @@
  from ?platform ~tag img
  @@ maintainer
  @@ shell

(* Apk based Dockerfile *)
let apk_opam2 ?(labels=[]) ?arch distro () =
  let img, tag = D.base_distro_tag ?arch distro in
  header ?arch distro @@ label (("distro_style", "apk") :: labels)
  @@ Linux.Apk.install "build-base bzip2 git tar curl ca-certificates openssl"
  @@ Linux.Git.init ()
  @@ install_opam_from_source ~add_default_link:false ~branch:"2.0" ()
  @@ install_opam_from_source ~add_default_link:false ~enable_0install_solver:true ~branch:"master" ()
  @@ run "strip /usr/local/bin/opam*"
  @@ from ~tag img
  @@ Linux.Apk.add_repository ~tag:"testing" "http://dl-cdn.alpinelinux.org/alpine/edge/testing"
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-2.0"] ~dst:"/usr/bin/opam-2.0" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-master"] ~dst:"/usr/bin/opam-2.1" ()
  @@ run "ln /usr/bin/opam-2.0 /usr/bin/opam"
  @@ Linux.Apk.dev_packages ()
  @@ Linux.Apk.add_user ~uid:1000 ~gid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()


(* Debian based Dockerfile *)
let apt_opam2 ?(labels=[]) ?arch distro () =
  let img, tag = D.base_distro_tag ?arch distro in
  header ?arch distro @@ label (("distro_style", "apt") :: labels)
  @@ Linux.Apt.install "build-essential curl git libcap-dev sudo"
  @@ Linux.Git.init ()
  @@ install_bubblewrap_from_source ()
  @@ install_opam_from_source ~add_default_link:false ~branch:"2.0" ()
  @@ install_opam_from_source ~add_default_link:false ~enable_0install_solver:true ~branch:"master" ()
  @@ from ~tag img
  @@ copy ~from:"0" ~src:["/usr/local/bin/bwrap"] ~dst:"/usr/bin/bwrap" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-2.0"] ~dst:"/usr/bin/opam-2.0" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-master"] ~dst:"/usr/bin/opam-2.1" ()
  @@ run "ln /usr/bin/opam-2.0 /usr/bin/opam"
  @@ run "ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime"
  @@ Linux.Apt.dev_packages ()
  @@ run "echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections"
  @@ Linux.Apt.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()


(* RPM based Dockerfile.

   [yum_workaround] activates the overlay/yum workaround needed
   for older versions of yum as found in CentOS 7 and earlier

   [enable_powertools] enables the PowerTools repository on CentOS 8 and above.
   This is needed to get most of *-devel packages frequently used by opam packages. *)
let yum_opam2 ?(labels= []) ?arch ~yum_workaround ~enable_powertools distro () =
  let img, tag = D.base_distro_tag ?arch distro in
  let workaround =
    if yum_workaround then
      run "touch /var/lib/rpm/*"
      @@ Linux.RPM.install "yum-plugin-ovl"
    else empty
  in
  header ?arch distro @@ label (("distro_style", "rpm") :: labels)
  @@ run "yum --version || dnf install -y yum"
  @@ workaround
  @@ Linux.RPM.update
  @@ Linux.RPM.dev_packages ~extra:"which tar curl xz libcap-devel openssl" ()
  @@ Linux.Git.init ()
  @@ install_bubblewrap_from_source ()
  @@ install_opam_from_source ~prefix:"/usr" ~add_default_link:false ~branch:"2.0" ()
  @@ install_opam_from_source ~prefix:"/usr" ~add_default_link:false ~enable_0install_solver:true ~branch:"master" ()
  @@ from ~tag img
  @@ run "yum --version || dnf install -y yum"
  @@ workaround
  @@ Linux.RPM.update
  @@ Linux.RPM.dev_packages ()
  @@ (if enable_powertools then run "yum config-manager --set-enabled powertools" @@ Linux.RPM.update else empty)
  @@ copy ~from:"0" ~src:["/usr/local/bin/bwrap"] ~dst:"/usr/bin/bwrap" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam-2.0"] ~dst:"/usr/bin/opam-2.0" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam-master"] ~dst:"/usr/bin/opam-2.1" ()
  @@ run "ln /usr/bin/opam-2.0 /usr/bin/opam"
  @@ run
       "sed -i.bak '/LC_TIME LC_ALL LANGUAGE/aDefaults    env_keep += \"OPAMYES OPAMJOBS OPAMVERBOSE\"' /etc/sudoers"
  @@ Linux.RPM.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()


(* Zypper based Dockerfile *)
let zypper_opam2 ?(labels=[]) ?arch distro () =
  let img, tag = D.base_distro_tag ?arch distro in
  header ?arch distro @@ label (("distro_style", "zypper") :: labels)
  @@ Linux.Zypper.dev_packages ()
  @@ Linux.Git.init ()
  @@ install_bubblewrap_from_source ()
  @@ install_opam_from_source ~prefix:"/usr" ~add_default_link:false ~branch:"2.0" ()
  @@ install_opam_from_source ~prefix:"/usr" ~add_default_link:false ~enable_0install_solver:true ~branch:"master" ()
  @@ from ~tag img
  @@ Linux.Zypper.dev_packages ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/bwrap"] ~dst:"/usr/bin/bwrap" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam-2.0"] ~dst:"/usr/bin/opam-2.0" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam-master"] ~dst:"/usr/bin/opam-2.1" ()
  @@ run "ln /usr/bin/opam-2.0 /usr/bin/opam"
  @@ Linux.Zypper.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()

(* Pacman based Dockerfile *)
let pacman_opam2 ?(labels=[]) ?arch distro () =
  let img, tag = D.base_distro_tag ?arch distro in
  header ?arch distro @@ label (("distro_style", "pacman") :: labels)
  @@ Linux.Pacman.dev_packages ()
  @@ Linux.Git.init ()
  @@ install_opam_from_source ~add_default_link:false ~branch:"2.0" ()
  @@ install_opam_from_source ~add_default_link:false ~enable_0install_solver:true ~branch:"master" ()
  @@ run "strip /usr/local/bin/opam*"
  @@ from ~tag img
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-2.0"] ~dst:"/usr/bin/opam-2.0" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-master"] ~dst:"/usr/bin/opam-2.1" ()
  @@ run "ln /usr/bin/opam-2.0 /usr/bin/opam"
  @@ Linux.Pacman.dev_packages ()
  @@ Linux.Pacman.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()

(* Cygwin based Dockerfile *)
let cygwin_opam2 ?(labels=[]) ?arch distro () =
  let img, tag = D.base_distro_tag ?arch distro in
  header ?arch distro @@ label (("distro_style", "cygwin") :: labels)
  @@ user "ContainerAdministrator"
  @@ Windows.Cygwin.(let extra, t = cygwin_packages () in setup ~extra () @@ t)
  @@ Windows.Cygwin.Git.init ()
  @@ install_opam_from_source_cygwin ~add_default_link:false ~branch:"2.0" ()
  @@ install_opam_from_source_cygwin ~add_default_link:false ~enable_0install_solver:true ~branch:"master" ()
  @@ run "strip /usr/local/bin/opam*"
  @@ from ~tag img
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-2.0"] ~dst:"/usr/bin/opam-2.0" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-master"] ~dst:"/usr/bin/opam-2.1" ()
  @@ run "ln /usr/bin/opam-2.0 /usr/bin/opam"
  @@ Windows.Cygwin.(let extra, t = cygwin_packages () in setup ~extra () @@ t)
  @@ Windows.Cygwin.Git.init ()

(* Native Windows, WinGet, Cygwin based Dockerfiles *)
let windows_opam2 ?winget ?(labels=[]) ?arch distro () =
  (* GNU Linker 2.36 may be breaking OCaml *)
  let cyg = { Windows.Cygwin.default with
              site = "http://ctm.crouchingtigerhiddenfruitbat.org/pub/cygwin/circa/64bit/2021/04/09/072945";
              args = Windows.Cygwin.default.args @ ["-X"] }
  in
  let version = match distro with `Windows (_, v) -> v | _ -> assert false in
  (match winget with
  | None -> Windows.Winget.install_from_release ~version ()
  | Some _ -> empty)
  @@ header ?arch distro @@ label (("distro_style", "windows") :: labels)
  @@ user "ContainerAdministrator"
  @@ begin
      let extra, t = match distro with
        | `Windows (`Mingw, _) ->
           Windows.Cygwin.mingw_packages (), empty
        | `Windows (`Msvc, _) ->
           Windows.Cygwin.msvc_packages (),
           Windows.install_visual_studio_build_tools [
               "Microsoft.VisualStudio.Component.VC.Tools.x86.x64";
               "Microsoft.VisualStudio.Component.Windows10SDK.18362"]
        | _ -> invalid_arg "Invalid distribution"
      in
      let extra, t' = Windows.Cygwin.ocaml_for_windows_packages ~cyg ~extra () in
      Windows.install_vc_redist () @@ t
      @@ Windows.Cygwin.setup ~cyg ~extra ~winsymlinks_native:true () @@ t'
    end
  @@ Windows.Winget.setup ?from:winget ()
  @@ Windows.Winget.dev_packages ~version ()
  @@ Windows.Cygwin.Git.init ~cyg ()
  @@ Windows.cleanup ()

let gen_opam2_distro ?winget ?(clone_opam_repo=true) ?arch ?labels d =
  let fn = match D.package_manager d with
  | `Apk -> apk_opam2 ?labels ?arch d ()
  | `Apt -> apt_opam2 ?labels ?arch d ()
  | `Yum ->
     let yum_workaround = match d with `CentOS `V7 -> true | _ -> false in
     let enable_powertools = match d with `CentOS (`V6 | `V7) -> false | `CentOS _ -> true | _ -> false in
     yum_opam2 ?labels ?arch ~yum_workaround ~enable_powertools d ()
  | `Zypper -> zypper_opam2 ?labels ?arch d ()
  | `Pacman -> pacman_opam2 ?labels ?arch d ()
  | `Cygwin -> cygwin_opam2 ?labels ?arch d ()
  | `Windows -> windows_opam2 ?winget ?labels ?arch d ()
  in
  let clone = if clone_opam_repo then
    let url = Dockerfile_distro.(os_family_of_distro d |> opam_repository) in
    run "git clone %S /home/opam/opam-repository" url
  else empty in
  let pers = match personality ?arch d with
    | None -> empty | Some pers -> entrypoint_exec [pers] in
  (D.tag_of_distro d, fn @@ clone @@ pers)

let create_switch ~arch distro t =
  let create_switch switch pkg = run "opam switch create %s %s" (OV.to_string switch) pkg in
  let switch = OV.with_patch t None in
  match distro with
  | `Windows (port, _) ->
    let (pn, pv) = Dockerfile_windows.ocaml_for_windows_package_exn ~port ~arch ~switch in
    create_switch switch (pv ^ pn)
  | _ ->
    create_switch switch (Ocaml_version.Opam.V2.name switch)

let all_ocaml_compilers hub_id arch distro =
  let distro_tag = D.tag_of_distro distro in
  let os_family = Dockerfile_distro.os_family_of_distro distro in
  let compilers =
    OV.Releases.recent |>
    List.filter (fun ov -> D.distro_supported_on arch ov distro) |> fun ovs ->
    let add_beta_remote =
      if List.exists OV.Releases.is_dev ovs then
         run "opam repo add beta git://github.com/ocaml/ocaml-beta-repository --set-default"
      else empty in
    add_beta_remote @@@ List.map (create_switch ~arch distro) ovs
  in
  let d =
    let pers = match personality ~arch distro with
      | None -> [] | Some pers -> [pers] in
    let sandbox = match os_family with
      | `Linux -> run "opam-sandbox-disable"
      | `Windows | `Cygwin -> empty
    in
    header ~arch ~tag:(Fmt.strf "%s-opam" distro_tag) ~img:hub_id distro
    @@ workdir "/home/opam/opam-repository" @@ run "git pull origin master"
    @@ sandbox
    @@ run "opam init -k git -a /home/opam/opam-repository --bare%s"
         (if os_family = `Windows then " --disable-sandboxing" else "")
    @@ compilers
    @@ run "opam switch %s" (OV.(to_string (with_patch OV.Releases.latest None)))
    @@ entrypoint_exec (pers @ ["opam"; "config"; "exec"; "--"])
    @@ run "opam install -y depext%s"
         (if os_family = `Windows then " depext-cygwinports" else "")
    @@ env ["OPAMYES","1"]
    @@ match os_family with
       | `Linux | `Cygwin -> cmd "bash"
       | `Windows -> cmd_exec ["cmd.exe"]
  in
  (Fmt.strf "%s" distro_tag, d)

let tag_of_ocaml_version ov =
  Ocaml_version.with_patch ov None |>
  Ocaml_version.to_string |>
  String.map (function '+' -> '-' | x -> x)

let separate_ocaml_compilers hub_id arch distro =
  let distro_tag = D.tag_of_distro distro in
  let os_family = Dockerfile_distro.os_family_of_distro distro in
  OV.Releases.recent_with_dev |> List.filter (fun ov -> D.distro_supported_on arch ov distro)
  |> List.map (fun ov ->
         let add_remote =
           if OV.Releases.is_dev ov then
             run "opam repo add beta git://github.com/ocaml/ocaml-beta-repository --set-default"
           else empty in
         let default_switch_name = OV.(with_patch (with_variant ov None) None |> to_string) in
         let variants =
           empty @@@ List.map (create_switch ~arch distro) (OV.Opam.V2.switches arch ov)
         in
         let d =
           let pers = match personality ~arch distro with
             | None -> [] | Some pers -> [pers] in
           let sandbox = match os_family with
             | `Linux -> run "opam-sandbox-disable"
             | `Windows | `Cygwin -> empty in
           header ~arch ~tag:(Fmt.strf "%s-opam" distro_tag) ~img:hub_id distro
           @@ workdir "/home/opam/opam-repository"
           @@ sandbox
           @@ run "opam init -k git -a /home/opam/opam-repository --bare%s"
                (if os_family = `Windows then "--disable-sandboxing" else "")
           @@ add_remote
           @@ variants
           @@ run "opam switch %s" default_switch_name
           @@ run "opam install -y depext%s"
                (if os_family = `Windows then "depext-cygwinports" else "")
           @@ env ["OPAMYES","1"]
           @@ entrypoint_exec (pers @ ["opam"; "config"; "exec"; "--"])
           @@ match os_family with
              | `Linux | `Cygwin -> cmd "bash"
              | `Windows -> cmd_exec ["cmd.exe"]
         in
         (Fmt.strf "%s-ocaml-%s" distro_tag (tag_of_ocaml_version ov), d) )


let deprecated =
  header (`Alpine `Latest)
  @@ run "echo 'This container is now deprecated and no longer supported. Please see https://github.com/ocaml/infrastructure/wiki/Containers for the latest supported tags.  Try to use the longer term supported aliases instead of specific distribution versions if you want to avoid seeing this message in the future.' && exit 1"

let multiarch_manifest ~target ~platforms =
  let ms =
    List.map
      (fun (image, arch) ->
        Fmt.strf
          "  -\n    image: %s\n    platform:\n      architecture: %s\n      os: linux"
          image arch)
      platforms
    |> String.concat "\n"
  in
  Fmt.strf "image: %s\nmanifests:\n%s" target ms
