(*
 *      Description:
 *          Read Eval Print Loop (REPL). It allows you to eval typer code
 *          interactively line by line.
 *
 *      Example:
 *
 *          $./_build/ityper [files]
 *            In[ 1] >> sqr = lambda x -> x * x;
 *            In[ 2] >> (sqr 4);
 *              Out[ 2] >> 16
 *            In[ 3] >> let a = 3; b = 3; in
 *                    .     a + b;
 *              Out[ 3] >> 6
 *
 * --------------------------------------------------------------------------- *)


open Debug
open Prelexer
open Lexer
open Sexp
open Grammar
open Pexp
open Debruijn
open Lparse
open Myers
open Eval
open Util
open Lexp
open Fmt

let print_input_line i =
    print_string "  In[";
    ralign_print_int i 2;
    print_string "] >> "
;;

(*  Read stdin for input. Returns only when the last char is ';'
 *  We can use '%' to prevent evaluation
 *  If return is pressed and the last char is not ';' then
 *  indentation will be added                                       *)
let rec read_input i =
    print_input_line i;
    flush stdout;

    let rec loop str i =
        flush stdout;
        let line = input_line stdin in
        let s = String.length str in
        let n = String.length line in
            if s = 0 && n = 0 then read_input i else
            (if n = 0 then (
                print_string "          . ";
                print_string (make_line ' ' (i * 4));
                loop str (i + 1))
            else
        let str = if s > 0 then  String.concat "\n" [str; line] else line in
            if line.[n - 1] = ';' || line.[0] = '%' then
                str
            else (
                print_string "          . ";
                print_string (make_line ' ' (i * 4));
                loop str (i + 1))) in

    loop "" i
;;

(* Interactive mode is not usual typer
 It makes things easier to test out code *)
type pdecl = pvar * pexp * bool
type pexpr = pexp

type ldecl = vdef * lexp * ltype
type lexpr = lexp

(* Grouping declaration together will enable us to support mutually recursive
 * declarations while bringing us closer to normal typer *)
let ipexp_parse (sxps: sexp list): (pdecl list * pexpr list) =
    let rec _pxp_parse sxps dacc pacc =
        match sxps with
            | [] -> (List.rev dacc), (List.rev pacc)
            | sxp::tl -> match sxp with
                (* Declaration *)
                | Node (Symbol (_, ("_=_" | "_:_")), [Symbol s; t]) ->
                    _pxp_parse tl (List.append (pexp_p_decls sxp) dacc) pacc
                (* Expression *)
                | _ -> _pxp_parse tl dacc ((pexp_parse sxp)::pacc) in
        _pxp_parse sxps [] []
;;

let ilexp_parse pexps lctx =
    let pdecls, pexprs = pexps in
    let ldecls, lctx = lexp_decls pdecls lctx in
    let lexprs = lexp_parse_all pexprs lctx in
        (ldecls, lexprs), lctx
;;

let ieval lexps rctx =
    let (ldecls, lexprs) = lexps in
    let rctx = eval_decls ldecls rctx in
    let vals = eval_all lexprs rctx in
        vals, rctx
;;

let _ieval f str  lctx rctx =
    let pres = (f str) in
    let sxps = lex default_stt pres in
    let nods = sexp_parse_all_to_list default_grammar sxps (Some ";") in

    (*  Different from usual typer *)
    let pxps = ipexp_parse nods in
    let lxps, lctx = ilexp_parse pxps lctx in
    let v, rctx = ieval lxps rctx in
        v, lctx, rctx
;;

let ieval_string = _ieval prelex_string
let ieval_file = _ieval prelex_file

(*  Specials commands %[command-name] *)
let rec repl i clxp rctx =
    let ipt = read_input i in
        match ipt with
            (*  Check special keywords *)
            | "%quit"  -> ()
            | "%who"   -> (print_rte_ctx rctx;      repl (i + 1) clxp rctx)
            | "%info"  -> (lexp_context_print clxp; repl (i + 1) clxp rctx)
            | "%calltrace" -> (print_call_trace (); repl (i + 1) clxp rctx)
            (* eval input *)
            | _ -> let (ret, clxp, rctx) = (ieval_string ipt clxp rctx) in
                List.iter (print_eval_result i) ret;
                repl (i + 1) clxp rctx
;;

let arg_files = ref []


(* ./ityper [options] files *)
let arg_defs = [
    (*"-I",
        Arg.String (fun f -> searchpath := f::!searchpath),
        "Append a directory to the search path"*)
];;

let parse_args () =
  Arg.parse arg_defs (fun s -> arg_files:= s::!arg_files) ""

let main () =
    parse_args ();

    let lctx = ref make_lexp_context in
    let rctx = ref make_runtime_ctx in

    (*  Those are hardcoded operation *)
    lctx := add_def "_+_" !lctx;
    lctx := add_def "_*_" !lctx;

    print_string (make_title " TYPER REPL ");
    print_string "      %quit      : leave REPL\n";
    print_string "      %who       : print runtime environment\n";
    print_string "      %info      : print elaboration environment\n";
    print_string "      %calltrace : print call trace of last call \n";
    print_string (make_sep '-');
    flush stdout;

    let nfiles = List.length !arg_files in

    (* Read specified files *)
    List.iteri (fun i file ->
        print_string "  In["; ralign_print_int (i + 1) 2;  print_string "] >> ";
        print_string ("%readfile " ^ file); print_string "\n";

        let (ret, lctx1, rctx1) = ieval_file file (!lctx) (!rctx) in
            lctx := lctx1;
            rctx := rctx1;
            List.iter (print_eval_result i) ret;
        )

        !arg_files;

    flush stdout;

    (* Initiate REPL. This will allow us to inspect interpreted code *)
    repl (nfiles + 1) (!lctx) (!rctx)
;;


main ()
;;
