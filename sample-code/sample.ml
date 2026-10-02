(* ============================================================================
 * Solarized Dark Showcase: OCaml (OCaml 5.x Modular Type-Safe Telemetry)
 * ============================================================================ *)

open Printf

type severity =
  | Info
  | Warn
  | Critical
  | Fatal

type 'a envelope = {
  id : string;
  payload : 'a;
  mutable retries : int;
  active : bool;
  tag : char;
}

type sample = {
  node : string;
  score : float;
  state : [ `Active | `Draining | `Offline ];
}

module type TELEMETRY = sig
  val clamp_score : float -> float -> float -> float
  val classify : sample -> severity option
  val process_batch : sample list -> (string, string) result
end

module Collector : TELEMETRY = struct
  let clamp_score lower upper value =
    if value < lower then lower
    else if value > upper then upper
    else value

  let classify (item : sample) : severity option =
    match item.state with
    | `Offline -> None
    | `Draining when item.score >= 50.0 -> Some Warn
    | `Active | `Draining ->
        let bounded = clamp_score 0.0 100.0 item.score in
        if bounded >= 90.0 then Some Critical
        else if bounded >= 70.0 then Some Warn
        else Some Info

  let rec sum_scores (acc : float) (items : sample list) : float =
    match items with
    | [] -> acc
    | head :: tail ->
        let delta =
          match classify head with
          | Some Critical -> head.score *. 1.5
          | Some Warn | Some Info | Some Fatal -> head.score
          | None -> 0.0
        in
        sum_scores (acc +. delta) tail

  let process_batch (batch : sample list) : (string, string) result =
    match batch with
    | [] -> Error "empty batch"
    | items ->
        let total =
          List.fold_left
            (fun acc s -> if s.score > 0.0 then acc +. s.score else acc)
            0.0
            items
        in
        let count = List.length items in
        let summary = Printf.sprintf "node_count=%d total=%.2f\n" count total in
        Ok summary
end
