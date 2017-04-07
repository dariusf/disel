From mathcomp.ssreflect
Require Import ssreflect ssrbool ssrnat eqtype ssrfun seq.
From mathcomp
Require Import path.
Require Import Eqdep.
Require Import pred prelude idynamic ordtype finmap pcm unionmap heap coding domain.
Require Import Freshness State EqTypeX Protocols Worlds NetworkSem Rely.
Require Import Actions.
Require Import SeqLib.
Require Import QueryProtocol.
Require Import NewStatePredicates.
Require Import Actions Injection Process Always HoareTriples InferenceRules.

Section QueryHooked.

(* Constructing the composite world *)

Variables (lq : Label) (pc : protocol).
Variable Data : Type.
Variable qnodes : seq nat.
Variable serialize : Data -> seq nat.
Variable deserialize : seq nat -> Data.
Hypothesis ds_inverse : left_inverse serialize deserialize.
Definition pq := QueryProtocol qnodes serialize lq.

Variable core_state_to_data : heap -> option Data.

(* The query hook extracts certain data from the the core protocol *)
(* local state if it's present there. *)
Definition query_hook : hook_type :=
  fun hc hq ms to =>
    if core_state_to_data hc is Some d
    then exists rid, ms = rid :: serialize d
    else True.

Definition query_hookz := (1, (plab pc), (plab pq, tresp)) \\-> query_hook.

Definition W : world := ((plab pc \\-> pc) \+ (plab pq \\-> pq), query_hookz).

Hypothesis Lab_neq: lq != (plab pc).
Hypothesis Nodes_eq: forall d, nodes pc d =i qnodes.

Lemma W_valid : valid W.
Proof.
apply/andP; split=>/=; last by rewrite um_validPt.
case: validUn=>//; rewrite ?um_validPt// =>l.
rewrite !um_domPt !inE=>/eqP=>Z; subst l=>/eqP=>Z.
by subst lq; move/negbTE: Lab_neq; rewrite eqxx.
Qed.

Lemma W_complete : hook_complete W.
Proof.
move=>z lc ls t/=; rewrite um_domPt inE=>/eqP[]_<-<-_.
rewrite !domUn !inE/= !um_domPt !inE !eqxx/= orbC.
by case/andP:W_valid=>->_.
Qed.

Lemma W_dom : dom W.1 =i [:: plab pc; lq].
Proof.
move=>z/=; rewrite domUn !inE/=; case/andP: W_valid=>->/=_. 
by rewrite !um_domPt !inE; rewrite -!(eq_sym z).
Qed.

Lemma eqW : 
  W = (plab pc \\-> pc, Unit) \+ (plab pq \\-> pq, Unit) \+ (Unit, query_hookz).
Proof. by rewrite /PCM.join/=/W !unitL !unitR. Qed.

Lemma eqW' : 
  W = (plab pc \\-> pc, Unit) \+ ((plab pq \\-> pq, Unit) \+ (Unit, query_hookz)).
Proof. by rewrite eqW joinA. Qed.


Lemma injW : injects (plab pc \\-> pc, Unit) W query_hookz.
Proof.
rewrite eqW; apply:injectL=>//; try by move=>????/=; rewrite dom0 inE.
- by rewrite -eqW W_valid.
- move=>z lc ls t; rewrite um_domPt inE.
  case/eqP=>Z1 Z2 Z3 Z4; subst ls z lc t.
  rewrite !domUn !inE !um_domPt !inE !eqxx/=.
  by case/andP:W_valid=>/=->_/=; rewrite orbC.
move=>l; rewrite um_domPt inE=>/eqP=><-.
move=>z lc ls t; rewrite um_domPt inE=>/eqP[]_ _<-_.  
apply/negbT; apply/eqP=>Z; subst lq; move/negbTE: Lab_neq.
by rewrite eqxx.
Qed.

Lemma prEqC : getProtocol W (plab pc) = pc.
rewrite /getProtocol/W/= findUnL; last by case/andP: W_valid.
by rewrite um_domPt inE eqxx um_findPt.
Qed.

Lemma prEqQ : getProtocol W lq = pq.
Proof.
rewrite /getProtocol/W/= findUnR; last by case/andP: W_valid.
by rewrite um_domPt inE eqxx um_findPt.
Qed.

(* Finished constructing the composite world *)

Variable this : nid.
Hypothesis this_in_qnodes: this \in qnodes.

(* Now playing with the stability of the desired invariant *)

(* Core getters *)
Notation getSc s := (getStatelet s (plab pc)).
Notation getLc s := (getLocal this (getSc s)).
Notation getLc' s n := (getLocal n (getSc s)).

(* Query getters *)
Notation getSq s := (getStatelet s (plab pq)).
Notation getLq s := (getLocal this (getSq s)).

(* Describing the response-permissions of our recipient *)
Definition holds_res_perms d n (pp : nat -> Prop) :=
  exists (reqs resp : seq (nid * nat)),
    getLocal n d = qst :-> (reqs, resp) /\
    forall rn, (this, rn) \in resp -> pp rn.

(* TODO: define the channel criterion *)
Definition request_msg (t: nat) (_ : seq nat) :=  t == treq.
Definition response_msg (t: nat) (_ : seq nat) := t == tresp.

(************************************************)
(*        Predicate for initial state           *)
(************************************************)

Definition query_init_state to s :=
  [/\ to \in qnodes,
      holds_res_perms (getSq s) to (fun _ : nat => false),
      no_msg_from_to' this to request_msg (dsoup (getSq s)) &
      no_msg_from_to' to this response_msg (dsoup (getSq s))].    

Lemma query_init_step z to s s' :
  this != z -> query_init_state to s ->
  network_step W z s s' -> query_init_state to s'.
Proof.
move=> N H S; case: (step_coh S)=>C1 _.
case: S; [by case=>_<- |
  move=>l st H1 to'/= msg n H2 H3 C H4 H5 H6->{s'}|
  move=>l rt H1 i from pf H3 C msg H2/=[H4]H5->{s'}];
rewrite -(cohD C) W_dom !inE in H3;
case/orP:H3=>/eqP=>Z; subst l;
(* Get rid of irrelevant cases: by means of a tactic *)                     
rewrite /query_init_state/getStatelet ?findU ?(negbTE Lab_neq) ?eqxx//= (cohS C1).
case B: (to == z); last first.
(* rewrite /query_init_state/holds_res_perms/no_msg_from_to'/getLocal/=. *)
(* rewrite findU B/=. *)
(* case: H. *)
(* - rewrite /query_init_state/holds_res_perms/no_msg_from_to'/getStatelet ?findU ?eqxx ?(negbTE Lab_neq)/=. *)
Admitted.

Lemma query_init_rely to s s' :
  query_init_state to s ->
  network_rely W this s s' -> query_init_state to s'.
Proof.
move=>H1 [n]H2; elim: n s H2 H1=>/=[s | n Hi s]; first by case=>Z _; subst s'.
case=>z[s1][N]H1 H2 H3; apply: (Hi s1 H2).
by apply: (query_init_step _ _ _ _ N H3 H1).
Qed.  

(***************************************************)
(*  Query-specific intermediate predicate          *)
(***************************************************)

(* 1. We've just sent our stuff. *)
Definition msg_just_sent d (reqs resp : seq (nid * nat)) req_num to :=
  [/\ getLocal this d = qst :-> (reqs, resp),
   no_msg_from_to' to this response_msg (dsoup d), 
   (to, req_num) \in reqs, 
   msg_spec' this to treq ([:: req_num]) (dsoup d) &
   holds_res_perms d to (fun _ => false)].

(* 2. Our request is received but not yet responded. *)
Definition msg_received d (reqs resp : seq (nid * nat)) req_num to :=
  [/\ getLocal this d = qst :-> (reqs, resp),
   (to, req_num) \in reqs,
   no_msg_from_to' this to request_msg (dsoup d),
   no_msg_from_to' to this response_msg (dsoup d) &
   holds_res_perms d to (fun rn => rn == req_num)].

(* 3. Our request is responded. *)
Definition msg_responded d (reqs resp : seq (nid * nat)) req_num to data :=
  [/\ getLocal this d = qst :-> (reqs, resp),
   (to, req_num) \in reqs,
   no_msg_from_to' this to request_msg (dsoup d),
   msg_spec' to this tresp (req_num :: serialize data) (dsoup d) &
   holds_res_perms d to (fun _ => false)].

(* 4. Stability of the local state of a core protocol, 
      to be proved separately *)

(* A local assertion ensuring stability of the core_state_to_data *)
Variable local_indicator : Pred heap.

Hypothesis core_state_stable_step : forall z s data s' n,
  this != z -> network_step (plab pc \\-> pc, Unit) z s s' ->
  n \in qnodes ->
  local_indicator (getLc s) ->
  core_state_to_data (getLc' s n) = Some data -> 
  core_state_to_data (getLc' s' n) = Some data.

Lemma prEqC' : (getProtocol (plab pc \\-> pc, Unit) (plab pc)) = pc.
Proof. by rewrite /getProtocol gen_findPt/=. Qed.
  
(* Showing that the core assertion is stable *)
Lemma core_state_stable_step_W s data s' z :
  this != z ->
  network_step W z s s' ->
  z \in qnodes ->
  local_indicator (getLc s) ->
  core_state_to_data (getLc' s z) = Some data -> 
  core_state_to_data (getLc' s' z) = Some data.
Proof.
move=>N H2 G L H1; move:(step_coh H2)=>[C1 C2].
rewrite eqW' in C1 C2.
move: (projectSE C1)(projectSE C2)=>E1 E2.
set s1 := projectS (plab pc \\-> pc, Unit) s in E1.
set s2 := projectS ((plab pq \\-> pq, Unit) \+ (Unit, query_hookz)) s in E1.
set s1' := projectS (plab pc \\-> pc, Unit) s' in E2.
set s2' := projectS ((plab pq \\-> pq, Unit) \+ (Unit, query_hookz)) s' in E2.
move: (C1) (C2) =>C1' C2'.
rewrite E1 E2 in H2 C1' C2'.
have [X X'] : (forall z, getLc' s z  = getLc' s1 z) /\
              (forall z, getLc' s' z = getLc' s1' z).
- by split; move=>z'; rewrite /getStatelet find_um_filt um_domPt inE eqxx.
case: (sem_split injW _ _ H2).
- apply: (@projectS_cohL (plab pc \\-> pc, Unit)
                         ((plab pq \\-> pq, Unit) \+ (Unit, query_hookz)))=>//.
  by move=>????; rewrite dom0 inE.
- suff H : hook_complete (plab pc \\-> pc, Unit).
  apply: (@projectS_cohL _ ((plab pq \\-> pq, Unit)\+(Unit, query_hookz)))=>//.
  by move=>????; rewrite dom0 inE.
- case=>H _; rewrite X'; rewrite !X in L H1.
  by apply: (core_state_stable_step _ _ _ _ _ N H _ L H1).
by case=>_ E; rewrite X'; rewrite !X in L H1; rewrite -E.
Qed.

Lemma core_state_stable s data s' z :
  network_rely W this s s' ->
  z \in qnodes ->
  local_indicator (getLc s) ->
  core_state_to_data (getLc' s z) = Some data -> 
  core_state_to_data (getLc' s' z)  = Some data.
Proof.
move=> R Z L. move: (L); rewrite -(@rely_loc' _ _ (plab pc) s s' R)=>L'.
move: R Z L.
case B: (this == z); [move/eqP: B=>B|move/negbT: B=>B].
- by subst z=>R; rewrite (@rely_loc' _ _ (plab pc) s s' R).
move=>[n]H2 H1; elim: n s H2=>/=[s | n Hi s]; first by case=>Z _; subst s'.
case=>y[s1][N]G1 G2 G3 G4; apply: (Hi s1 G2).
- by rewrite /getLocal -(step_is_local (plab pc) G1 N). 
case B' : (z == y); [move/eqP: B'=>B' | move/negbT: B'=>B'].
- by subst y; apply: (core_state_stable_step_W _ _ _ _ B G1 _ G3).
by rewrite /getLocal -(step_is_local (plab pc) G1 B').
Qed.

(***********************************************************)
(* A rely-inductive predicate describing the message story *)
(***********************************************************)
Definition msg_story s req_num to data reqs resp :=
  [/\ core_state_to_data (getLc' s to) = Some data,
     local_indicator (getLc s) & 
     let: d := getSq s in
     [\/ msg_just_sent d reqs resp req_num to,
      msg_received d reqs resp req_num to |
      msg_responded d reqs resp req_num to data]].

Lemma msg_story_step req_num to data reqs resp z s s' :
  this != z ->
  msg_story s req_num to data reqs resp ->
  network_step W z s s' ->
  msg_story s' req_num to data reqs resp.
Proof.
move=> N H S; split=>//.
(* - case: H=>H _; apply: (core_state_stable s data s')=>//. *)
(*   by exists 1, z, s'; split=>//=; split=>//; case/step_coh: S.  *)
(* TODO: figure out how not to consider transitions in other worlds *)
(* case: S; [by case=>_<-; case: H| *)
(*  move=>l st H1 to'/= msg n H2 H3 C H4 H5 H6->{s'}| *)
(*  move=>l rt H1 i from pf H3 C msg H2/=[H4]H5->{s'}]; *)
(*  rewrite -(cohD C) W_dom !inE in H3; *)
(*  case/orP:H3=>/eqP=>Z; subst l; *)
(*  try by rewrite /getStatelet findU (negbTE Lab_neq)/=; case: H.  *)
(* Okay, now let's deal with interesting cases... *)

(* It's a send-transition *)
(* set d := getStatelet s lq; move: prEqQ st H1 H2 H4 H5 H6. *)
(* rewrite /get_st=>-> st H1/= H2 H4 H5 H6. *)
(* rewrite /getStatelet findU eqxx/= (cohS C)/=. *)
(* case: H1; [move|case=>//]; move=>Z; subst st. *)
(* - admit. (* Boring transition *) *)
(* - case B: ((z == to) && (to' == this)). *)
(*   case/andP:B=>/eqP Z/eqP Z'; subst z to'. *)
(*   case: H=>G1 G2. *)
(*   case:G2; [by admit | | by admit]. *)
(*   rewrite /all_hooks_fire/query_hookz/query_hook in H5.  *)
(* admit. *)
(* admit. *)
(* (* It's a receive-transition *) *)
(* set d := getStatelet s lq. *)
(* move: prEqQ (coh_s lq C) rt pf H1 H2 H4 H5. *)
(* rewrite /get_rt=>-> Cq rt pf H1 H2 H4 H5. *)
(* rewrite /getStatelet findU eqxx/= (cohS C)/=. *)
(* case: H1; [move|case=>//]; move=>Z; subst rt. *)

Admitted.

Lemma msg_story_rely req_num to data reqs resp s s2 :
  msg_story s req_num to data reqs resp ->
  network_rely W this s s2 ->
  msg_story s2 req_num to data reqs resp.
Proof.
move=>H1 [n]H2; elim: n s H2 H1=>/=[s | n Hi s]; first by case=>Z _; subst s2.
case=>z[s1][N]H1 H2 H3; apply: (Hi s1 H2).
by apply: (msg_story_step _ _ _ _ _ _ _ _ N H3 H1).
Qed.  


(**************************************************************)
(*********************  Query Programs ************************)
(**************************************************************)


(********************** Sending request ***********************)

Program Definition send_req rid to :=
  act (@send_action_wrapper W pq this (plab pq) prEqQ
                            (qsend_req qnodes) _ [:: rid] to).
Next Obligation. by rewrite !InE; left. Qed.

Program Definition send_req_act (rid : nat) (to : nid) :
  {rrd : seq (nid * nat) * seq (nid * nat) * Data}, DHT [this, W]
   (fun i =>
      let: (reqs, resp, data) := rrd in 
      [/\ getLq i = qst :-> (reqs, resp),
       local_indicator (getLc i),
       rid = fresh_id reqs,
       query_init_state to i &
       core_state_to_data (getLc' i to) = Some data],
   fun (r : seq nat) m => 
     let: (reqs, resp, data) := rrd in 
     [/\ getLq m = qst :-> ((to, rid) :: reqs, resp),
      local_indicator (getLc m),
      r = [:: rid] &
      msg_story m rid to data ((to, rid) :: reqs) resp])
  :=
    Do (send_req rid to).

Next Obligation.
apply: ghC=>s0[[reqs resp] d]/=[P1] Pi P2 Q P3 C0.
apply: act_rule=>i1 R0; split=>//=[|r i2 i3[Hs]St R2].
(* Precondition *)
- rewrite /Actions.send_act_safe/=.
  move/rely_coh: (R0)=>[_ C1]; rewrite -(rely_loc' _ R0) in P1.
  move: (coh_coh lq C1); rewrite prEqQ=>Cq1; 
  split=>//; [split=>//; try by case:Q| | ].
  + by exists Cq1; rewrite /QueryProtocol.send_req_prec (getStK _ P1)/= P2.
  + by apply/andP; split=>//; rewrite -(cohD C1) W_dom !inE eqxx orbC.
  move=>z lc hk; rewrite find_um_filt eqxx /query_hookz/==>/sym.
  by move/find_some; rewrite um_domPt !inE=>/eqP. 
(* Postcondition *)
have N: network_step W this i1 i2.
- apply: (Actions.send_act_step_sem _ _ St)=>//; first by rewrite prEqQ.
  by rewrite !InE; left.
rewrite (rely_loc' _ R2).
rewrite -(rely_loc' _ R0) in P1.
move/rely_coh: (R0)=>[_]C1; move: (coh_coh lq C1);rewrite prEqQ=>Cq1.
case: St=>->[h]/=[].
rewrite/QueryProtocol.send_step/QueryProtocol.send_step_fun/=.
rewrite (proof_irrelevance (QueryProtocol.send_safe_coh _) Cq1).
rewrite (getStK _ P1); case=>Z Z'; subst h rid.
rewrite Z' locE; last first;
[by apply: cohVl Cq1| by apply: cohS C1|
   by rewrite -(cohD C1) W_dom !inE eqxx orbC|].
have X : getLc i3 = getLc s0.
- rewrite (rely_loc' _ R2) -(rely_loc' _ R0) Z'.
  by rewrite /getStatelet findU; move/negbTE: Lab_neq; rewrite eq_sym=>->.
(* Massaging the hypotheses. *)
split=>//; try by rewrite X//.
apply: (msg_story_rely _ _ _ _ _ i2)=>//.
have E: core_state_to_data (getLc' i1 to) = core_state_to_data (getLc' i2 to).
- case B: (to == this); [move/eqP:B=>Z; subst to | ]; last first.
  + by rewrite /getLocal (step_is_local _ N)=>//; move/negbT: B.
  subst i2; rewrite ![getLc' _ _]/getLocal /getStatelet/=.
  by rewrite findU; move/negbTE: Lab_neq; rewrite eq_sym=>->.
move: (query_init_rely _ s0 i1 Q R0)=>{Q}Q; subst i2.
move: (Q)=>[Q1 Q2 Q3 Q4].
move: (core_state_stable _ _ _ _ R0 Q1 Pi P3); rewrite E=>{E}E.
clear N R2 Q C0 X i3 P3.
split=>//.
- rewrite /getStatelet findU; move/negbTE: Lab_neq; rewrite eq_sym=>->//=.
  by rewrite (rely_loc' _ R0).
constructor 1. 
split=>//; rewrite ?inE ?eqxx=>//=.
- rewrite locE=>//; 
  [by rewrite -(cohD C1) W_dom !inE eqxx orbC|
   apply: cohS C1|by apply: cohVl Cq1].
(* Prove the interesting transition *)
- move=>m t c; rewrite /getStatelet findU eqxx (cohS C1)/=.
  set ds := (dsoup _); rewrite findUnR; last first.
  by rewrite valid_fresh; apply: cohVs Cq1.
  rewrite gen_domPt !inE/=; case:ifP=>[/eqP<-|_]; last by apply: Q4.
  by rewrite um_findPt; case=><-. 
(* TODO: refactor this into a separate lemma about those state predicates *)
- rewrite /getStatelet findU eqxx (cohS C1)/=.
  set ds := (dsoup _).
  exists (fresh ds); split=>//.
  + exists QueryProtocol.treq, [:: fresh_id reqs].
    rewrite findUnR; last by rewrite valid_fresh; apply: cohVs Cq1.
    by rewrite um_domPt inE eqxx um_findPt !eqxx/=. 
  move=>x[t][c].
  rewrite findUnR; last by rewrite valid_fresh; apply: cohVs Cq1.
  case:ifP=>[|_[]]; first by rewrite um_domPt inE=>/eqP->.
  by move/(Q3 x t c)=>X/andP[/eqP]Z; subst t. 
set ds := (dsoup _).
case: Q2=>reqs'[resp'][G1 G2].
case X: (to == this).
- exists ((this, fresh_id reqs) :: reqs), resp; move/eqP:X=>X; subst to.
  rewrite P1 in G1; have V: valid (qst :-> (reqs, resp)) by [].
  case: (hcancelPtV V G1)=>Z1 Z2; subst reqs' resp'=>{G1}.
  split=>//; rewrite locE//; last first;
    [by apply: cohVl Cq1| by apply: cohS C1|
       by rewrite -(cohD C1) W_dom !inE eqxx orbC].
exists reqs', resp'; split=>//.
rewrite /getStatelet findU eqxx (cohS C1)/=.
by rewrite /getLocal findU X. 
Qed.

(******************** Receiving request *********************)


(*

TODO (in arbitrary order):

[1]. Prove injective "core_state_stable" -- done.

2. Prove quasi-inductive property "query_init_step"

3. Prove quasi-inductive property "msg_story_step"

4. Specify and verify the read-action. 

------------------------------------

Old TODO

0. Refine no_msg_from_to for specific tags, otherwise the invariant 
   doesn't hold.

1. Finish showing that this property is preseverd by the joined rely;

2. Make sure that this is the property we actually need in order to
   verify the composite program; that is, write the program code and
   verify it.

3. Check that core_state_stable indeed holds just like this in 2PC 
   inductive invariant.

4. Define the generic procedure and make sure that the injection rule 
   works as it should with respect to the core protocol!!!

*)


End QueryHooked.

