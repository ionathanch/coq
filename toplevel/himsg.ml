
(* $Id$ *)

open Pp
open Util
open Options
open Names
open Generic
open Term
open Inductive
open Sign
open Environ
open Type_errors
open Reduction
open Logic
open Pretty
open Printer
open Ast

let guill s = "\""^s^"\""

let explain_unbound_rel k ctx n =
  let pe = pr_ne_env [< 'sTR"in environment" >] k ctx in
  [< 'sTR"Unbound reference: "; pe; 'fNL;
     'sTR"The reference "; 'iNT n; 'sTR" is free" >]

let explain_cant_execute k ctx c =
  let tc = gentermpr k ctx c in
  [< 'sTR"Cannot execute term:"; 'bRK(1,1); tc >]

let explain_not_type k ctx c =
  let pe = pr_ne_env [< 'sTR"In environment" >] k ctx in
  let pc = gentermpr k ctx c in
  [< pe; 'cUT; 'sTR "the term"; 'bRK(1,1); pc; 'sPC;
     'sTR"should be typed by Set, Prop or Type." >];;

let explain_bad_assumption k ctx c =
  let pc = gentermpr k ctx c in
  [< 'sTR "Cannot declare a variable or hypothesis over the term";
     'bRK(1,1); pc; 'sPC; 'sTR "because this term is not a type." >];;

let explain_reference_variables id =
  [< 'sTR "the constant"; 'sPC; print_id id; 'sPC; 
     'sTR "refers to variables which are not in the context" >]

let msg_bad_elimination ctx k = function
  | Some(ki,kp,explanation) ->
      let pki = gentermpr k ctx ki in
      let pkp = gentermpr k ctx kp in
      (hOV 0 
         [< 'fNL; 'sTR "Elimination of an inductive object of sort : ";
            pki; 'bRK(1,0);
            'sTR "is not allowed on a predicate in sort : "; pkp ;'fNL;
            'sTR "because"; 'sPC; 'sTR explanation >])
  | None -> 
      [<>]

let explain_elim_arity k ctx ind aritylst c p pt okinds = 
  let pi = gentermpr k ctx ind in
  let ppar = prlist_with_sep pr_coma (gentermpr k ctx) aritylst in
  let pc = gentermpr k ctx c in
  let pp = gentermpr k ctx p in
  let ppt = gentermpr k ctx pt in
  [< 'sTR "Incorrect elimination of"; 'bRK(1,1); pc; 'sPC;
     'sTR "in the inductive type"; 'bRK(1,1); pi; 'fNL;
     'sTR "The elimination predicate"; 'bRK(1,1); pp; 'sPC;
     'sTR "has type"; 'bRK(1,1); ppt; 'fNL;
     'sTR "It should be one of :"; 'bRK(1,1) ; hOV 0 ppar; 'fNL;
     msg_bad_elimination ctx k okinds >]

let explain_case_not_inductive k ctx c ct =
  let pc = gentermpr k ctx c in
  let pct = gentermpr k ctx ct in
  [< 'sTR "In Cases expression"; 'bRK(1,1); pc; 'sPC; 
     'sTR "has type"; 'bRK(1,1); pct; 'sPC; 
     'sTR "which is not an inductive definition" >]
  
let explain_number_branches k ctx c ct expn =
  let pc = gentermpr k ctx c in
  let pct = gentermpr k ctx ct in
  [< 'sTR "Cases on term"; 'bRK(1,1); pc; 'sPC ;
     'sTR "of type"; 'bRK(1,1); pct; 'sPC;
     'sTR "expects ";  'iNT expn; 'sTR " branches" >]

let explain_ill_formed_branch k ctx c i actty expty =
  let pc = gentermpr k ctx c in
  let pa = gentermpr k ctx actty in
  let pe = gentermpr k ctx expty in
  [< 'sTR "In Cases expression on term"; 'bRK(1,1); pc;
     'sPC; 'sTR "the branch " ; 'iNT (i+1);
     'sTR " has type"; 'bRK(1,1); pa ; 'sPC; 
     'sTR "which should be:"; 'bRK(1,1); pe >]

let explain_generalization k ctx (name,var) c =
  let pe = pr_ne_env [< 'sTR"in environment" >] k ctx in
  let pv = gentermpr k ctx var.body in
  let pc = gentermpr k (add_rel (name,var) ctx) c in
  [< 'sTR"Illegal generalization: "; pe; 'fNL;
     'sTR"Cannot generalize"; 'bRK(1,1); pv; 'sPC;
     'sTR"over"; 'bRK(1,1); pc; 'sPC;
     'sTR"which should be typed by Set, Prop or Type." >]

let explain_actual_type k ctx c ct pt =
  let pe = pr_ne_env [< 'sTR"In environment" >] k ctx in
  let pc = gentermpr k ctx c in
  let pct = gentermpr k ctx ct in
  let pt = gentermpr k ctx pt in
  [< pe; 'fNL;
     'sTR"The term"; 'bRK(1,1); pc ; 'sPC ;
     'sTR"does not have type"; 'bRK(1,1); pt; 'fNL;
     'sTR"Actually, it has type" ; 'bRK(1,1); pct >]

let explain_cant_apply k ctx s rator randl =
  let pe = pr_ne_env [< 'sTR"in environment" >] k ctx in
  let pr = gentermpr k ctx rator.uj_val in
  let prt = gentermpr k ctx rator.uj_type in
  let term_string = if List.length randl > 1 then "terms" else "term" in
  let appl = 
    prlist_with_sep pr_fnl
      (fun c ->
         let pc = gentermpr k ctx c.uj_val in
         let pct = gentermpr k ctx c.uj_type in
         hOV 2 [< pc; 'sPC; 'sTR": " ; pct >]) randl 
  in
  [< 'sTR"Illegal application ("; 'sTR s; 'sTR"): "; pe; 'fNL;
     'sTR"The term"; 'bRK(1,1); pr; 'sPC;
     'sTR"of type"; 'bRK(1,1); prt; 'sPC ;
     'sTR("cannot be applied to the "^term_string); 'fNL; 
     'sTR" "; v 0 appl >]

(* (co)fixpoints *)
let explain_ill_formed_rec_body k ctx str lna i vdefs =
  let pvd = gentermpr k ctx vdefs.(i) in
  let s =
    match List.nth lna i with Name id -> string_of_id id | Anonymous -> "_" in
  [< str; 'fNL; 'sTR"The ";
     if Array.length vdefs = 1 then [<>] else [<'iNT (i+1); 'sTR "-th ">];
     'sTR"recursive definition"; 'sPC; 'sTR s;
	 'sPC ; 'sTR":="; 'sPC ; pvd; 'sPC;
     'sTR "is not well-formed" >]
    
let explain_ill_typed_rec_body k ctx i lna vdefj vargs =
  let pvd = gentermpr k ctx (vdefj.(i)).uj_val in
  let pvdt = gentermpr k ctx (vdefj.(i)).uj_type in
  let pv = gentermpr k ctx (body_of_type vargs.(i)) in
  [< 'sTR"The " ;
     if Array.length vdefj = 1 then [<>] else [<'iNT (i+1); 'sTR "-th">];
     'sTR"recursive definition" ; 'sPC; pvd; 'sPC;
     'sTR "has type"; 'sPC; pvdt;'sPC; 'sTR "it should be"; 'sPC; pv >]

let explain_not_inductive k ctx c =
  let pc = gentermpr k ctx c in
  [< 'sTR"The term"; 'bRK(1,1); pc; 'sPC;
     'sTR "is not an inductive definition" >]

let explain_ml_case k ctx mes c ct br brt =
  let pc = gentermpr k ctx c in
  let pct = gentermpr k ctx ct in
  let expln =
    match mes with
      | "Inductive" -> [< pct; 'sTR "is not an inductive definition">]
      | "Predicate" -> [< 'sTR "ML case not allowed on a predicate">]
      | "Absurd" -> [< 'sTR "Ill-formed case expression on an empty type" >]
      | "Decomp" ->
          let plf = gentermpr k ctx br in
          let pft = gentermpr k ctx brt in
          [< 'sTR "The branch "; plf; 'wS 1; 'cUT; 'sTR "has type "; pft;
             'wS 1; 'cUT;
             'sTR "does not correspond to the inductive definition" >]
      | "Dependent" ->
          [< 'sTR "ML case not allowed for a dependent case elimination">]
      | _ -> [<>]
  in
  hOV 0 [< 'sTR "In ML case expression on "; pc; 'wS 1; 'cUT ;
           'sTR "of type";  'wS 1; pct; 'wS 1; 'cUT; 
           'sTR "which is an inductive predicate."; 'fNL; expln >]

let explain_cant_find_case_type k ctx c =
  let pe = gentermpr k ctx c in
  hOV 3 [<'sTR "Cannot infer type of whole Case expression on"; 'wS 1; pe >]

(***
let explain_cant_find_case_type_loc loc k ctx c =
  let pe = gentermpr k ctx c in
  user_err_loc
    (loc,"pretype",
     hOV 3 [<'sTR "Cannot infer type of whole Case expression on"; 
	     'wS 1; pe >])
***)

let explain_occur_check k ctx ev rhs =
  let id = "?" ^ string_of_int ev in
  let pt = gentermpr k ctx rhs in
  [< 'sTR"Occur check failed: tried to define "; 'sTR id;
     'sTR" with term"; 'bRK(1,1); pt >]

let explain_not_clean k ctx ev t =
  let c = Rel (Intset.choose (free_rels t)) in
  let id = "?" ^ string_of_int ev in
  let var = gentermpr k ctx c in
  [< 'sTR"Tried to define "; 'sTR id;
     'sTR" with a term using variable "; var; 'sPC;
     'sTR"which is not in its scope." >]

let explain_var_not_found k ctx id = 
  [< 'sTR "The variable"; 'sPC; 'sTR (string_of_id id);
     'sPC ; 'sTR "was not found"; 
     'sPC ; 'sTR "in the current"; 'sPC ; 'sTR "environment" >]

(* Pattern-matching errors *)
let explain_bad_constructor k ctx cstr ind =
  let pi = pr_inductive ind in
  let pc = pr_constructor cstr in
  let pt = pr_inductive (inductive_of_constructor cstr) in
  [< 'sTR "Expecting a constructor in inductive type "; pi; 'bRK(1,1) ;
     'sTR " but found the constructor " ; pc; 'bRK(1,1) ;
     'sTR " in inductive type "; pt >]

let explain_wrong_numarg_of_constructor k ctx cstr n =
  let pc = pr_constructor cstr in
  [<'sTR "The constructor "; pc;
    'sTR " expects " ; 'iNT n ; 'sTR " arguments. ">]

let explain_wrong_predicate_arity k ctx pred nondep_arity dep_arity=
  let pp = gentermpr k ctx pred in
  [<'sTR "The elimination predicate " ; pp; 'cUT;
    'sTR "should be of arity " ;
    'iNT nondep_arity ; 'sTR " (for non dependent case)  or " ;
    'iNT dep_arity ; 'sTR " (for dependent case).">]

let explain_needs_inversion k ctx x t =
  let px = gentermpr k ctx x in
  let pt = gentermpr k ctx t in
  [< 'sTR "Sorry, I need inversion to compile pattern matching of term ";
     px ; 'sTR " of type: "; pt>]


let explain_type_error k ctx = function
  | UnboundRel n -> 
      explain_unbound_rel k ctx n
  | CantExecute c -> 
      explain_cant_execute k ctx c
  | NotAType c -> 
      explain_not_type k ctx c
  | BadAssumption c -> 
      explain_bad_assumption k ctx c
  | ReferenceVariables id -> 
      explain_reference_variables id
  | ElimArity (ind, aritylst, c, p, pt, okinds) ->
      explain_elim_arity k ctx ind aritylst c p pt okinds 
  | CaseNotInductive (c, ct) -> 
      explain_case_not_inductive k ctx c ct
  | NumberBranches (c, ct, n) -> 
      explain_number_branches k ctx c ct n
  | IllFormedBranch (c, i, actty, expty) -> 
      explain_ill_formed_branch k ctx c i actty expty 
  | Generalization (nvar, c) ->
      explain_generalization k ctx nvar c
  | ActualType (c, ct, pt) -> 
      explain_actual_type k ctx c ct pt
  | CantAply (s, rator, randl) ->
      explain_cant_apply k ctx s rator randl
  | IllFormedRecBody (i, lna, vdefj, vargs) ->
      explain_ill_formed_rec_body k ctx i lna vdefj vargs
  | IllTypedRecBody (i, lna, vdefj, vargs) ->
      explain_ill_typed_rec_body k ctx i lna vdefj vargs
  | NotInductive c ->
      explain_not_inductive k ctx c
  | MLCase (mes,c,ct,br,brt) ->
      explain_ml_case k ctx mes c ct br brt
  | CantFindCaseType c ->
      explain_cant_find_case_type k ctx c
  | OccurCheck (n,c) ->
      explain_occur_check k ctx n c
  | NotClean (n,c) ->
      explain_not_clean k ctx n c
  | VarNotFound id ->
      explain_var_not_found k ctx id
  (* Pattern-matching errors *)
  | BadConstructor (c,ind) ->
      explain_bad_constructor k ctx c ind
  | WrongNumargConstructor (c,n) ->
      explain_wrong_numarg_of_constructor k ctx c n
  | WrongPredicateArity (pred,n,dep) ->
      explain_wrong_predicate_arity k ctx pred n dep
  | NeedsInversion (x,t) ->
      explain_needs_inversion k ctx x t

let explain_refiner_bad_type arg ty conclty =
  [< 'sTR"refiner was given an argument"; 'bRK(1,1); 
     prterm arg; 'sPC;
     'sTR"of type"; 'bRK(1,1); prterm ty; 'sPC;
     'sTR"instead of"; 'bRK(1,1); prterm conclty >]

let explain_refiner_occur_meta t =
  [< 'sTR"cannot refine with term"; 'bRK(1,1); prterm t;
     'sPC; 'sTR"because there are metavariables, and it is";
     'sPC; 'sTR"neither an application nor a Case" >]

let explain_refiner_cannot_applt t harg =
  [< 'sTR"in refiner, a term of type "; 'bRK(1,1);
     prterm t; 'sPC; 'sTR"could not be applied to"; 'bRK(1,1);
     prterm harg >]

let explain_refiner_cannot_unify m n =
  let pm = prterm m in 
  let pn = prterm n in
  [< 'sTR"Impossible to unify"; 'bRK(1,1) ; pm; 'sPC ;
     'sTR"with"; 'bRK(1,1) ; pn >]

let explain_refiner_cannot_generalize ty =
  [< 'sTR "cannot find a generalisation of the goal with type : "; 
     prterm ty >]

let explain_refiner_not_well_typed c =
  [< 'sTR"The term " ; prterm c ; 'sTR" is not well-typed" >]

let explain_refiner_bad_tactic_args s l =
  [< 'sTR "Internal tactic "; 'sTR s; 'sTR " cannot be applied to ";
     Tacmach.pr_tactic (s,l) >]

let explain_refiner_error = function
  | BadType (arg,ty,conclty) -> explain_refiner_bad_type arg ty conclty
  | OccurMeta t -> explain_refiner_occur_meta t
  | CannotApply (t,harg) -> explain_refiner_cannot_applt t harg
  | CannotUnify (m,n) -> explain_refiner_cannot_unify m n
  | CannotGeneralize (_,ty) -> explain_refiner_cannot_generalize ty
  | NotWellTyped c -> explain_refiner_not_well_typed c
  | BadTacticArgs (s,l) -> explain_refiner_bad_tactic_args s l

let error_non_strictly_positive k lna c v  =
  let env = assumptions_for_print lna in
  let pc = gentermpr k env c in
  let pv = gentermpr k env v in
  [< 'sTR "Non strictly positive occurrence of "; pv; 'sTR " in";
     'bRK(1,1); pc >]

let error_ill_formed_inductive k lna c v =
  let env = assumptions_for_print lna in
  let pc = gentermpr k env c in
  let pv = gentermpr k env v in
  [< 'sTR "Not enough arguments applied to the "; pv;
     'sTR " in"; 'bRK(1,1); pc >]

let error_ill_formed_constructor k lna c v =
  let env = assumptions_for_print lna in
  let pc = gentermpr k env c in
  let pv = gentermpr k env v in
  [< 'sTR "The conclusion of"; 'bRK(1,1); pc; 'bRK(1,1); 
     'sTR "is not valid;"; 'bRK(1,1); 'sTR "it must be built from "; pv >]

let str_of_nth n =
  (string_of_int n)^
  (match n mod 10 with
     | 1 -> "st"
     | 2 -> "nd"
     | 3 -> "rd"
     | _ -> "th")

let error_bad_ind_parameters k lna c n v1 v2  =
  let env = assumptions_for_print lna in
  let pc = gentermpr k env c in
  let pv1 = gentermpr k env v1 in
  let pv2 = gentermpr k env v2 in
  [< 'sTR ("The "^(str_of_nth n)^" argument of "); pv2; 'bRK(1,1);
     'sTR "must be "; pv1; 'sTR " in"; 'bRK(1,1); pc >]

let error_same_names_types id =
  [< 'sTR "The name"; 'sPC; print_id id; 'sPC; 
     'sTR "is used twice is the inductive types definition." >]

let error_same_names_constructors id cid =
  [< 'sTR "The constructor name"; 'sPC; print_id cid; 'sPC; 
     'sTR "is used twice is the definition of type"; 'sPC;
     print_id id >]

let error_not_an_arity id =
  [< 'sTR "The type of"; 'sPC; print_id id; 'sPC; 'sTR "is not an arity." >]

let error_bad_entry () =
  [< 'sTR "Bad inductive definition." >]

let explain_inductive_error = function
  | NonPos (lna,c,v) -> error_non_strictly_positive CCI lna c v
  | NotEnoughArgs (lna,c,v) -> error_ill_formed_inductive CCI lna c v
  | NotConstructor (lna,c,v) -> error_ill_formed_constructor CCI lna c v
  | NonPar (lna,c,n,v1,v2) -> error_bad_ind_parameters CCI lna c n v1 v2
  | SameNamesTypes id -> error_same_names_types id
  | SameNamesConstructors (id,cid) -> error_same_names_constructors id cid
  | NotAnArity id -> error_not_an_arity id
  | BadEntry -> error_bad_entry ()
