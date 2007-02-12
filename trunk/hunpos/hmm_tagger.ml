module SNgramTree = Ngramtree.Make(Mfhash.String)

type observation = {word : string; 
					mutable seen : bool; 
					mutable oov : bool; 
					mutable anals : string list;
					mutable guessed: (string * float ) list;
					}

let load filename   morphtable tag_order emission_order = 
	let ic = open_in filename in
	let  (ttree, otree, suffixtrie, vocab) = Marshal.from_channel ic in
	close_in ic;


(*	Printf.eprintf "calculating tag transition lamdas\n";
*)	let tlamdas = SNgramTree.calculate_lambdas ttree ttree (tag_order + 1) in
(*	Array.iteri (fun i v -> Printf.eprintf "%d = %f\n" i v) tlamdas; 
*)	
(*	Printf.eprintf "calculating observation lamdas\n";
*)	let olamdas = SNgramTree.calculate_lambdas otree ttree (emission_order + 1) in
(*	Array.iteri (fun i v -> Printf.eprintf "%d = %f\n" i v) olamdas; 
*)
(*	Printf.eprintf "deriving observation probabilities\n";
*)	let potree = SNgramTree.probtree otree ttree olamdas in
	(*
	SNgramTree.iter  (fun l freq -> Printf.printf "%s\t%f\n" (String.concat " " l) freq ) potree;
	*)	
(*	Printf.eprintf "deriving tag transition probabilities\n";
*)	let pttree = SNgramTree.probtree ttree ttree tlamdas in
(*	SNgramTree.iter  (fun l freq -> Printf.printf "%s\t%f\n" (String.concat " " l) freq ) pttree;	
	Printf.eprintf "model is built.\n";
*)	
	prerr_endline "calculating theta";
	let theta = Suffix_guesser.theta suffixtrie in
	prerr_string "theta = "; prerr_float theta; prerr_newline ();
	
	let tagprobs = Suffix_guesser.guesser_from_trie suffixtrie theta vocab in
	let a = tagprobs "Zam�rdiba"  in
	List.iter (fun (t,p) -> Printf.printf "%s %f\n" (t) p) a;
	

let module State = struct
	type t = string Ngram.t
	let compare ng1 ng2  = Ngram.compare ng1 ng2 tag_order
end 
in

let module StateViterbi = Viterbi.Make(Ocamap.Make(State))
in

let module SNgramTree = Ngramtree.Make(Mfhash.String)
in

let start_state = "<s>" :: "<s>" :: [] in

let next obs =
		let w = obs.word in
	
		if w = "<s>" then
			let transition from = ((Ngram.add "<s>" from),SNgramTree.wordprob pttree from "<s>")::[] in
			let emission state = 0.0 in
			(transition, emission)
		else 
		let (oov, anals) = try (false, Morphtable.analyze morphtable w) with Not_found -> (true, []) in
		obs.oov <- oov ; 
		obs.anals <- anals;	
		try 
			let obs_node = SNgramTree.move_to_child potree w in
			obs.seen <- true;
			
			(* milyen tagjei lehetnek *)
			let tags = SNgramTree.edges obs_node in
			
			let transition from = 
				List.map (fun tag -> 
							let next_state = Ngram.add tag from in
							let tp = SNgramTree.wordprob pttree from tag in
							
							(next_state, (tp )) 
				) tags
			in
			let emission state =
				SNgramTree.seq_prob obs_node state 
			in
			(transition, emission)		
					
		with Not_found -> (* not seen word *)
			obs.seen <- false;
			if not (obs.oov) && List.length obs.anals = 1 then
				let transition from = List.map (fun tag  ->
													let next_state = Ngram.add tag from in
													let tp = SNgramTree.wordprob pttree from tag in
													(next_state, tp )) obs.anals
				in 
				let emission state = 0.0
				in
				(transition, emission)
			else begin				
			let gtags_probs = tagprobs  w in
			obs.guessed <- gtags_probs;
			(* csak a morphtable alta adott elemzeseket fogadjuk el *)
			let tags_probs =
				if obs.oov then gtags_probs
				else let l =List.filter (fun (tag, _) -> List.mem tag obs.anals) gtags_probs in
				if List.length l = 0 then begin Printf.printf "hunmorph hiba?: %s\n " w ;
				List.iter (fun (t, p) -> Printf.printf "%s %f " t p) gtags_probs;
				List.iter (fun t -> Printf.printf "%s " t ) obs.anals; Printf.printf "\n";
				 gtags_probs end else l 
			in	
		
			let transition 	from = List.map (fun (tag,logprob) -> 
							let next_state = Ngram.add tag from in
							let tp = SNgramTree.wordprob pttree from tag in
							(next_state, (tp )) 
				) tags_probs			
			in
			let emission state =
				let tag = List.hd state in
				List.assoc tag tags_probs 
			in
			(transition, emission)		
			end
		
in		
		

let tag_sentence words  =

	let word2observation w = { word = w; seen = true; oov = false; anals = []; guessed = []} in

	let observations = 	List.map (word2observation) (List.rev ( "<s>"::words))  in
	let state_seq = StateViterbi.decode next start_state observations in
	( List.tl (List.rev  observations), List.tl (List.rev (List.map  (Ngram.newest) (state_seq))))
		
 in tag_sentence