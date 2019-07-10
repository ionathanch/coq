open Utest
open Util
open Stages
open Stage
open Annot
open Constraints

let log_out_ch = open_log_out_ch __FILE__

(** Helpers for debugging *)

let str_tuple (a, b, c) = "(" ^ string_of_int a ^ "," ^ string_of_int b ^ "," ^ string_of_int c ^ ")"
let str_list_tuple lst = "[;" ^ List.fold_right (fun tup str -> str_tuple tup ^ ";" ^ str) lst "]"
let str_int_set set = "{," ^ Int.Set.fold (fun i str -> string_of_int i ^ "," ^ str) set "}"

let debug = Printf.printf "%s\n"

(* Testing constants *)

let test_prefix = "kernel-stages_test"

let inf = -1

let s0_0 = Stage (StageVar (0, 0))
let s0_1 = Stage (StageVar (0, 1))
let s2_0 = Stage (StageVar (2, 0))
let s5_0 = Stage (StageVar (5, 0))
let s9_0 = Stage (StageVar (9, 0))
let s9_1 = Stage (StageVar (9, 1))

let s0_0_and_s9_1 = (add s0_0 s9_1 empty)
let s9_0_and_s0_1 = (add s9_0 s0_1 empty)
let s0_1_and_s9_0 = (add s0_1 s9_0 empty)
let s9_1_and_s0_0 = (add s9_1 s0_0 empty)

let pos_cycle = union s0_0_and_s9_1 s9_0_and_s0_1
let pos_cycle_bigger =
  let cstrnts1 = add s0_0 s2_0 empty in
  let cstrnts2 = add s2_0 s9_1 cstrnts1 in
  add s9_0 s0_1 cstrnts2
let neg_cycle = union s0_1_and_s9_0 s9_1_and_s0_0
let neg_cycle_bigger =
  let cstrnts1 = add s0_1 s9_0 empty in
  let cstrnts2 = add s9_1 s5_0 cstrnts1 in
  add s5_0 s0_0 cstrnts2
let neg_cycle_extra1 =
  add s2_0 s0_0 neg_cycle_bigger
let neg_cycle_extra2 =
  add s0_0 s2_0 neg_cycle_bigger

(* Constraints tests *)

let add_prefix = test_prefix ^ "-add"
let add_name i = add_prefix ^ string_of_int i

let add1 = mk_eq_test
  (add_name 1)
  "s0⊑s0+1 not added"
  empty
  (add s0_0 s0_1 empty)
let add2 = mk_eq_test
  (add_name 2)
  "s0⊑∞ not added"
  empty
  (add s0_0 infty empty)
let add3 = mk_bool_test
  (add_name 3)
  "s0+1⊑s0 is added"
  (contains (0, 0) (add s0_1 s0_0 empty))
let add4 = mk_bool_test
  (add_name 4)
  "∞⊑s0 is added"
  (contains (inf, 0) (add infty s0_0 empty))
let add5 = mk_bool_test
  (add_name 5)
  "s9⊑s0 is added"
  (contains (9, 0) (add s9_0 s0_0 empty))
let add6 = mk_bool_test
  (add_name 6)
  "s9+1⊑s0+1 is added"
  (contains (9, 0) (add s9_1 s0_1 empty))
let add7 = mk_bool_test
  (add_name 7)
  "adding s0⊑s9 does not add s9⊑s0"
  (not (contains (9, 0) (add s0_0 s9_0 empty)))
let add_tests = [add1; add2; add3; add4; add5; add6]

let fold1 =
  let f vfrom vto wt lst = (vfrom, vto, wt) :: lst in
  let cstrnts_list = fold f pos_cycle [] in
  mk_bool_test
    (test_prefix ^ "-fold1")
    "folding constraints works"
    (List.mem (0, 9, 1) cstrnts_list && List.mem (9, 0, 1) cstrnts_list)
let fold_tests = [fold1]

let filter1 =
  let f vfrom vto wt = Int.equal 9 vto in
  let cstrnts = filter f pos_cycle in
  mk_bool_test
    (test_prefix ^ "-filter1")
    "filtering constraints works"
    (contains (0, 9) cstrnts && not (contains (9, 0) cstrnts))
let filter_tests = [filter1]

let sup1 =
  let cstrnts = add s5_0 s9_0 (add s5_0 s0_0 empty) in
  let sups = sup 5 cstrnts in
  mk_bool_test
    (test_prefix ^ "-sup1")
    "sup returns all superstages"
    (Int.Set.mem 0 sups && Int.Set.mem 9 sups)
let sup_tests = [sup1]

let sub1 =
  let cstrnts = add s9_0 s5_0 (add s0_0 s5_0 empty) in
  let subs = sub 5 cstrnts in
  mk_bool_test
    (test_prefix ^ "-sub1")
    "sup returns all substages"
    (Int.Set.mem 0 subs && Int.Set.mem 9 subs)
let sub_tests = [sub1]

(* RecCheck tests *)

let bf_prefix = test_prefix ^ "-bf"
let bf_name i = add_prefix ^ string_of_int i

let bf1 = mk_eq_test
  (bf_name 1)
  "Bellman-Ford returns empty set for positive size 2 cycle"
  Int.Set.empty
  (bellman_ford_all pos_cycle)
let bf2 = mk_eq_test
  (bf_name 2)
  "Bellman-Ford returns empty set for positive size 3 cycle"
  Int.Set.empty
  (bellman_ford_all pos_cycle_bigger)
let bf3 = mk_bool_test
  (bf_name 3)
  "Bellman-Ford returns nonempty set for negative size 2 cycle"
  (not (Int.Set.is_empty (bellman_ford_all neg_cycle)))
let bf4 = mk_bool_test
  (bf_name 4)
  "Bellman-Ford returns nonempty set for negative size 3 cycle"
  (not (Int.Set.is_empty (bellman_ford_all neg_cycle_bigger)))
let bf5 = mk_bool_test
  (bf_name 5)
  "Bellman-Form returns nonempty set for size 3 cycle without vertices NOT in cycle"
  (let vs = bellman_ford_all neg_cycle_extra1 in
  (not (Int.Set.is_empty vs) && not (Int.Set.mem 2 vs)))
let bellman_ford_tests = [bf1; bf2; bf3; bf4; bf5]

let upward_closure =
  let up = upward neg_cycle_extra1 (Int.Set.singleton 0) in
  let expected = Int.Set.of_list [0; 5; 9] in
  mk_bool_test
    (test_prefix ^ "-upward_closure")
    "upward closure from s0"
    (Int.Set.equal up expected)
let downward_closure =
  let down = downward neg_cycle_extra2 (Int.Set.singleton 0) in
  let expected = Int.Set.of_list [0; 5; 9] in
  mk_bool_test
    (test_prefix ^ "-downward_closure")
    "downward closure from s0"
    (Int.Set.equal down expected)
let closure_tests = [upward_closure; downward_closure]

(* Run tests *)

let tests = add_tests
  @ fold_tests
  @ filter_tests
  @ sup_tests
  @ sub_tests
  @ bellman_ford_tests
  @ closure_tests

let _ = run_tests __FILE__ log_out_ch tests
