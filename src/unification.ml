
open Lexp

module VMap = Map.Make (struct type t = int let compare = compare end)

type substitution = lexp VMap.t * int
type constraints  = (lexp * lexp) list
(* IMPROVEMENT For error handling : can carry location and name of type error *)
type a' expected =
  | Some of 'a
  | Error of location * string (*location * type name*)
  | None

(* For convenience *)
type return_type = (substitution * constraints) option

(**
 * Imm       , Imm                -> if Imm =/= Imm then ERROR else OK

 * Cons      , Cons               -> ERROR

 * Builtin   , Builtin            -> if Builtin =/= Buitin
                                     then ERROR else OK
 * Builtin   , lexp               -> UNIFY lexp of Builtin with lexp

 * Let       , lexp               -> UNIFY right part of Let with lexp

 * Var       , Var                -> if db_index ~= db_index UNIFY else ERROR
 * Var       , MetaVar            -> UNIFY Metavar
 * Var       , lexp               -> ERROR

 * Arrow     , Arrow              -> if var_kind = var_kind
                                     then UNIFY ltype & lexp else ERROR
 * Arrow     , lexp               -> ERROR

 * lexp      , {metavar <-> none} -> UNIFY
 * lexp      , {metavar <-> lexp} -> UNFIFY lexp subst[metavar]
 * metavar   , metavar            -> if Metavar = Metavar then OK else ERROR
 * metavar   , lexp               -> ERROR

 * Lamda     , Lambda             -> if var_kind = var_kind
                                     then unify ltype & lxp else ERROR
 * Lambda    , Var                -> constraints
 * Lambda    , lexp               -> ERROR

   (*TODO*)
 * Call      , lexp               ->
 * Inductive , lexp               ->
 * Case      , case               ->
 * lexp      , lexp               ->

 * lexp is equivalent to _ in ocaml
 * (Let , lexp) == (lexp , Let)
 * UNIFY -> recursive call or dispatching
 * OK -> add a substituion to the list of substitution
*)
(*l & r commutative ?*)
let rec unify (l: lexp) (r: lexp) (subst: substitution) : return_type =
  (* Dispatch to the right unifyer*)
  (* TODO : check rule order*)
  match (l, r) with
  | (Imm, Imm)   -> _unify_imm      l r subst
  | (Cons, Cons) -> None
  | (Builtin, _) -> _unify_builtin  l r subst
  | (_, Builtin) -> _unify_builtin  r l subst
  | (Let, _)     -> _unify_let      l r subst
  | (_, Let)     -> _unify_let      r l subst
  | (Var, _)     -> _unify_var      l r subst
  | (_, Var)     -> _unify_var      r l subst
  | (Arrow, _)   -> _unify_arrow    l r subst
  | (_, Arrow)   -> _unify_arrow    r l subst
  | (Metavar, _) -> _unify_metavar  l r subst
  | (_, MetaVar) -> _unify_metavar  r l susbt
  | (Lambda, _)  -> _unify_lambda   l r subst
  | (_, Lambda)  -> _unify_lambda   r l subst
  | (_, _)       -> None

(* maybe split unify into 2 function : is_unifyable and unify ?
 * cf _unify_lambda for (Lambda, Lambda) behavior*)

(** Unify a Lambda and a lexp if possible
 * See above for result
 *)
let _unify_lambda (lambda: lexp) (lxp: lexp) (subst: substituion) : return_type =
  match (lambda, lexp) with
  | (Lambda (var_kind1, _, ltype1, lexp1), Lambda (var_kind2, _, ltype2, lexp2))
    -> if var_kind1 = var_kind2
    then _unify_inner_arrow ltype1 lexp1 ltype2 lexp2 subst
    else None
  | (Lambda, Var)   -> (subst, (lambda, lexp))
  | (Lambda, Let)   -> (subst, (lambda, lexp))
  | (Lambda, Arrow) -> (subst, (lambda, lexp)) (* ?? *)
  | (Lambda, Call)  -> (subst, (lambda, lexp))
  | (_, _)          -> None

(** Unify a Metavar and a lexp if possible
 * See above for result
 *)
let _unify_metavar (meta: lexp) (lxp: lexp) (subst: substitution) : return_type =
  match (meta, lxp) with
  | (Metavar val1, Metavar val2) ->
    if val1 = val2
    then (add_substitution meta lxp subst, ())
    else None
  | (Metavar v, _) -> (
      match find_or_none v subst with
      | None          -> (associate v lxp subst, ())
      | Some (lxp_)   -> unify lxp_ lxp subst) (*Not sure if it's the expected behavior*)
  | (_, _) -> None

(** Unify a Arrow and a lexp if possible
 * (Arrow, Arrow) -> if var_kind = var_kind
                     then unify ltype & lexp (Arrow (var_kind, _, ltype, lexp))
                     else None
 * (_, _) -> None
 *)
let rec _unify_arrow (arrow: lexp) (lxp: lexp) (subst: substitution)
  : return_type =
  match (arrow, lxp) with
  (*?????*)
  | (Arrow (_, _, ltype1, lexp1), Arrow (_, _, ltype2, lexp2))
    -> if var_kind1 = var_kind2
    then (match _unify_inner_arrow ltype1 lexp1 ltype2 lexp2 susbt with
        | Some -> (add_substitution arrow subst, ())
        | None -> None)
    else None
  (*| *)
  | (_, _) -> None

(** Unify lexp & ltype (Arrow (_,_,ltype, lexp)) of two Arrow*)
let _unify_inner_arrow (lt1: lexp) (lxp1: lexp)
    (lt2: lexp) (lxp2: lexp) (subst: substitution): return_type =
  match unify lt1 lt2 subst with
  | Some (subst_, const) -> ( (*bracket for formating*)
      match unify lxp1 lxp2 subst_ with
      | Some (s, c) -> Some(s, const@c)
      | None -> None )
  | None -> None

(** Unify a Var and a lexp, if possible
 * (Var, Var) -> unify if they have the same bebuijn index FIXME : shift indexes
 * (Var, Metavar) -> unify_metavar Metavar var subst
 * (_, _) -> None
 *)
let _unify_var (var: lexp) (r: lexp) (subst: substitution) : return_type =
  match (var, r) with
  | (Var (_, idx1), Var (_, idx2))
    -> if idx1 = idx2 then (add_substitution var subst, ())
    else None
  | (Var, Metavar) -> _unify_metavar r var subst
  (*| (Var, _) -> ???(*TODO*)*)
  | (_, _)   -> None

(** Unify two Imm if they match <=> Same type and same value
 * Add one of the Imm (the first arguement) to the substitution *)
let _unify_imm (l: lexp) (r: lexp) (subst: substitution) : return_type =
  match (l, r) with
  | (Imm (String (_, v1)), Imm (String (_, v2)))
    -> if v1 = v2 then (add_substitution l subst, ())
    else None
  | (Imm (Integer (_, v1)), Imm (Integer (_, v2)))
    -> if v1 = v2 then (add_substitution l subst, ())
    else None
  | (Imm (Float (_, v1)), Imm (Float (_, v2)))
    -> if v1 = v2 then (add_substitution l subst, ())
    else None
  | (_, _) -> None

(** Unify a builtin (bltin) and a lexp (lxp) if it is possible
 * If the two arguments are builtin, unify based on name
 * If it's a Builtin and an other lexp, unify lexp part of Builtin with the lexp
*)
let _unify_builtin (bltin: lexp) (lxp: lexp) (subst: substitution) : return_type =
  match (bltin, lxp) with
  | (Builtin ((_, name1), _), Builtin ((_, name2),_))
    -> if name1 = name2 then (add_substitution l subst, ())
    else None (* assuming that builtin have unique name *)
  | (Builtin (_, lxp_), _) -> unify lxp lxp subst
  | (_, _) -> None

(** Unify a Let (let_) and a lexp (lxp), if possible
 * Unify the left lexp part of the Let (Let (_, _, lxp)) with the lexp
 *)
let _unify_let (let_: lexp) (lxp: lexp) (subst: substitution) : return_type =
  match let_ with (* Discard the middle part of Let : right behavior ? *)
  | Let (_, _, lxp_) -> (match unify lxp_ lxp subst with
      | None -> None
      | Some _ -> (add_substitution let_ subst, ()) )
  | _ -> None

(** Generate the next metavar by taking the highest value and
 * adding it one
 *)
let add_substitution (lxp: lexp) ((subst, max_): substitution) : substitution =
  associate (max_ + 1) lxp (subst, max_)

(** If key is in map returns the value associated
 * else returns None
 *)
let find_or_none (value: lexp) ((map, max_): substitution) : lexp option =
  match value with
  | Metavar idx -> (if max_ < idx (* 0 < keys <= max_ *)
                    then None
                    else (if VMap.mem idx map
                           then Some ((VMap.find idx map, max_))
                           else None))
  | _ -> None

(** Alias for VMap.add*)
let associate (meta: int) (lxp: lexp) ((subst, max_): substitution)
  : substitution =
  (VMap.add meta lexp subst, (max max_ meta ))

let empty_subst = (VMap.empty, 0)
