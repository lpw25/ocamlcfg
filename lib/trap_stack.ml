(**************************************************************************)
(*                                                                        *)
(*                                 OCamlFDO                               *)
(*                                                                        *)
(*                     Greta Yorsh, Jane Street Europe                    *)
(*                                                                        *)
(*   Copyright 2019 Jane Street Group LLC                                 *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)
[@@@ocaml.warning "+a-4-30-40-41-42"]

type t = stack ref

and h =
  | Unknown
  | Label of Label.t

and stack =
  | Emp
  | Unknown
  | Push of
      { mutable h : h;
        t : t
      }
  | Pop of t

(* CR-soon gyorsh: we could represent adjust trap with negative delta as pop
   and *)

(* CR-soon gyorsh: test it *)
(* rep that shortens chains of pop;push *)
let rec rep (t : t) =
  match !t with
  | Unknown -> t
  | Emp -> t
  | Push p ->
      p.t := !(rep p.t);
      t
  | Pop s -> (
      let s' = rep s in
      match !s' with
      | Push p -> p.t
      | _ ->
          s := !s';
          t )

let emp = ref Emp

let unknown () = ref (Unknown : stack)

let pop t = rep (ref (Pop t))

let push t h = ref (Push { h = Label h; t = rep t })

let push_unknown t = ref (Push { h = Unknown; t = rep t })

exception Unresolved

let top_exn t =
  match !(rep t) with
  | Emp -> None
  | Push { h = Label l; t = _ } -> Some l
  | Push { h = Unknown; t = _ } | Unknown | Pop _ -> raise Unresolved

(** Raises [Unresolved] if t contains any pop or Unknown. *)
let rec to_list_exn t =
  match !(rep t) with
  | Emp -> []
  | Push { h = Label h; t } ->
      (* This won't terminate if [s] is a cycle back to [t]. *)
      h :: to_list_exn t
  | Push { h = Unknown; t = _ } | Unknown | Pop _ -> raise Unresolved

let rec print t =
  match !t with
  | Emp -> Printf.printf "emp\n"
  | Unknown -> Printf.printf "unknown\n"
  | Push p ->
      ( match p.h with
      | Label l -> Printf.printf "%d::" l
      | Unknown -> Printf.printf "?::" );
      print p.t
  | Pop s ->
      Printf.printf "pop::";
      print s

let print_pair msg t1 t2 =
  Printf.printf "%s\n" msg;
  print t1;
  print t2

let fail () =
  Misc.fatal_error "Malformed trap stack: mismatched pop/push trap handlers."

(* If there is a cycle, this won't terminate but that's easy to debug. If
   there is no cycle, it terminates because every step decreases the
   following well-founded order: (1) removes one unknown, (2) transforms one
   pop into push, and there is no rule that creates pop from push, or (3) -
   reduces the length of the stack. *)
let rec unify s1 s2 =
  match (!s1, !s2) with
  | Emp, Emp -> ()
  | Unknown, Unknown -> ()
  | Unknown, _ -> s1 := !(rep s2)
  | _, Unknown -> s2 := !(rep s1)
  | Push p1, Push p2 ->
      ( (* unify handlers *)
      match (p1.h, p2.h) with
      | Unknown, Unknown -> ()
      | Label l1, Label l2 ->
          if l1 <> l2 then (
            print_pair "push/push" s1 s2;
            fail () )
      | Unknown, Label _ -> p1.h <- p2.h
      | Label _, Unknown -> p2.h <- p1.h );
      unify p1.t p2.t
  | Pop s1, Pop s2 -> unify s1 s2
  | Pop s, _ -> (
      let s' = rep s in
      match !s' with
      | Push p -> unify p.t s2
      | _ -> unify s' (push_unknown s2) )
  | _, Pop s -> (
      let s' = rep s in
      match !s' with
      | Push p -> unify s1 p.t
      | _ -> unify (push_unknown s1) s' )
  | Emp, _ | _, Emp ->
      print_pair "emp" s1 s2;
      fail ()
