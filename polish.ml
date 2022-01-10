(** Projet Polish -- Analyse statique d'un mini-langage impératif *)

(** Note : cet embryon de projet est pour l'instant en un seul fichier
    polish.ml. Il est recommandé d'architecturer ultérieurement votre
    projet en plusieurs fichiers source de tailles raisonnables *)

(*****************************************************************************)
(** Syntaxe abstraite Polish (types imposés, ne pas changer sauf extensions) *)

(** Position : numéro de ligne dans le fichier, débutant à 1 *)
type position = int

(** Nom de variable *)
type name = string

(** Opérateurs arithmétiques : + - * / % *)
type op = Add | Sub | Mul | Div | Mod

(** Expressions arithmétiques *)
type expr =
  | Num of int
  | Var of name
  | Op of op * expr * expr

(** Opérateurs de comparaisons *)
type comp =
| Eq (* = *)
| Ne (* Not equal, <> *)
| Lt (* Less than, < *)
| Le (* Less or equal, <= *)
| Gt (* Greater than, > *)
| Ge (* Greater or equal, >= *)

(** Condition : comparaison entre deux expressions *)
type cond = expr * comp * expr

(** Instructions *)
type instr =
  | Set of name * expr
  | Read of name
  | Print of expr
  | If of cond * block * block
  | While of cond * block
and block = (position * instr) list

(** Un programme Polish est un bloc d'instructions *)
type program = block

type sign = Neg | Zero | Pos | Error

module NameTable = Map.Make(String)

let find (pos : position) (var_name:name) (env: 'a NameTable.t) : 'a = 
  try NameTable.find var_name env with
  Not_found -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: La variable " ^ var_name ^ " n'existe pas dans l'environnement")


(***********************************************************************)

(** Lire le fichier en entrée et extraire toutes ses lignes en couplant chaque ligne à son numéro de ligne *)
let read_lines (file:in_channel) : (position * string) list = 
  let rec read_lines_aux (file:in_channel) (acc:(position * string) list) (pos: position): (position * string) list =
    try
      let x = input_line file
      in read_lines_aux file ((pos, x)::acc) (pos+1)
    with End_of_file -> acc
  in List.rev (read_lines_aux file [] 1)

let nb_indentations (line : string) : int =
  if String.split_on_char ' ' (String.trim line) = [""] then 0
  else let mots = String.split_on_char ' ' line
  in let rec nb_indentations_aux mots nb =
    match mots with 
    |[] -> nb
    |m::ms -> if m = "" then nb_indentations_aux ms (nb+1) else nb
  in nb_indentations_aux mots 0

(** Créer à partir d'une chaine donnée, une liste de mots en supprimant tout les blancs qui y figurent *)
let create_mots (s : string) : string list = 
  let rec create_mots_aux l = match l with 
    |[] -> []
    |x::xs -> if x = "" then create_mots_aux xs 
      else x::(create_mots_aux xs)
  in create_mots_aux (String.split_on_char ' ' (String.trim s))

let operateur (s : string) : op option =
  if s = "+" then Some Add
  else if s = "-" then Some Sub
  else if s = "*" then Some Mul
  else if s = "/" then Some Div
  else if s = "%" then Some Mod
  else None;;

(** Lire une expression *)
let rec read_expr (pos : position) (l : string list) : (expr * string list) = match l with 
  | [] -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: expression non valide")
  | hd :: tl ->
    (match operateur hd with
      | None ->
        (match (int_of_string_opt hd) with
          | Some n -> Num n, tl
          | None -> Var hd, tl)
      | Some op -> 
        let exp1, reste1 = read_expr pos tl
        in let exp2, reste2 = read_expr pos reste1
        in (Op (op, exp1, exp2), reste2));;

let condition (s : string) : comp option =
  if s = "=" then Some Eq
  else if s = "<>" then Some Ne
  else if s = "<" then Some Lt
  else if s = "<=" then Some Le
  else if s = ">" then Some Gt
  else if s = ">=" then Some Ge
  else None;;

(** Lire une condition *)
let read_cond (pos : position) (l : string list) : cond =
  let exp1, reste1 = read_expr pos l
  in match reste1 with
  | [] -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: condition non valide")
  | hd :: tl ->
    (match condition hd with
      | None -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: condition non valide")
      | Some comp ->
        let exp2, reste2 = read_expr pos tl
        in if reste2 = [] then (exp1, comp, exp2)
        else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: condition non reconnue"))

let rec read_instr (pos: position) (niv : int) (lines : (position * string) list) : (position * instr * (position * string) list) =
  match lines with 
  |[] -> failwith "Programme vide"
  |x::xs -> 
    match x with p, s -> 
      let mots = create_mots s in match mots with 
        | [] -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe:?????") (* ligne vide *)
        | y::ys -> match y with
          (* | "COMMENT" -> read_instr (pos+1) niv xs *)
          | "READ" -> (match ys with 
            |[v] -> if int_of_string_opt v = None && operateur v = None then (pos+1, Read (v), xs)
              else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: le paramètre de READ doit être un nom de variable")
            |_-> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: READ ne supporte pas plus d'un paramètre"))
          | "PRINT" -> let exp, reste = read_expr pos ys in 
                      if reste = [] then (pos+1, Print (exp), xs)
                      else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: la syntaxe de PRINT n'est pas respectée !")
          | "IF" ->
            let condition = read_cond pos ys
            in let (new_pos1, bloc_if, reste1) = read_block (pos+1) (niv+1) xs
            in let (new_pos2, bloc_else, reste3) = read_else (new_pos1+1) niv reste1 in (new_pos2, If (condition, bloc_if, bloc_else), reste3)  
          | "WHILE" -> (* TODO: traiter le cas ou le bloc de while ou if ou else est vide *)
            let condition = read_cond pos ys (* on lit la condition du while *)
            in let (new_pos, bloc, reste) = read_block (pos+1) (niv+1) xs (* on lit le bloc du while *)
            in (new_pos, While (condition, bloc), reste)
          | _ -> (match ys with 
            | [] -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe:?????")
            | ":="::zs ->
              let exp, reste = read_expr pos zs
              in (if reste = [] then (pos+1, Set(y, exp), xs)
              else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: On peut pas affecter plus d'une expression"))
            | _ -> failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: instruction non reconnue !"))
and read_else (pos : position) (niv : int) (lines : (position * string) list) : (position * block * (position * string) list) =
  match lines with
    | [] -> (pos, [], []) (*(new_pos1, If (condition, bloc_if, []), [])*)
    | (pp,ss)::reste2 ->
      let motss = create_mots ss in (match motss with 
        | [] -> read_else (pos+1) niv reste2
        | "ELSE" :: tl ->
          (if tl = [] then
            let nb_ind = nb_indentations ss
            in if nb_ind mod 2 <> 0 then failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: nombre d'indentations impair !")
            else if (nb_ind/2) <> niv then failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: nombre d'indentations non respecté !")
            else let (new_pos2, bloc_else, reste3) = read_block (pos+1) (niv+1) reste2 (* lire le bloc de ELSE *)
            in (new_pos2, bloc_else, reste3)
          else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: le mot clé ELSE doit être tout seul dans la ligne"))
        | _ -> (pos, [], reste2))
and read_block (pos: position) (niv : int) (lines : (position * string) list) : (position * block * (position * string) list) =
  match lines with 
  | [] -> (pos, [], [])
  | (p, line)::resteLignes ->
    let nb_ind = nb_indentations line
    in if nb_ind mod 2 <> 0 then failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: nombre d'indentations impair !")
    else if (nb_ind/2) > niv then failwith ("Ligne " ^ string_of_int pos ^ ": Erreur de syntaxe: nombre d'indentations non respecté !")
    else if (nb_ind/2) < niv then (pos, [], lines)
    else match String.split_on_char ' ' (String.trim line) with
      | "COMMENT"::_ | [""] -> read_block (pos+1) niv resteLignes
      | _ ->
        let (new_pos1, instruction, reste1) = read_instr pos niv lines (* on lit la première instruction du bloc *)
        in let (new_pos2, bloc, reste2) = read_block new_pos1 niv reste1 (* on lit le reste du bloc *)
        in (new_pos2, ((pos, instruction)::bloc), reste2);;

let read_program (lines : (position * string) list) : program =
  match lines with 
  | [] -> []
  | _ ->
    let (new_pos, bloc, reste) = read_block 1 0 lines
    in bloc;;

let read_polish (filename:string) : program =
  let polish_program = open_in filename
  in let lines = read_lines polish_program
  in read_program lines;;

let print_ind (ind:int) : unit =
  print_string(String.make ind ' ');;

let print_op (opr : op) : unit = 
  match opr with
  |Add -> print_string "+ "
  |Sub -> print_string "- "
  |Mul -> print_string "* "
  |Div -> print_string "/ "
  |Mod -> print_string "% ";;

let rec print_expr (expr : expr) : unit =
  match expr with 
  | Num(v) -> print_int(v)
  | Var(v) -> print_string(v)
  | Op(op,expr1,expr2) -> print_op (op); print_expr(expr1); print_string (" "); print_expr(expr2)

let print_cond (cond : cond) : unit =
  match cond with 
  |(exp1,comp,exp2)-> 
    print_expr(exp1);
    (match comp with
    |Eq -> print_string " = "
    |Ne -> print_string " <> "
    |Lt -> print_string " < "
    |Le -> print_string " <= "
    |Gt -> print_string " > "
    |Ge -> print_string " >= ");
    print_expr(exp2)

let rec print_instr (inst : instr) (ind:int) : unit =
  match inst with
  | Set (v,expr) -> print_string(v ^ " := " );print_expr(expr);print_newline()
  | Read (v) -> print_string("READ "^v);print_newline()
  | Print(expr) -> print_string("PRINT ");print_expr(expr);print_newline()
  | If (cond,block1,block2) ->
    print_string("IF "); print_cond(cond); print_newline();
    print_program block1 (ind+2);
    if (block2 <> []) then print_ind ind; print_string("ELSE\n"); print_program block2 (ind+2)
  | While(cond,block) -> print_string("WHILE ");print_cond(cond);print_newline();print_program block (ind+2)
and print_program (p:program) (ind : int) : unit =
  match p with 
  |[] -> ()
  |(pos,instr)::ps -> print_ind ind; print_instr instr ind;print_program ps ind

let print_polish (p:program) : unit = 
    print_program p 0;;

let rec eval_expr (pos : position) (exp: expr) (envir : int NameTable.t) : int = 
  match exp with 
  | Num (n) -> n
  | Var (v) -> find pos v envir
  | Op (op, expr1, expr2) -> (match op with 
    | Add -> (eval_expr pos expr1 envir) + (eval_expr pos expr2 envir)
    | Sub -> (eval_expr pos expr1 envir) - (eval_expr pos expr2 envir)
    | Mul -> (eval_expr pos expr1 envir) * (eval_expr pos expr2 envir)
    | Div ->
      let expr2_eval = eval_expr pos expr2 envir in if expr2_eval <> 0 then (eval_expr pos expr1 envir) / expr2_eval
      else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur d'évaluation: Division par zéro")
    | Mod ->
      let expr2_eval = eval_expr pos expr2 envir in if expr2_eval <> 0 then (eval_expr pos expr1 envir) mod expr2_eval
      else failwith ("Ligne " ^ string_of_int pos ^ ": Erreur d'évaluation: Modulo par zéro"));;(* TODO: ("Ligne " ^ string_of_int pos ^ ": Erreur d'évaluation: Modulo par zéro")*)

let eval_cond (pos : position) (condition:cond) (envir : int NameTable.t) : bool =
  match condition with
  |(expr1, comp, expr2) -> match comp with
    | Eq -> (eval_expr pos expr1 envir) = (eval_expr pos expr2 envir)
    | Ne -> (eval_expr pos expr1 envir) <> (eval_expr pos expr2 envir)
    | Lt -> (eval_expr pos expr1 envir) < (eval_expr pos expr2 envir)
    | Le -> (eval_expr pos expr1 envir) <= (eval_expr pos expr2 envir)
    | Gt -> (eval_expr pos expr1 envir) > (eval_expr pos expr2 envir)
    | Ge -> (eval_expr pos expr1 envir) >= (eval_expr pos expr2 envir);;

let environment : int NameTable.t = NameTable.empty;; (* L'environnement de notre programme Polish *)
let eval_polish (p:program) : unit = 
  let e : int NameTable.t = NameTable.empty
  in let rec eval_polish_aux (p:program) (env : int NameTable.t) : int NameTable.t = (*int NameTable.t =*)
    match p with
    | [] -> env
    | (pos, Set (v, exp))::reste -> eval_polish_aux reste (NameTable.update v (fun _ -> Some (eval_expr pos exp env)) env)
    | (pos, Read (name))::reste -> print_string (name ^ "?"); eval_polish_aux reste (NameTable.update name (fun _ -> Some (read_int ())) env) (*;print_newline()*)
    | (pos, Print (exp))::reste -> print_int (eval_expr pos exp env); print_newline (); eval_polish_aux reste env 
    | (pos, If (cond, bloc1, bloc2))::reste -> let c = eval_cond pos cond env in if c then eval_polish_aux reste (eval_polish_aux bloc1 env) else eval_polish_aux reste (eval_polish_aux bloc2 env)
    | (pos, While (cond, bloc))::reste -> eval_polish_aux reste (eval_while pos cond bloc env)
  and eval_while (pos : position) (cond:cond) (bloc:program) (env : int NameTable.t) : int NameTable.t =
    if eval_cond pos cond env then (eval_while pos cond bloc (eval_polish_aux bloc env)) else env
  in let nothing (ee : int NameTable.t) : unit = () in nothing (eval_polish_aux p e);;

(* let p = read_polish "prog.p";;
eval_polish p;; *)

let simpl_expr (exp : expr) : expr =
  let rec simpl_expr_aux exp = 
    match exp with 
    | Num(v) -> exp
    | Var(v) -> exp
    | Op(Div, Num 0, expr2) -> Num 0
    | Op(Mul, expr1, Num 0) -> Num 0
    | Op(Mul, Num 0, expr2) -> Num 0
    | Op(Mul, Num 1, expr) 
    | Op(Mul, expr, Num 1) 
    | Op(Add, Num 0, expr) 
    | Op(Add, expr, Num 0) -> (simpl_expr_aux expr)
    | Op(Div, expr1, Num 0) -> Op (Div, simpl_expr_aux expr1, Num 0)
    | Op(Mod, expr1, Num 0) -> Op (Mod, simpl_expr_aux expr1, Num 0)
    | Op(op, Num x, Num y) -> (match op with 
        |Add -> Num (x+y)
        |Sub -> Num (x-y)
        |Mul -> Num (x*y)
        |Div -> Num (x/y)
        |Mod -> Num (x mod y))
    | Op(op,expr1,expr2) -> Op(op, simpl_expr_aux expr1, simpl_expr_aux expr2)
  in let exp_simp = simpl_expr_aux exp 
  in let exp_simp_simp = (simpl_expr_aux exp_simp) 
  in if exp_simp_simp = exp_simp then exp_simp else simpl_expr_aux exp_simp_simp

let simpl_cond (c : cond) : cond =
  match c with (exp1, comp, exp2) -> 
    let exp1_simp = simpl_expr exp1 
    in let exp2_simp = simpl_expr exp2 
    in (exp1_simp, comp, exp2_simp) 
let rec simpl_instr (pos : position) (inst : instr) : (instr * bool) =
  match inst with 
  | Set (v,expr) -> Set (v,simpl_expr expr), false
  | Read (v) -> inst, false
  | Print (expr) -> Print (simpl_expr expr), false
  | If (cond,blockIf,blockElse) -> 
      let cond_simp = simpl_cond cond 
      in (match cond_simp with  
        | (Num (v1), comp, Num (v2)) -> 
          if eval_cond pos cond_simp environment then If (cond_simp, (simpl_program blockIf), []), true
          else If (cond_simp, [], (simpl_program blockElse)), true
        | _ -> If (cond_simp, simpl_program blockIf, simpl_program blockElse), false)
  | While(cond,bloc) -> 
    let cond_simp = simpl_cond cond 
    in (match cond_simp with  
    | (Num (v1), comp, Num (v2)) -> While (cond_simp, simpl_program bloc), not (eval_cond pos cond_simp environment) 
    | _ -> While (cond_simp, simpl_program bloc), false)
and simpl_program (p:program) : program =
  match p with 
  |[] -> []
  |(pos,ins)::ps -> 
    let ins_simp, can_be_deleted = simpl_instr pos ins
    in if can_be_deleted then 
      (match ins_simp with 
       | If (_, b1, b2) -> (simpl_program b1) @ (simpl_program b2) @ (simpl_program ps)
       | _ -> simpl_program ps)
    else ((pos, ins_simp)::(simpl_program ps)) 
let simpl_polish (p:program) : unit = print_polish (simpl_program p)

let vars_polish (p:program) : unit = failwith "TODO";;

let rec union l1 l2 =
  match l2 with
  | [] -> l1
  | hd::tl ->
    if List.mem hd l1 then union l1 tl else union (hd::l1) tl;;

let distribute l1 l2 f g cas_base =
  let rec distribute_aux s1 l =
    match l with 
    | [] -> cas_base
    | s2::q -> g (f s1 s2) (distribute_aux s1 q)
  in let rec distribute_aux2 l1 l2 =
    match l1 with 
    | [] -> cas_base
    | s1::q1 -> g (distribute_aux s1 l2) (distribute_aux2 q1 l2)
  in distribute_aux2 l1 l2;;

let sign_add (l1 : sign list) (l2 : sign list) : sign list =
  let sign_add_aux (s1 : sign) (s2 : sign) : sign list = match s1, s2 with 
    | Error, _ | _, Error -> [Error]
    | Zero, s | s, Zero -> [s]
    | Pos, Pos -> [Pos]
    | Neg, Neg -> [Neg]
    | Pos, Neg | Neg, Pos -> [Zero; Pos; Neg]
  in distribute l1 l2 sign_add_aux union []

let sign_mul (l1 : sign list) (l2 : sign list) : sign list =
  let sign_mul_aux (s1 : sign) (s2 : sign) : sign list = match s1, s2 with
  | Error, _ | _, Error -> [Error]
  | Zero, s | s, Zero -> [Zero]
  | Pos, Pos | Neg, Neg -> [Pos]
  | _, _ -> [Neg] 
  in distribute l1 l2 sign_mul_aux union []

let sign_div (l1 : sign list) (l2 : sign list) : sign list = 
  let sign_inverse s = match s with 
  | Pos | Neg -> s
  | Zero | Error -> Error
  in sign_mul l1 (List.map sign_inverse l2);;

let sign_sub (l1 : sign list) (l2 : sign list) : sign list =
  let sign_negation s = match s with 
    | Pos -> Neg
    | Neg -> Pos
    | Zero | Error -> s
  in sign_add l1 (List.map sign_negation l2);;

let sign_mod (l1 : sign list) (l2 : sign list) : sign list =
  let sign_mod_aux (s1 : sign) (s2 : sign) : sign list = match s1, s2 with
    | Error, _ | _, Error | _, Zero -> [Error]
    | Zero, s -> [Zero]
    | s, _ -> [Zero; s]
  in distribute l1 l2 sign_mod_aux union []
  
let rec sign_expr (pos : position) (exp : expr) (env : (sign list) NameTable.t) : sign list =
  match exp with 
  | Num (n) -> if n = 0 then [Zero] else if n > 0 then [Pos] else [Neg]
  | Var (v) -> find pos v env
  | Op (op, expr1, expr2) -> (match op with 
    | Add -> sign_add (sign_expr pos expr1 env) (sign_expr pos expr2 env)
    | Sub -> sign_sub (sign_expr pos expr1 env) (sign_expr pos expr2 env)
    | Mul -> sign_mul (sign_expr pos expr1 env) (sign_expr pos expr2 env)
    | Div -> sign_div (sign_expr pos expr1 env) (sign_expr pos expr2 env)
    | Mod -> sign_mod (sign_expr pos expr1 env) (sign_expr pos expr2 env))
let intersection l1 l2 =
  let rec intersection_aux l1 l2 acc =
    match l1 with 
      | [] -> acc
      | hd::tl ->
        if List.mem hd l2 then intersection_aux tl l2 (hd::acc) else intersection_aux tl l2 acc
  in intersection_aux l1 l2 []

let condition_satisfied (pos : position) (c : cond) (env : (sign list) NameTable.t) : bool =
  let eq_satisfied l1 l2 =
    let eq_satisfied_aux s1 s2 = match s1, s2 with
      | Pos, Pos | Zero, Zero | Neg, Neg -> true
      | _, _ -> false
    in distribute l1 l2 eq_satisfied_aux (||) false
  in let gt_satisfied l1 l2 =
    let gt_satisfied_aux s1 s2 = match s1, s2 with
      | Error, _ | _, Error -> false
      | Pos, (Pos | Zero | Neg) -> true
      | (Zero | Neg), Neg -> true
      | (Zero | Neg), (Zero | Pos) -> false
    in distribute l1 l2 gt_satisfied_aux (||) false
  in let lt_satisfied l1 l2 = 
    let lt_satisfied_aux s1 s2 = match s1, s2 with
      | Error, _ | _, Error -> false
      | Neg, (Pos | Zero | Neg) -> true
      | (Zero | Pos), Pos -> true
      | (Zero | Pos), (Neg | Zero) -> false
    in distribute l1 l2 lt_satisfied_aux (||) false
  in let ne_satisfied l1 l2 = (lt_satisfied l1 l2) || (gt_satisfied l1 l2)
  in let ge_satisfied l1 l2 = (gt_satisfied l1 l2) || (eq_satisfied l1 l2)
  in let le_satisfied l1 l2 = (lt_satisfied l1 l2) || (eq_satisfied l1 l2)
  in match c with 
    | exp1, Eq, exp2 -> eq_satisfied (sign_expr pos exp1 env) (sign_expr pos exp2 env)
    | exp1, Ne, exp2 -> ne_satisfied (sign_expr pos exp1 env) (sign_expr pos exp2 env)
    | exp1, Lt, exp2 -> lt_satisfied (sign_expr pos exp1 env) (sign_expr pos exp2 env)
    | exp1, Le, exp2 -> le_satisfied (sign_expr pos exp1 env) (sign_expr pos exp2 env)
    | exp1, Gt, exp2 -> gt_satisfied (sign_expr pos exp1 env) (sign_expr pos exp2 env)
    | exp1, Ge, exp2 -> ge_satisfied (sign_expr pos exp1 env) (sign_expr pos exp2 env)

let sign_polish (p:program) : unit =
  let e : (sign list) NameTable.t = NameTable.empty
  in let divbyzero = false in let first_time_divbyzero = 0
  in let rec sign_polish_aux (p:program) (env : (sign list) NameTable.t) : (sign list) NameTable.t = 
    match p with
    | [] -> env
    | (pos, Set (v, exp))::reste -> 
        let exp_sign = sign_expr pos exp env
        in let divbyzero, first_time_divbyzero = if List.mem Error exp_sign && not divbyzero then true, pos else divbyzero, first_time_divbyzero
        in sign_polish_aux reste (NameTable.update v (fun _ -> Some exp_sign) env)
    | (pos, Read (name))::reste -> sign_polish_aux reste (NameTable.update name (fun _ -> Some [Neg; Zero; Pos]) env)
    | (pos, Print (exp))::reste ->
      let exp_sign = sign_expr pos exp env
      in let divbyzero, first_time_divbyzero = if List.mem Error exp_sign && not divbyzero then true, pos else divbyzero, first_time_divbyzero
      in env
    | (pos, If (cond, bloc1, bloc2))::reste ->
      let (exp1, _, exp2) = cond in
      let exp1_sign, exp2_sign = sign_expr pos exp1 env, sign_expr pos exp2 env
      in let divbyzero, first_time_divbyzero =
        if (List.mem Error exp1_sign || List.mem Error exp2_sign) && not divbyzero then true, pos
        else divbyzero, first_time_divbyzero
      in if condition_satisfied pos cond env then sign_polish_aux reste (sign_polish_aux bloc1 env) 
      else sign_polish_aux reste (sign_polish_aux bloc2 env)
    | (pos, While (cond, bloc))::reste ->
      let (exp1, _, exp2) = cond
      in let exp1_sign, exp2_sign = sign_expr pos exp1 env, sign_expr pos exp2 env
      in let divbyzero, first_time_divbyzero =
        if (List.mem Error exp1_sign || List.mem Error exp2_sign) && not divbyzero then true, pos
        else divbyzero, first_time_divbyzero
      in sign_polish_aux reste (sign_while pos cond bloc env)
  and sign_while (pos : position) (cond:cond) (bloc:program) (env : (sign list) NameTable.t) : (sign list) NameTable.t =
    if condition_satisfied pos cond env then (sign_while pos cond bloc (sign_polish_aux bloc env)) else env

  in let sign_to_string s = match s with Pos -> "+" | Neg -> "-" | Zero -> "0" | Error -> "!"
  in let sign_list_to_string_list l = List.map sign_to_string l
  in let print_sign_list l = List.iter print_string (sign_list_to_string_list l)
  in NameTable.iter (fun k v -> print_string k; print_sign_list v; print_newline ()) (sign_polish_aux p e);
  if divbyzero then Printf.printf "divbyzero %d" first_time_divbyzero else print_string "safe";;

let usage () =
  print_string "Polish : analyse statique d'un mini-langage\n";
  print_string "usage: run [options] <file>\n telle que les options sont:\n
  -reprint : lire et réafficher le programme polish\n
  -eval : évaluer le programme polish\n
  -simpl : simplifier un programme polish en effectuant la propagation des constantes et l'élimination des blocs morts\n
  -vars : TODO: \n
  -sign : TODO: \n";;


let main () =
  match Sys.argv with
  | [|_;"-reprint";file|] -> print_polish (read_polish file)
  | [|_;"-eval";file|] -> eval_polish (read_polish file)
  | [|_;"-simpl";file|] -> simpl_polish (read_polish file)
  | [|_;"-vars";file|] -> simpl_polish (read_polish file)
  | [|_;"-sign";file|] -> simpl_polish (read_polish file)
  | _ -> usage ()

(* lancement de ce main *)
let () = main ();;
