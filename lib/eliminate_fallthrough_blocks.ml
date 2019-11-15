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

module C = Cfg
module CL = Cfg_with_layout

let is_fallthrough_block cfg_with_layout (block : C.basic_block) =
  let cfg = CL.cfg cfg_with_layout in
  if
    cfg.entry_label = block.start
    || block.is_trap_handler || block.can_raise
    || List.length block.body > 0
  then None
  else
    match C.successor_labels ~normal:true ~exn:false cfg block with
    | [target_label] -> Some target_label
    | _ -> None

(* CR mshinwell: The logic below looks similar in structure to
   [Eliminate_dead_blocks]. I think it would be worth trying to factor that
   out (into a functor) -- this would presumably form the starting point for
   a generic traversal / rewrite mechanism in the future. *)

let rec disconnect_fallthrough_blocks cfg_with_layout =
  let cfg = CL.cfg cfg_with_layout in
  let found =
    Label.Tbl.fold
      (fun label block found ->
        match is_fallthrough_block cfg_with_layout block with
        | None -> found
        | Some target_label ->
            if !C.verbose then
              Printf.printf "block at %d has single successor %d\n" label
                target_label;
            Disconnect_block.disconnect cfg_with_layout label;
            label :: found)
      cfg.blocks []
  in
  let len = List.length found in
  if len > 0 then (
    if !C.verbose then
      Printf.printf "%s: disconnected fallthrough blocks: %d\n" cfg.fun_name
        len;
    disconnect_fallthrough_blocks cfg_with_layout )

let run cfg_with_layout =
  let cfg = CL.cfg cfg_with_layout in

  (* Find and disconnect fallthrough blocks (i.e., blocks with empty body and
     a single successor) by rerouting their predecessors to point directly to
     their successors. It can create a new fallthrough block, for example: if
     we have edges { A -> B, B -> C , A -> C } and B is the only fallthrough
     here and we eliminate it, then A becomes fallthrough. Repeat until
     fixpoint.

     Disconnected fallthrough nodes can be eliminate by dead block
     elimination pass.

     Termination is guaranteed because every step eliminates a node. The
     order matters for performance but not for the final result. *)
  let len = Label.Tbl.length cfg.blocks in
  if !C.verbose then CL.print_dot cfg_with_layout "before_elim_ft";
  disconnect_fallthrough_blocks cfg_with_layout;
  Eliminate_dead_blocks.run cfg_with_layout;
  let new_len = Label.Tbl.length cfg.blocks in
  if !C.verbose then (
    Printf.printf "%s: eliminated %d block that were dead or fallthrough.\n"
      cfg.fun_name (len - new_len);
    CL.print_dot cfg_with_layout "after_elim_ft" )
